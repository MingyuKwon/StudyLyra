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

이벤트 상태는 ASC의 `AbilityTargetDataMap` (`FGameplayAbilityReplicatedDataContainer`) 에 저장된다.

### 실제 타입은 TMap이 아니다

이름에 "Map"이 붙어 있지만 내부 구현은 **`TArray` 두 개**로 된 커스텀 컨테이너다.

```cpp
// GameplayAbilityTypes.h:604
struct FGameplayAbilityReplicatedDataContainer
{
    typedef TPair<
        FGameplayAbilitySpecHandleAndPredictionKey,
        TSharedRef<FAbilityReplicatedDataCache>
    > FKeyDataPair;

    TArray<FKeyDataPair>                            InUseData;  // 현재 사용 중인 엔트리
    TArray<TSharedRef<FAbilityReplicatedDataCache>> FreeData;   // 반납된 재활용 풀
};
```

`TMap` 대신 `TArray`를 쓰는 이유가 헤더 주석에 명시돼 있다:

> "Return shared ptrs so that callsites are not vulnerable to the underlying map shifting around.  
> E.g invoking a replicated event **ends the ability** or activates a new one and causes memory to move, invalidating the pointer."

`InvokeReplicatedEvent`가 `Delegate.Broadcast()`를 호출하면 그 콜백 안에서 GA가 종료될 수 있다. GA 종료가 `Remove()`를 부르고, `TMap`이었다면 rehash로 메모리가 이동해 **Broadcast 도중 잡고 있던 포인터가 댕글링**된다. `TSharedRef`로 접근하면 내부 배열이 이동해도 참조는 안전하다.

### 키 — `FGameplayAbilitySpecHandleAndPredictionKey`

```cpp
// GameplayAbilityTypes.h:504
struct FGameplayAbilitySpecHandleAndPredictionKey
{
    FGameplayAbilitySpecHandle AbilityHandle;
    int32 PredictionKeyAtCreation;   // FPredictionKey::Current 값만 저장

    friend uint32 GetTypeHash(...) {
        return GetTypeHash(AbilityHandle) ^ PredictionKeyAtCreation;
    }
};
```

PredictionKey가 키에 포함된 이유 — **같은 GA Spec이 연속으로 여러 번 활성화될 수 있기 때문**이다. LocalPredicted GA를 빠르게 연타하면 각 활성화마다 고유한 PredictionKey가 붙는다. 이를 키에 포함시켜야 서로 다른 활성화의 이벤트 상태가 충돌하지 않는다.

### 값 — `FAbilityReplicatedDataCache`

GenericEvents 외에도 TargetData 관련 상태까지 담긴다. 이름이 "TargetDataMap"인 이유가 여기 있다 — 원래 `WaitTargetData` AbilityTask용으로 설계됐고, 나중에 GenericEvents가 합류했다.

```cpp
// GameplayAbilityTypes.h:539
struct FAbilityReplicatedDataCache
{
    // WaitTargetData AbilityTask가 사용
    FGameplayAbilityTargetDataHandle TargetData;
    FGameplayTag                     ApplicationTag;
    bool                             bTargetConfirmed;
    bool                             bTargetCancelled;
    FAbilityTargetDataSetDelegate    TargetSetDelegate;
    FSimpleMulticastDelegate         TargetCancelledDelegate;

    // WaitInputPress / WaitConfirm / WaitCancel 등이 사용
    FAbilityReplicatedData GenericEvents[EAbilityGenericReplicatedEvent::MAX];
    //   └─ bTriggered:    bool
    //      VectorPayload: FVector_NetQuantize100
    //      Delegate:      FSimpleMulticastDelegate

    FPredictionKey PredictionKey;
};
```

### FindOrAdd — 조회 + 재활용

```cpp
// GameplayAbilityTypes.cpp:413
TSharedRef<FAbilityReplicatedDataCache> FindOrAdd(Key)
{
    // 1. InUseData 선형 탐색 (O(n) — 동시 활성 GA 수가 적어서 실용적)
    for (Pair : InUseData)
        if (Pair.Key == Key) return Pair.Value;

    // 2. FreeData 풀에서 재활용 — IsUnique()인 것만 (다른 참조자 없을 때)
    for (FreeRef : FreeData 역순)
        if (FreeRef.IsUnique())
        {
            FreeRef->ResetAll();   // 내용 초기화 + 델리게이트 바인딩 해제
            FreeData에서 제거;
            break;
        }

    // 3. 풀도 비었으면 신규 할당
    if (!SharedPtr) SharedPtr = new FAbilityReplicatedDataCache();

    InUseData.Emplace(Key, SharedPtr);
    return SharedPtr;
}
```

### Remove — GA 종료 시 재활용 풀로 반납

```cpp
// GameplayAbilityTypes.cpp:455
void Remove(Key)
{
    // InUseData에서 찾아 FreeData로 이동 (delete 하지 않음)
    FreeData.Add(InUseData[i].Value);
    InUseData.RemoveAtSwap(i);
}
```

GA가 `EndAbility()`로 종료될 때 `ClearAbilityReplicatedDataCache()`가 이 `Remove`를 호출한다. 객체는 삭제되지 않고 풀에 남아 다음 GA 활성화 때 재사용된다.

### 전체 구조

```
ASC.AbilityTargetDataMap
│
├─ InUseData: [ (Handle#1 + PredKey=42) → TSharedRef<Cache> ]
│                                                └─ GenericEvents[InputPressed].Delegate  ← WaitInputPress 구독 중
│             [ (Handle#2 + PredKey=43) → TSharedRef<Cache> ]
│                                                └─ TargetData, bTargetConfirmed, ...     ← WaitTargetData 대기 중
│
└─ FreeData:  [ TSharedRef<Cache(ResetAll 완료)> ]  ← 재활용 대기
```

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
