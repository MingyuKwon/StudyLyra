# RepLayout & Shadow Buffer — UPROPERTY 자동 복제

> 소스:  
> `Engine/Source/Runtime/Engine/Public/Net/RepLayout.h`  
> `Engine/Source/Runtime/Engine/Private/Net/RepLayout.cpp`  
> `Engine/Source/Runtime/Engine/Private/DataReplication.cpp`  
> `Engine/Source/Runtime/Engine/Private/ActorChannel.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyBaseObject.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyStruct.cpp`

`UPROPERTY(Replicated)`를 선언만 하면 자동으로 복제된다.
그 "자동"이 내부적으로 어떻게 동작하는지.

---

## FRepLayout — 복제 프로퍼티 레이아웃

클래스마다 `FRepLayout` 하나가 생성된다.
이 클래스가 "어떤 프로퍼티를, 어떤 순서로, 어떤 방식으로 직렬화할지"를 담는다.

```
FRepLayout
  ├─ Parents[]    — 최상위 UPROPERTY 목록 (예: Health, Position)
  ├─ Cmds[]       — 실제 직렬화 명령 목록 (중첩 구조체는 재귀 전개됨)
  └─ BaseOffset   — 각 프로퍼티의 메모리 오프셋
```

`GetPropertyCmd` 타입:

| 타입 | 직렬화 방식 |
|------|------------|
| `REPCMD_Property` | 기본 타입 (int, float, bool 등) — `operator<<` |
| `REPCMD_PropertyObject` | 오브젝트 포인터 — PackageMap을 통한 GUID 변환 |
| `REPCMD_PropertyString` | FString — 가변 길이 |
| `REPCMD_PropertyNetSerialize` | `WithNetSerializer = true` 구조체 — 커스텀 NetSerialize 호출 |
| `REPCMD_Return` | 구조체 끝 마커 |

엔진 시작 시 클래스별 `FRepLayout`이 한 번 빌드되고, 이후 모든 복제에서 재사용된다.

---

## GetLifetimeReplicatedProps — 무엇을 복제할지 선언

```cpp
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);

    DOREPLIFETIME(AMyActor, Health);
    DOREPLIFETIME_CONDITION(AMyActor, Ammo, COND_OwnerOnly);
}
```

`DOREPLIFETIME` 매크로가 `OutLifetimeProps`에 `FLifetimeProperty`를 추가한다.
`FRepLayout`은 이 목록을 읽어 어떤 프로퍼티를 어느 조건에서 복제할지 기록한다.

복제 조건 (`ELifetimeCondition`):

| 조건 | 대상 |
|------|------|
| `COND_None` | 모든 클라이언트 |
| `COND_OwnerOnly` | 이 Actor를 소유한 클라이언트만 |
| `COND_SkipOwner` | 소유자 제외 |
| `COND_SimulatedOnly` | Simulated Proxy만 |
| `COND_AutonomousOnly` | Autonomous Proxy만 |
| `COND_InitialOnly` | Actor가 처음 Relevancy에 들어올 때만 (이후 변경 전송 안 함) |

---

## Shadow Buffer — 변경 감지의 핵심

`FObjectReplicator`는 Actor의 복제 프로퍼티 값을 **복사본**으로 따로 보관한다.
이 복사본이 Shadow Buffer다.

```
실제 Actor 메모리:  Health = 80, Position = (100, 200, 0)
Shadow Buffer:      Health = 90, Position = (100, 200, 0)
                    ^^^^^ 다름                             ← Health가 변경됨
```

매 틱 `CompareProperties()`가 실제 메모리와 Shadow Buffer를 비교한다.

```cpp
// RepLayout.cpp (간략화)
bool FRepLayout::CompareProperties(
    FRepState* RepState,
    const uint8* Data,       // 실제 Actor 메모리
    const uint8* Shadow,     // 이전 틱의 복사본
    FRepChangedPropertyTracker& Tracker)
{
    for (const FRepLayoutCmd& Cmd : Cmds)
    {
        if (memcmp(Data + Cmd.Offset, Shadow + Cmd.Offset, Cmd.ElementSize) != 0)
        {
            Tracker.MarkChanged(Cmd.RelativeHandle);  // 변경된 것만 표시
        }
    }
}
```

변경된 프로퍼티 핸들만 기록해두고, 그것만 `FBitWriter`에 써서 전송한다.

전송 후 Shadow Buffer를 현재값으로 갱신한다.
다음 틱에는 이 갱신된 Shadow와 비교하므로, 또 바뀐 것만 잡힌다.

---

## 복제 전체 흐름

```
[서버 틱]
  ActorChannel::ReplicateActor()
    │
    ├─ FRepLayout::CompareProperties()
    │    현재값 vs Shadow Buffer 비교 → 변경된 프로퍼티 핸들 목록
    │
    ├─ FRepLayout::SendProperties()
    │    변경된 핸들들을 FOutBunch에 직렬화
    │    ├─ 핸들 번호 기록 (몇 번 프로퍼티인지)
    │    ├─ 값 직렬화 (NetSerialize 또는 자동)
    │    └─ 다음 변경 핸들 기록 ... 반복
    │
    ├─ Shadow Buffer 갱신
    │    전송한 현재값을 Shadow에 복사
    │
    └─ FOutBunch → UNetConnection → UDP 전송

[클라이언트]
  UActorChannel::ReceivedBunch()
    │
    ├─ FRepLayout::ReceiveProperties()
    │    FInBunch에서 핸들 번호 읽기
    │    → 해당 프로퍼티 역직렬화 및 값 적용
    │
    ├─ Shadow Buffer 갱신 (클라이언트 측도 동일하게 유지)
    │
    └─ OnRep_XXX 콜백 호출
         GetLifetimeReplicatedProps에서 
         UPROPERTY(ReplicatedUsing = OnRep_Health) 로 지정된 함수
```

---

## OnRep 콜백 — 클라이언트에서만 호출

```cpp
UPROPERTY(ReplicatedUsing = OnRep_Health)
float Health;

UFUNCTION()
void OnRep_Health();   // 서버에서는 호출되지 않음
```

서버는 직접 `Health`를 변경하므로 콜백이 필요 없다.
클라이언트는 복제 값 수신 후 `OnRep_Health`를 호출해 UI 갱신, 이펙트 재생 등 후처리를 한다.

콜백의 파라미터로 이전 값을 받을 수 있다:

```cpp
void OnRep_Health(float OldHealth);  // 복제 직전 값이 들어옴
```

이전 값은 복제 직전 Shadow Buffer에서 꺼낸다.

---

## Actor 직렬화 실제 호출 체인

Actor는 사용자가 구현하는 단일 직렬화 함수가 없다.
RepLayout이 프로퍼티 단위로 쪼개 `FProperty::NetSerializeItem` 가상함수를 호출한다.

```
UActorChannel::ReplicateActor()
  ↓
FObjectReplicator::ReplicateProperties()          // DataReplication.cpp:1908
  ↓
FRepLayout::ReplicateProperties()                 // 변경 목록 계산 포함
  ↓
FRepLayout::SendProperties()
  ↓
FRepLayout::SendProperties_r()                    // RepLayout.cpp:2767
  ↓ 변경된 Cmd 하나씩 순회
Cmd.Property->NetSerializeItem(Writer, PackageMap, Data)   // RepLayout.cpp:2924
  │
  ├─ FBoolProperty::NetSerializeItem()        → 1비트
  ├─ FNumericProperty::NetSerializeItem()     → sizeof(T) 바이트
  ├─ FObjectPropertyBase::NetSerializeItem()  → Map->SerializeObject() → GUID 4바이트
  └─ FStructProperty::NetSerializeItem()
       ├─ STRUCT_NetSerializeNative 있음 → CppStructOps->NetSerialize() 호출
       └─ 없음 → RepLayout이 빌드 시점에 리프 필드로 전개했으므로 이 경로엔 오지 않음
```

`FProperty::NetSerializeItem`은 엔진 내부의 FProperty 서브클래스들이 각자 구현하는 가상함수다.
사용자가 Actor에 구현하는 `NetSerialize`(USTRUCT 용)와 이름이 비슷하지만 완전히 다른 것이다.

---

## Actor에서 사용자가 직렬화를 제어할 수 있는 곳

**1. GetLifetimeReplicatedProps — 어떤 필드를 복제할지**

```cpp
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    DOREPLIFETIME(AMyActor, Health);                        // 모든 클라이언트
    DOREPLIFETIME_CONDITION(AMyActor, Ammo, COND_OwnerOnly); // 소유자만
    // 여기 없는 UPROPERTY(Replicated) 필드는 복제 목록에서 제외됨
}
```

**2. USTRUCT 타입 프로퍼티의 NetSerialize — 어떻게 직렬화할지**

```cpp
UPROPERTY(Replicated)
FHitData HitData;   // FHitData에 NetSerialize를 구현하면 해당 필드의 직렬화 방식을 제어 가능
```

Actor 전체를 하나의 덩어리로 직렬화하는 진입점은 없다.
"어떤 필드를" → `GetLifetimeReplicatedProps`,
"그 필드를 어떻게" → 필드 타입이 USTRUCT면 `NetSerialize`, 기본 타입이면 엔진이 자동 처리.

---

## 핸들 번호 — 어떤 프로퍼티인지 식별

`FRepLayout`은 각 프로퍼티에 **핸들 번호**를 부여한다.
네트워크로는 프로퍼티 이름이 아닌 핸들 번호를 전송한다.

```
핸들 1: Health (2바이트)
핸들 2: Stamina (2바이트)
핸들 3: Position.X (4바이트)
핸들 4: Position.Y (4바이트)
핸들 5: Position.Z (4바이트)
```

`Health`만 바뀌었다면: `[핸들=1][값=80][종료]` — 총 몇 비트만 전송.
이름 문자열을 보내지 않으므로 패킷이 작다.

서버와 클라이언트가 핸들 번호에 동의하려면 **같은 코드**를 써야 한다.
클라이언트가 다른 버전이면 핸들 번호가 어긋나 값이 잘못 적용된다.
핫픽스로 서버만 업데이트하면 안 되는 이유 중 하나다.
