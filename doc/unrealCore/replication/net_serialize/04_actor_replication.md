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

`FProperty::NetSerializeItem`은 엔진 내부 FProperty 서브클래스들이 각자 구현하는 가상함수다.
USTRUCT에 사용자가 구현하는 `NetSerialize`와 이름이 비슷하지만 완전히 다른 레이어다.

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

`DOREPLIFETIME` 매크로가 `OutLifetimeProps`에 `FLifetimeProperty`를 추가한다.
FRepLayout은 이 목록만 Cmds[]로 빌드한다. 여기 없는 필드는 복제 대상 자체가 아니다.

복제 조건 (`ELifetimeCondition`):

| 조건 | 전송 대상 |
|------|----------|
| `COND_None` | 모든 클라이언트 |
| `COND_OwnerOnly` | 이 Actor를 소유한 클라이언트만 |
| `COND_SkipOwner` | 소유자 제외 모든 클라이언트 |
| `COND_SimulatedOnly` | Simulated Proxy만 |
| `COND_AutonomousOnly` | Autonomous Proxy만 |
| `COND_InitialOnly` | Relevancy 진입 시 최초 1회만 |

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
