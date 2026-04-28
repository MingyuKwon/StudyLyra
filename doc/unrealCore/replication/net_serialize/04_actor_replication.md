# Actor 복제 — 호출 체인과 사용자 제어

> 소스:  
> `Engine/Source/Runtime/Engine/Private/DataReplication.cpp`  
> `Engine/Source/Runtime/Engine/Private/RepLayout.cpp`  
> `Engine/Source/Runtime/Engine/Private/ActorChannel.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyBaseObject.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyStruct.cpp`

Actor는 사용자가 구현하는 단일 직렬화 함수가 없다.
`GetLifetimeReplicatedProps`로 복제할 필드를 선언하면,
RepLayout이 프로퍼티 단위로 쪼개 `FProperty::NetSerializeItem` 가상함수를 호출한다.

---

## 실제 호출 체인

```
UActorChannel::ReplicateActor()
  ↓
FObjectReplicator::ReplicateProperties()        // DataReplication.cpp:1908
  ↓
FRepLayout::ReplicateProperties()               // Shadow Buffer 비교 → 변경 목록 계산
  ↓
FRepLayout::SendProperties()
  ↓
FRepLayout::SendProperties_r()                  // RepLayout.cpp:2767
  ↓ 변경된 Cmd 하나씩 순회
Cmd.Property->NetSerializeItem(Writer, PackageMap, Data)  // RepLayout.cpp:2924
  │
  ├─ FBoolProperty::NetSerializeItem()          → 1비트
  ├─ FNumericProperty::NetSerializeItem()       → sizeof(T) 바이트
  ├─ FObjectPropertyBase::NetSerializeItem()    → Map->SerializeObject() → GUID 4바이트
  └─ FStructProperty::NetSerializeItem()
       ├─ STRUCT_NetSerializeNative 있음 → CppStructOps->NetSerialize() 호출  (사용자 코드)
       └─ 없음 → RepLayout 빌드 시점에 리프 필드로 전개 완료 → 이 경로엔 도달 안 함
```

---

## 직렬화 단위 — 기본 동작과 NetSerialize opt-in

**기본 동작은 USTRUCT든 Actor든 동일하다**: RepLayout이 모든 타입을 리프 필드(float, bool, int)까지 전개해 하나씩 직렬화한다.

USTRUCT에 `NetSerialize`를 구현하는 것은 "이 타입 전체를 내가 하나의 단위로 직렬화하겠다"는 opt-in이다.

| | 직렬화 단위 | 제어권 |
|---|---|---|
| Actor / USTRUCT (기본) | 리프 필드 하나씩 | 엔진 자동 처리 |
| USTRUCT (`NetSerialize` 구현) | 타입 전체를 하나의 덩어리로 | 사용자가 비트 직접 제어 |

`FHitResult` 예시:

```
NetSerialize 없음 → RepLayout이 Location.X, Location.Y, Normal.X ... 각각을 float 단위로 직렬화
NetSerialize 있음 → "이 구조체 전체를 내가 압축해서 쓸게" → CppStructOps->NetSerialize() 호출
```

`FStructProperty::NetSerializeItem`이 디스패처이고, 사용자 `NetSerialize`는 그 안에서 호출되는 콜백이다. 이름이 비슷하지만 완전히 다른 레이어다.

Actor에 `NetSerialize`가 없는 이유는 직렬화 외에도 스폰/GUID 매핑/Role/RPC 같은 부가 처리가 붙어야 해서 "함수 하나"로 커버가 불가능하기 때문이다.

---

## GetLifetimeReplicatedProps — 복제할 필드 선언

```cpp
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);

    DOREPLIFETIME(AMyActor, Health);
    DOREPLIFETIME_CONDITION(AMyActor, Ammo, COND_OwnerOnly);
}
```

- **호출 시점**: `FRepLayout::InitFromObjectClass()`에서 **클래스당 1회**. 빌드된 `Cmds[]`는 모든 인스턴스가 공유한다.
- **`DOREPLIFETIME`**: 리플렉션으로 `FProperty*`를 찾아 `FLifetimeProperty{RepIndex, Condition, RepNotifyCondition}`를 `OutLifetimeProps`에 추가한다. `UPROPERTY(Replicated)` 없는 변수를 등록하면 Fatal.
- **`RepIndex`**: UHT가 컴파일 시점에 Replicated 프로퍼티마다 자동 부여하는 고유 번호. 패킷에 필드명 대신 이 번호만 들어간다.
- **`DOREPLIFETIME_CONDITION`**: `Condition` 하나만 더 설정하는 것 외에 동일. RepLayout이 틱마다 해당 Connection이 조건을 만족하는지 확인 후 포함 여부를 결정한다.
- **여기 없는 필드는 Shadow Buffer 비교 대상 자체에서 제외**되므로 절대 복제되지 않는다.

복제 조건 (`ELifetimeCondition`):

| 조건 | 전송 대상 |
|------|----------|
| `COND_None` | 모든 클라이언트 |
| `COND_OwnerOnly` | 이 Actor를 소유한 클라이언트만 |
| `COND_SkipOwner` | 소유자 제외 모든 클라이언트 |
| `COND_SimulatedOnly` | Simulated Proxy만 |
| `COND_AutonomousOnly` | Autonomous Proxy만 |
| `COND_InitialOnly` | Relevancy 진입 시 최초 1회만 |

`DOREPLIFETIME_WITH_PARAMS`로 조건 + RepNotify 조건 + Push Model 여부를 한 번에 지정할 수 있다.

---

## 복제 전체 흐름

```
[서버 틱]
  UActorChannel::ReplicateActor()
    │
    ├─ FRepLayout::CompareProperties()
    │    현재값 vs Shadow Buffer → 변경된 핸들 목록
    │
    ├─ FRepLayout::SendProperties_r()
    │    변경된 핸들마다:
    │      [핸들 번호] + [Cmd.Property->NetSerializeItem()] 기록
    │
    ├─ Shadow Buffer 현재값으로 갱신
    │
    └─ FOutBunch → UNetConnection → UDP 전송

[클라이언트]
  UActorChannel::ReceivedBunch()
    │
    ├─ FRepLayout::ReceiveProperties()
    │    핸들 번호 읽기 → 해당 프로퍼티 역직렬화 → 값 적용
    │
    ├─ Shadow Buffer 갱신
    │
    └─ OnRep_XXX 콜백 호출
```

---

## OnRep 콜백 — 클라이언트에서만 호출

```cpp
UPROPERTY(ReplicatedUsing = OnRep_Health)
float Health;

UFUNCTION()
void OnRep_Health(float OldHealth);  // 복제 직전 값(Shadow Buffer)이 파라미터로 들어옴
```

서버는 `Health`를 직접 변경하므로 콜백이 없다.
클라이언트는 값 수신 후 `OnRep_Health`를 호출해 UI 갱신, 이펙트 재생 등 후처리를 한다.

---

## 사용자가 직렬화를 제어할 수 있는 두 가지 지점

Actor 전체를 하나의 덩어리로 직렬화하는 진입점은 없다.
제어는 두 곳에서만 가능하다.

```
"어떤 필드를 복제할지"  →  GetLifetimeReplicatedProps
"그 필드를 어떻게"      →  필드 타입이 USTRUCT면 NetSerialize, 아니면 엔진이 자동 처리
```

```cpp
// 1. 복제 대상 선택
void AMyActor::GetLifetimeReplicatedProps(...) const
{
    DOREPLIFETIME(AMyActor, HitData);   // HitData만 복제
    // OtherField는 목록에 없으므로 전송 안 됨
}

// 2. USTRUCT 필드의 직렬화 방식 제어
UPROPERTY(Replicated)
FHitData HitData;
// ↑ FHitData에 NetSerialize + TStructOpsTypeTraits 구현하면 직렬화 방식 직접 제어 가능
```

---

## 왜 Actor에는 NetSerialize가 없는가

`FStruct`는 데이터만 전달하면 되는 **값 타입**이라 "비트를 어떻게 쓸지" 함수 하나로 충분하다.
`UObject`/`Actor`는 복제 시 직렬화 외에도 엔진이 자동으로 처리해야 할 것들이 있다.

```
Actor 복제가 처리하는 것들:
  ├─ 스폰/제거        — 클라이언트에 Actor가 없으면 먼저 생성
  ├─ 정체성(GUID)     — "이 Actor가 클라이언트의 어떤 오브젝트인가" 매핑
  ├─ Role/RemoteRole  — Authority / AutonomousProxy / SimulatedProxy
  ├─ 소유권(Owner)    — 어떤 Connection이 이 Actor를 제어하는가
  ├─ Relevancy        — 이 클라이언트에 보낼 필요가 있는가
  └─ RPC 처리         — 함수 호출 라우팅
```

이것들은 "직렬화 함수 하나"로 커버할 수 없다. 스폰도 안 된 Actor에 NetSerialize를 호출할 수 없다.

또한 깊은 상속 계층에서는 선언형(`GetLifetimeReplicatedProps`)이 더 유리하다.

```cpp
// 각 클래스가 자기 프로퍼티만 독립적으로 선언
ACharacter::GetLifetimeReplicatedProps        // 이동 관련 필드
ALyraCharacter::GetLifetimeReplicatedProps    // PawnData, bIsCrouching

// NetSerialize였다면?
bool ALyraCharacter::NetSerialize(...)
{
    Super::NetSerialize(...);  // 부모 계층의 수백 줄 호출
    // 파생 클래스가 필드 추가할 때마다 부모 직렬화 코드를 건드려야 함
}
```

프로퍼티별 조건(`COND_OwnerOnly`, `COND_SimulatedOnly`)도 선언형으로만 표현 가능하다.
NetSerialize 하나로 합치면 프로퍼티별 세분화가 불가능해진다.

---

## Actor vs UObject 서브오브젝트 — 채널 인프라 차이

**프로퍼티 직렬화 메커니즘(RepLayout + UPROPERTY)은 동일**하다.
차이는 그것을 감싸는 네트워크 인프라다.

| | Actor | UObject 서브오브젝트 |
|---|---|---|
| **채널** | 자기만의 `UActorChannel` | 소유 Actor 채널에 편승 |
| **스폰/제거** | 엔진이 클라이언트에서 자동 생성/제거 | 없음 — Owner Actor가 살아야 존재 |
| **Role 시스템** | Authority / AutonomousProxy / SimulatedProxy | 없음 |
| **RPC** | 지원 | 제한적 |
| **Relevancy** | `IsNetRelevantFor()` | 없음 — Owner가 Relevant하면 따라감 |
| **프로퍼티 복제** | RepLayout (동일) | RepLayout (동일) |

`ULyraHealthSet`(AttributeSet)이 대표적인 예다.
`UPROPERTY(Replicated)` + `GetLifetimeReplicatedProps`를 쓰지만,
자기 채널이 없고 `ALyraPlayerState`의 채널 안에서 서브오브젝트로 복제된다.

```
ALyraPlayerState    ← 자기 UActorChannel 보유, 독립적으로 복제
  └─ ULyraHealthSet ← PlayerState 채널 안에 포함, 자기 채널 없음
```

UObject를 서브오브젝트로 등록하는 방법 (UE5):
```cpp
// Actor::BeginPlay 또는 생성 시점
AddReplicatedSubObject(HealthSet);

// UObject 자체는 동일하게 선언
void ULyraHealthSet::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    DOREPLIFETIME_CONDITION(ULyraHealthSet, Health, COND_None);
}
```
