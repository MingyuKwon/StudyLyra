# GenericReplicatedEvent

> 소스: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/GameplayAbilityTargetTypes.h:662`  
> `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:3880`

---

## 개념

`EAbilityGenericReplicatedEvent`는 **활성화된 GA 인스턴스에 묶인 신호 슬롯**이다.
이름의 "Replicated"는 클라↔서버 RPC로 동기화되기 때문에 붙었다.

```cpp
// GameplayAbilityTargetTypes.h:662
// "Generic, nonpayload carrying events that are replicated between the client and server"
namespace EAbilityGenericReplicatedEvent
{
    enum Type : int
    {
        GenericConfirm,           // WaitConfirm AbilityTask용
        GenericCancel,            // WaitCancel AbilityTask용
        InputPressed,             // WaitInputPress AbilityTask용
        InputReleased,            // WaitInputRelease AbilityTask용
        GenericSignalFromClient,  // 범용 클라 → 서버 신호
        GenericSignalFromServer,  // 범용 서버 → 클라 신호
        GameCustom1,              // 게임 전용 확장 슬롯
        GameCustom2,
        GameCustom3,
        GameCustom4,
        GameCustom5,
        GameCustom6,
        MAX
    };
}
```

---

## 저장소 — AbilityTargetDataMap

이벤트 상태는 ASC의 `AbilityTargetDataMap`에 저장된다.

```
AbilityTargetDataMap
  key:   FGameplayAbilitySpecHandle + FPredictionKey   ← GA 인스턴스 단위
  value: FAbilityReplicatedDataCache
           └─ GenericEvents[MAX]                        ← 이벤트 타입별 슬롯
                  └─ bTriggered:     bool
                     VectorPayload:  FVector_NetQuantize100
                     Delegate:       FSimpleMulticastDelegate
```

키가 `(Handle + PredictionKey)` 조합이라 **같은 GA 클래스의 서로 다른 인스턴스** 이벤트가 섞이지 않는다.

---

## InvokeReplicatedEvent — 로컬 발동

```cpp
// AbilitySystemComponent_Abilities.cpp:3880
bool UAbilitySystemComponent::InvokeReplicatedEvent(
    EAbilityGenericReplicatedEvent::Type EventType,
    FGameplayAbilitySpecHandle AbilityHandle,
    FPredictionKey AbilityOriginalPredictionKey,
    FPredictionKey CurrentPredictionKey)
{
    TSharedRef<FAbilityReplicatedDataCache> ReplicatedData =
        AbilityTargetDataMap.FindOrAdd(Handle + PredKey);

    ReplicatedData->GenericEvents[(uint8)EventType].bTriggered = true;

    if (ReplicatedData->GenericEvents[EventType].Delegate.IsBound())
    {
        ReplicatedData->GenericEvents[EventType].Delegate.Broadcast();
        return true;
    }
    return false;
}
```

발동 결과가 두 갈래로 나뉜다:

- **구독자가 있으면** → 즉시 `Delegate.Broadcast()`
- **아무도 구독 안 했으면** → `bTriggered = true`만 저장

두 번째 경로가 필요한 이유는 **타이밍 레이스** 때문이다.  
예를 들어 서버에서 InputPressed 이벤트가 먼저 발동됐는데, 클라이언트의 `WaitInputPress`가 아직 `Activate()`를 호출하지 않은 경우가 있다.  
이럴 때 `Activate()` 안에서 `CallReplicatedEventDelegateIfSet()`을 호출하면 이미 `bTriggered = true`인 이벤트를 사후에 처리할 수 있다.

---

## RPC 동기화

로컬 발동만으로는 반대편(서버↔클라)에 이벤트가 전달되지 않는다.
반대편에 알리려면 RPC를 직접 호출해야 한다.

```
클라 → 서버:  ServerSetReplicatedEvent()
                → 서버에서 InvokeReplicatedEvent() 호출

서버 → 클라:  ClientSetReplicatedEvent()
                → 클라에서 InvokeReplicatedEvent() 호출
```

LocalPredicted GA라면 클라가 먼저 `InvokeReplicatedEvent()`를 로컬에서 호출하고,
이어서 `ServerSetReplicatedEvent()` RPC로 서버에도 같은 이벤트를 발동시킨다.

---

## 구독 방법 — AbilityReplicatedEventDelegate

AbilityTask나 GA 안에서 이 이벤트를 기다리려면 `AbilityReplicatedEventDelegate()`가 반환하는 델리게이트에 바인딩한다.

```cpp
// 구독
DelegateHandle = ASC->AbilityReplicatedEventDelegate(
    EAbilityGenericReplicatedEvent::InputPressed,
    GetAbilitySpecHandle(),        // 이 GA 인스턴스에만 반응
    GetActivationPredictionKey()
).AddUObject(this, &ThisClass::OnCallback);

// 이미 발동된 이벤트 사후 처리 (타이밍 레이스 방어)
ASC->CallReplicatedEventDelegateIfSet(InputPressed, Handle, PredKey);

// 구독 해제
ASC->AbilityReplicatedEventDelegate(InputPressed, Handle, PredKey).Remove(DelegateHandle);
```

---

## WaitInputPress 전체 체인

`WaitInputPress`가 이 시스템을 어떻게 사용하는지 전체 흐름을 보면 구조가 명확해진다.

```
[Activate()]
  ASC->AbilityReplicatedEventDelegate(InputPressed, handle, predKey)
    .AddUObject(this, &OnPressCallback)        ← 구독 등록

[입력 발생 — ProcessAbilityInput]
  AbilitySpec->IsActive() == true
    → AbilitySpecInputPressed()
        → InvokeReplicatedEvent(InputPressed, handle, predKey)
            → Delegate.Broadcast()
                → OnPressCallback()

[OnPressCallback()]
  델리게이트 Remove(DelegateHandle)             ← 구독 해제
  if (IsPredictingClient())
      ServerSetReplicatedEvent(InputPressed)   ← 서버에 알림
  else
      ConsumeGenericReplicatedEvent()          ← 서버 측: 이벤트 소비
  OnPress.Broadcast(ElapsedTime)               ← GA로 결과 전달
  EndTask()
```

---

## 어디에 쓰이나

| AbilityTask | 사용 이벤트 |
|---|---|
| `WaitInputPress` | `InputPressed` |
| `WaitInputRelease` | `InputReleased` |
| `WaitConfirm` | `GenericConfirm` |
| `WaitCancel` | `GenericCancel` |
| `WaitNetSync` (BothWait) | `GenericSignalFromClient` + `GenericSignalFromServer` |
| 커스텀 태스크 | `GameCustom1` ~ `GameCustom6` |

`WaitConfirm` / `WaitCancel`은 `GenericConfirm` / `GenericCancel` 슬롯을 사용한다.
`ProcessAbilityInput`이 아니라 ASC의 `LocalInputConfirm()` / `LocalInputCancel()`이 각각 `InvokeReplicatedEvent`를 발동시킨다.
