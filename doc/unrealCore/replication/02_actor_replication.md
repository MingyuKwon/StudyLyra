# Actor 복제 상세

> 출처:  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Private/ActorReplication.cpp`  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/Actor.h`

---

## Actor를 복제하려면

최소 두 가지가 필요하다.

```cpp
// 1. 클래스에서 복제 활성화
AMyActor::AMyActor()
{
    bReplicates = true;
}

// 2. 복제할 프로퍼티 선언
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AMyActor, Health);
}
```

---

## bReplicates 내부 동작

```cpp
// Actor.cpp:4518
void AActor::SetReplicates(bool bInReplicates)
{
    bReplicates = bInReplicates;

    if (bReplicates)
        RemoteRole = ROLE_SimulatedProxy;  // 복제 대상임을 선언
    else
        RemoteRole = ROLE_None;            // 복제 안 함

    // 이미 BeginPlay 이후라면 즉시 복제 시스템에 등록/해제
    if (bInReplicates)
        UE::Net::FReplicationSystemUtil::StartReplicatingActor(this);
    else
        UE::Net::FReplicationSystemUtil::StopReplicatingActor(this, ...);
}
```

`bReplicates = false`이면 `RemoteRole = ROLE_None` → ConsiderList 구성 시 즉시 스킵된다.

---

## 복제 시스템 등록 시점

```cpp
// Actor.cpp:3241 — DispatchBeginPlay → BeginPlay 직전
void DispatchBeginPlay()
{
    StartReplicatingActor();  // ← 복제 시스템에 이 Actor를 등록
    BeginPlay();
    ...
}
```

```cpp
// Actor.cpp:3215 — EndPlay
void RouteEndPlay(...)
{
    StopReplicatingActor(...);  // ← 복제 시스템에서 제거
    ...
}
```

즉, Actor는 **BeginPlay 직전에 복제 등록**, **EndPlay 시점에 복제 해제**된다.

---

## GetLifetimeReplicatedProps — 복제 레이아웃 선언

```cpp
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);

    DOREPLIFETIME(AMyActor, Health);                            // 모든 클라이언트
    DOREPLIFETIME_CONDITION(AMyActor, Speed, COND_OwnerOnly);   // Owner만
    DOREPLIFETIME_CONDITION(AMyActor, TeamId, COND_InitialOnly);// 최초 1회
}
```

이 함수는 **매 틱 호출이 아니다**. 복제 시스템 초기화 시 한 번 호출되어 `FRepLayout`을 구성한다.  
`FRepLayout`은 이 클래스의 복제 프로퍼티 목록을 바이트 오프셋 기반으로 저장해 두는 자료구조다.

**COND_ 조건 종류**:

| 조건 | 복제 대상 |
|------|----------|
| `COND_None` | 모든 클라이언트 |
| `COND_OwnerOnly` | Owner 클라이언트만 |
| `COND_SkipOwner` | Owner 제외 전체 |
| `COND_SimulatedOnly` | SimulatedProxy만 |
| `COND_AutonomousOnly` | AutonomousProxy만 |
| `COND_InitialOnly` | 최초 연결 시 1회만 |
| `COND_Custom` | PreReplication에서 수동 제어 |

---

## Network Role — 서버와 클라이언트가 보는 관점

같은 Actor라도 서버와 클라이언트에서 Role이 다르다.

```
서버에서 본 내 Pawn:
  LocalRole  = ROLE_Authority      ← 내가 실제 권한을 가짐
  RemoteRole = ROLE_AutonomousProxy ← 클라이언트 측 역할

클라이언트에서 본 내 Pawn (로컬 플레이어):
  LocalRole  = ROLE_AutonomousProxy ← 내가 조종
  RemoteRole = ROLE_Authority       ← 서버가 권한

클라이언트에서 본 다른 플레이어 Pawn:
  LocalRole  = ROLE_SimulatedProxy  ← 서버 데이터로 시뮬레이션
  RemoteRole = ROLE_Authority
```

Role에 따른 판단:

```cpp
if (HasAuthority())  // LocalRole == Authority
{
    // 서버 로직
}

if (IsLocallyControlled())  // AutonomousProxy
{
    // 로컬 플레이어 로직
}
```

---

## NetUpdateFrequency — 복제 주기 제어

```cpp
// Actor.cpp:292
NetPriority = 1.0f;
SetNetUpdateFrequency(100.0f);   // 초당 최대 100회 업데이트 후보
SetMinNetUpdateFrequency(2.0f);  // 적응형 주기 사용 시 최소 2회
```

`NetUpdateFrequency`는 ConsiderList 진입 주기를 제한한다.  
값이 높다고 매 틱 복제되는 게 아니라 "후보에 오를 수 있는 최대 빈도"다.  
대역폭 상황이나 우선순위에 따라 실제 전송은 건너뛸 수 있다.

---

## PreReplication — 복제 직전 훅

```cpp
// Actor.cpp
void AActor::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
```

매 복제 주기마다, 패킷 구성 직전에 호출된다.  
`COND_Custom` 프로퍼티의 복제 여부를 여기서 동적으로 결정한다.

```cpp
void AMyActor::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
{
    Super::PreReplication(ChangedPropertyTracker);

    // bIsInCombat 값에 따라 CombatState 복제 여부 토글
    DOREPLIFETIME_ACTIVE_OVERRIDE(AMyActor, CombatState, bIsInCombat);
}
```

호출 조건:

```cpp
// Actor.cpp:3297
bool AActor::ShouldCallPreReplication() const
{
    return bCallPreReplication
        || bReplicateMovement
        || (RootComponent && !RootComponent->GetIsReplicated());
}
```

`bReplicateMovement = true`이면 이동 처리를 위해 항상 호출된다.

---

## OnRep_ — 클라이언트 수신 콜백

```cpp
UPROPERTY(ReplicatedUsing = OnRep_Health)
float Health;

UFUNCTION()
void OnRep_Health();                  // 이전 값 불필요
void OnRep_Health(float OldHealth);   // 이전 값 필요할 때
```

**서버에서는 호출되지 않는다** — 클라이언트 전용.  
서버에서 `Health`를 바꾸면:
1. 복제 시스템이 변경을 감지 (Shadow Buffer 비교)
2. 클라이언트로 전송
3. 클라이언트에서 `OnRep_Health()` 호출

**초기 복제 시도 호출**:  
클라이언트가 이 Actor를 처음 받을 때도 현재값이 기본값(0.0f 등)과 다르면 호출된다.  
`BeginPlay`보다 먼저 호출될 수 있다.

---

## Actor 복제의 전체 흐름 (서버→클라이언트)

```
[서버] Actor 스폰, bReplicates=true
  ↓
DispatchBeginPlay()
  StartReplicatingActor()     ← 복제 시스템 등록
  BeginPlay()

[매 틱 서버]
  ConsiderList에 포함
  IsNetRelevantFor() → 이 클라이언트에 관련 있음
  ActorChannel 생성 (최초)
  ReplicateActor()
    bNetInitial=true: SerializeNewActor()  ← 클라이언트에서 이 Actor 스폰하도록
    모든 초기값 직렬화

[클라이언트 최초 수신]
  SpawnActor() (복제 수신 전용)
  초기 프로퍼티 적용
  OnRep_XXX() 호출
  PostNetInit() → BeginPlay()

[이후 서버에서 값 변경]
  Health: 100 → 80

[다음 복제 주기]
  CompareProperties()
    Shadow Buffer: Health=100
    현재값:        Health=80
    → 변경 감지
  Health=80 직렬화 → 전송

[클라이언트 수신]
  Health = 80 적용
  OnRep_Health() 호출

[서버] Actor EndPlay
  StopReplicatingActor()      ← 복제 시스템 해제
  클라이언트에 Destroy 패킷 전송
```

---

## 주의사항

**1. OnRep에서 다른 복제 프로퍼티를 읽으면 순서가 보장되지 않는다**

같은 패킷으로 온 A, B 프로퍼티가 있을 때 `OnRep_A`에서 B를 읽으면 B가 아직 적용 전일 수 있다.  
여러 복제값을 조합해야 할 때는 `PostRepNotifies()` 또는 별도 타이머를 쓴다.

**2. OnRep는 서버에서 직접 호출하면 안 된다**

서버에서 값을 변경하면 복제가 자동으로 일어난다.  
`OnRep_()`를 서버에서 수동 호출하면 서버-클라이언트 로직이 이중 실행된다.

**3. GetLifetimeReplicatedProps에서 Super 누락**

부모 클래스의 복제 프로퍼티가 통째로 빠진다. `Super::` 누락은 가장 흔한 복제 버그 중 하나.

**4. bReplicates는 생성자에서 설정해야 한다**

`BeginPlay` 이후 `SetReplicates(true)`를 호출하면 동작하지만,  
가능하면 생성자에서 설정하는 것이 안전하다.

**5. 클라이언트에서 복제 Actor의 BeginPlay는 초기값 적용 이후다**

클라이언트에서 복제로 받은 Actor의 `BeginPlay`는 초기 복제 프로퍼티가 모두 적용된 뒤 호출된다.  
(`04_replication.md` 참고: `bDeferBeginPlayAndUpdateOverlaps`)  
따라서 `BeginPlay`에서 복제된 초기값을 안전하게 읽을 수 있다.
