# 복제 전체 파이프라인

> 출처:  
> `Engine/Source/Runtime/Engine/Private/NetDriver.cpp`  
> `Engine/Source/Runtime/Engine/Private/DataChannel.cpp`  
> `Engine/Source/Runtime/Engine/Private/DataReplication.cpp`

---

## 복제는 서버가 주도한다

클라이언트는 요청하지 않는다. 서버가 매 틱마다 "이 클라이언트한테 뭘 보내야 하지?"를 계산해서 보낸다.

```
[서버 매 틱]
UNetDriver::TickFlush()                      NetDriver.cpp:1128
  └─ ServerReplicateActors(DeltaSeconds)
       ├─ ServerReplicateActors_BuildConsiderList()    ← 1단계: 후보 목록
       └─ [각 클라이언트 Connection 순회]
            └─ ServerReplicateActors_ForConnection()   ← 2단계: 연결별 처리
                 ├─ PrioritizeActors()                 ← 3단계: 우선순위 정렬
                 └─ [각 Actor] ActorChannel::ReplicateActor()  ← 4단계: 실제 복제
```

---

## 1단계 — ConsiderList 구성

`ServerReplicateActors_BuildConsiderList()` (NetDriver.cpp:5111)

복제 대상이 될 수 있는 Actor 목록을 만든다. 다음 조건 중 하나라도 해당하면 스킵한다.

```cpp
// NetDriver.cpp:5127
if (!ActorInfo->bPendingNetUpdate && World->TimeSeconds <= ActorInfo->NextUpdateTime)
    continue;  // 아직 업데이트 시간이 안 됐음 (NetUpdateFrequency 기반)

if (Actor->GetRemoteRole() == ROLE_None)
    continue;  // 복제 안 하는 Actor

if (!Actor->IsActorInitialized())
    continue;  // PostInitializeComponents 아직 안 됨

if (IsDormInitialStartupActor(Actor))
    continue;  // 초기 Dormant 상태
```

**핵심**: `NextUpdateTime`은 `NetUpdateFrequency`로 계산된다.  
`NetUpdateFrequency = 100.0f`이면 초당 최대 100번 업데이트 후보에 오른다.

---

## 2단계 — Relevancy 판정

`IsNetRelevantFor()` (ActorReplication.cpp:382)

ConsiderList에 올라왔더라도, **이 클라이언트에게 이 Actor가 관련 있는가**를 판단한다.

```cpp
bool AActor::IsNetRelevantFor(const AActor* RealViewer, const AActor* ViewTarget, const FVector& SrcLocation) const
{
    // 항상 관련
    if (bAlwaysRelevant || IsOwnedBy(ViewTarget) || IsOwnedBy(RealViewer) || this == ViewTarget)
        return true;

    // Owner의 Relevancy를 따름
    if (bNetUseOwnerRelevancy && Owner)
        return Owner->IsNetRelevantFor(RealViewer, ViewTarget, SrcLocation);

    // Owner에게만 관련 — 다른 클라이언트엔 안 보냄
    if (bOnlyRelevantToOwner)
        return false;

    // 숨어있고 충돌도 없으면 관련 없음
    if (IsHidden() && (!RootComponent || !RootComponent->IsCollisionEnabled()))
        return false;

    // 거리 기반 컬링
    return IsWithinNetRelevancyDistance(SrcLocation);
    // → FVector::DistSquared(SrcLocation, GetActorLocation()) < NetCullDistanceSquared
}
```

**관련성 플래그 요약**:

| 플래그 | 동작 |
|--------|------|
| `bAlwaysRelevant = true` | 모든 클라이언트에 항상 복제 |
| `bOnlyRelevantToOwner = true` | Owner 클라이언트에게만 복제 |
| `bNetUseOwnerRelevancy = true` | Owner의 IsNetRelevantFor 결과를 따름 |
| (기본값) | 거리(`NetCullDistanceSquared`) 기반 |

---

## 3단계 — 우선순위 정렬

`GetNetPriority()` (ActorReplication.cpp:45)

대역폭이 부족할 때, 어떤 Actor를 먼저 복제할지 결정한다.

```cpp
float AActor::GetNetPriority(const FVector& ViewPos, const FVector& ViewDir, ...)
{
    // 내가 보고 있는 대상이거나 그 대상이 소유한 Actor → 4배 가중치
    if (ViewTarget && (this == ViewTarget || GetInstigator() == ViewTarget))
        Time *= 4.f;

    // 뒤에 있고 멀리 있으면 → 0.2배
    // 앞에서 직접 바라보고 있으면 → 2배

    return NetPriority * Time;
}
```

`NetPriority`의 기본값은 `1.0f`.  
중요한 Actor는 생성자에서 높게 설정한다.

```cpp
// Time은 "마지막 복제 이후 경과 시간" — 오래 기다린 Actor일수록 우선순위 상승
// 이 덕분에 낮은 우선순위 Actor도 결국 언젠가는 복제된다
```

---

## 4단계 — ActorChannel::ReplicateActor()

`UActorChannel::ReplicateActor()` (DataChannel.cpp:3568)

실제로 패킷을 만드는 함수.

```cpp
int64 UActorChannel::ReplicateActor()
{
    // 최초 복제면 Actor 스폰 정보를 직렬화 (클라이언트가 이 Actor를 만들도록)
    if (RepFlags.bNetInitial && OpenedLocally)
        Connection->PackageMap->SerializeNewActor(Bunch, this, Actor);  // DataChannel.cpp:3797

    // 프로퍼티 복제 (변경된 것만)
    ActorReplicator->ReplicateProperties(Bunch, RepFlags);   // DataChannel.cpp:3857

    // 컴포넌트 복제
    for (각 ReplicatedComponent)
        ComponentReplicator->ReplicateProperties(Bunch, RepFlags);

    // 패킷 전송
    SendBunch(&Bunch, ...);
}
```

**최초 복제 vs 이후 복제**:

| 상황 | `bNetInitial` | 동작 |
|------|:---:|------|
| 클라이언트가 이 Actor를 처음 받을 때 | true | Actor 스폰 정보 + 모든 초기값 전송 |
| 이후 값이 바뀔 때 | false | 바뀐 프로퍼티만 전송 |

---

## 5단계 — 프로퍼티 Diff (Shadow Buffer)

`FObjectReplicator::ReplicateProperties_r()` (DataReplication.cpp:1922)  
`FRepLayout::CompareProperties()` (RepLayout.cpp)

변경된 프로퍼티만 보내는 핵심 메커니즘.

```
[서버 메모리]
  Actor 실제 데이터:   Health=80, Speed=300, Name="Hero"
  Shadow Buffer:       Health=100, Speed=300, Name="Hero"
                              ↑ 지난번에 보낸 값의 복사본

CompareProperties() 수행:
  Health: 80 ≠ 100  → 변경됨, 전송 목록에 추가
  Speed:  300 = 300 → 동일, 스킵
  Name:   동일      → 스킵

전송 후:
  Shadow Buffer 갱신: Health=80, Speed=300, Name="Hero"
```

```cpp
// RepLayout.cpp:1275 — UpdateChangelistMgr 내부
// GShareShadowState: 같은 프레임에 여러 커넥션에 보낼 때 CompareProperties 결과를 재사용
// → 클라이언트가 100명이어도 CompareProperties는 프레임당 1번만 수행
```

Shadow Buffer 덕분에:
- 전체 Actor 상태를 매번 보내지 않는다
- **바뀐 것만 직렬화** → 대역폭 절약
- 연결이 100개여도 Diff 계산은 한 번만 (GShareShadowState)

---

## 클라이언트 수신 흐름

```
패킷 수신
  UNetConnection::ReceivedPacket()
    → UActorChannel::ReceivedBunch()
         → 프로퍼티 역직렬화 및 적용
         → OnRep_XXX() 콜백 호출
```

최초 수신(bNetInitial)이면:
```
SerializeNewActor() 역직렬화
  → 클라이언트에서 SpawnActor() 실행
  → 초기 프로퍼티 적용
  → OnRep_XXX 호출
  → PostNetInit() → DispatchBeginPlay() → BeginPlay()
```

---

## 전체 흐름 다이어그램

```
서버                                          클라이언트
 │                                              │
 │ [매 틱] ServerReplicateActors               │
 │   ConsiderList 구성                          │
 │   IsNetRelevantFor() 판정                    │
 │   GetNetPriority() 정렬                      │
 │   ReplicateActor()                           │
 │     CompareProperties()                      │
 │     변경된 프로퍼티만 직렬화                  │
 │──────── 패킷 전송 ──────────────────────────▶│
 │                                              │ ReceivedBunch()
 │                                              │ 프로퍼티 적용
 │                                              │ OnRep_XXX() 호출
 │                                              │
```
