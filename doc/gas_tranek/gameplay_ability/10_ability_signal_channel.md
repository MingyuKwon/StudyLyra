# GA 인스턴스 신호 채널 — GenericReplicatedEvent

> 소스: `GameplayAbilityTargetTypes.h:662` · `AbilitySystemComponent_Abilities.cpp:3880`

---

## EAbilityGenericReplicatedEvent란 무엇이며, 각 슬롯은 어떤 AbilityTask에 대응하는가?

`EAbilityGenericReplicatedEvent`는 **활성화된 GA 인스턴스에 묶인 클라↔서버 양방향 신호 슬롯**이다.
하나의 GA 인스턴스가 여러 이벤트를 동시에 기다릴 수 있도록 슬롯 배열(`GenericEvents[MAX]`)로 관리된다.
슬롯은 고정 배열이라 미사용 슬롯도 항상 메모리에 존재하며, 동적 할당 오버헤드가 없다.

```cpp
// GameplayAbilityTargetTypes.h:662
namespace EAbilityGenericReplicatedEvent
{
    enum Type : int
    {
        GenericConfirm,           // WaitConfirm / WaitConfirmCancel
        GenericCancel,            // WaitCancel / WaitConfirmCancel
        InputPressed,             // WaitInputPress
        InputReleased,            // WaitInputRelease
        GenericSignalFromClient,  // WaitNetSync (클라 → 서버)
        GenericSignalFromServer,  // WaitNetSync (서버 → 클라)
        GameCustom1,              // 게임 전용 확장
        GameCustom2,
        GameCustom3,
        GameCustom4,
        GameCustom5,
        GameCustom6,
        MAX
    };
}
```

### GenericReplicatedEvent 슬롯별로 어떤 AbilityTask가 어떻게 연결되는가?

| 슬롯 | AbilityTask | 트리거 |
|---|---|---|
| `InputPressed` | `WaitInputPress` | 활성화 버튼 재입력 |
| `InputReleased` | `WaitInputRelease` | 활성화 버튼 뗌 |
| `GenericConfirm` | `WaitConfirm` / `WaitConfirmCancel` / `WaitTargetData` | 확인 버튼 |
| `GenericCancel` | `WaitCancel` / `WaitConfirmCancel` / `WaitTargetData` | 취소 버튼 |
| `GenericSignalFromClient` | `WaitNetSync` | 클라가 서버에게 "준비 완료" |
| `GenericSignalFromServer` | `WaitNetSync` | 서버가 클라에게 "진행해도 됨" |
| `GameCustom1~6` | 커스텀 태스크 | 게임 코드가 직접 발동 |

여러 슬롯을 동시에 기다리는 예시:

```
GA::ActivateAbility()
  → WaitInputRelease (InputReleased)  ← 버튼 뗌 → 차지 발사
  → WaitConfirm      (GenericConfirm) ← 다른 버튼 → 즉시 발동
  → WaitNetSync      (GenericSignalFromServer) ← 서버 준비 대기
  // 셋 중 먼저 오는 이벤트에 반응
```

---

## GenericReplicatedEvent의 이벤트 상태는 어디에 어떻게 저장되는가?

이벤트 상태는 ASC의 `AbilityTargetDataMap` (`FGameplayAbilityReplicatedDataContainer`)에 저장된다.
이름과 달리 실제 구현은 `TArray<(Key, TSharedRef<Cache>)>` 기반 커스텀 컨테이너다.

**키** — `AbilityHandle + PredictionKeyAtCreation(int32)`

같은 GA를 빠르게 연타하면 각 활성화마다 PredictionKey가 다르다. 키에 포함시켜야 인스턴스 간 이벤트가 충돌하지 않는다.

**값** — `FAbilityReplicatedDataCache`

원래 `WaitTargetData`를 위해 설계됐고 나중에 GenericEvents가 합류했다. 이름이 "TargetDataMap"인 이유가 여기 있다.

```cpp
struct FAbilityReplicatedDataCache
{
    // WaitTargetData가 사용
    FGameplayAbilityTargetDataHandle TargetData;
    bool bTargetConfirmed;
    bool bTargetCancelled;
    FAbilityTargetDataSetDelegate    TargetSetDelegate;
    FSimpleMulticastDelegate         TargetCancelledDelegate;

    // WaitInputPress / WaitConfirm / WaitCancel 등이 사용
    FAbilityReplicatedData GenericEvents[EAbilityGenericReplicatedEvent::MAX];
    //   └─ bTriggered, VectorPayload, Delegate(FSimpleMulticastDelegate)
};
```

**TMap 대신 TArray인 이유**: `Delegate.Broadcast()` 콜백 안에서 GA가 종료되면 `Remove()`가 호출된다. TMap이었다면 rehash로 메모리가 이동해 Broadcast 도중 포인터가 댕글링된다. `TSharedRef` + `TArray`로 관리하면 배열이 바뀌어도 참조는 안전하다.

---

## GenericReplicatedEvent는 어떻게 발동되며, 구독자가 없을 때 bTriggered만 저장하는 이유는?

### InvokeReplicatedEvent는 내부적으로 어떻게 동작하는가?

```cpp
// AbilitySystemComponent_Abilities.cpp:3880
bool InvokeReplicatedEvent(EventType, Handle, PredKey, ...)
{
    auto& Cache = AbilityTargetDataMap.FindOrAdd(Handle + PredKey);
    Cache->GenericEvents[(uint8)EventType].bTriggered = true;

    if (Cache->GenericEvents[EventType].Delegate.IsBound())
        Cache->GenericEvents[EventType].Delegate.Broadcast();  // 구독자 즉시 호출
    else
        return false;  // bTriggered=true만 저장 — 사후 처리 가능
}
```

구독자가 없을 때 `bTriggered=true`만 저장하는 이유는 타이밍 레이스 방어다.
서버에서 이벤트가 먼저 발동됐을 때 클라의 태스크가 아직 `Activate()`를 호출하지 않은 경우,
나중에 `CallReplicatedEventDelegateIfSet()`으로 사후에 이벤트를 처리할 수 있다.

### 각 GenericReplicatedEvent 슬롯은 누가 어떤 경로로 발동하는가?

**InputPressed / InputReleased** — ASC가 입력 처리 중 직접 발동

```
ProcessAbilityInput() → AbilitySpecInputPressed()
  → InvokeReplicatedEvent(InputPressed, Handle, PredKey)
```

**나머지 슬롯** — AbilityTask가 RPC를 보내면 수신 측에서 발동

```
클라 → ServerSetReplicatedEvent() RPC → 서버에서 InvokeReplicatedEvent()
서버 → ClientSetReplicatedEvent() RPC → 클라에서 InvokeReplicatedEvent()
```

**GenericConfirm / GenericCancel의 특이한 경로**

로컬 클라이언트는 `InvokeReplicatedEvent`를 거치지 않는다. `LocalInputConfirm()`이 별도의 `GenericLocalConfirmCallbacks` 델리게이트를 브로드캐스트하면 `WaitConfirmCancel`이 이를 받아 서버에 RPC를 보낸다. 서버 수신 경로에서만 `InvokeReplicatedEvent`가 발동된다.

```
[클라] LocalInputConfirm()
  → GenericLocalConfirmCallbacks.Broadcast()
      → WaitConfirmCancel::OnLocalConfirmCallback()
          ├─ ServerSetReplicatedEvent(GenericConfirm) ──→ [서버] InvokeReplicatedEvent()
          └─ OnConfirmCallback() 로컬 즉시 처리
```

### 이벤트 종류별 로컬 발동 주체와 RPC 전송 주체는 어떻게 다른가?

| 이벤트 | 로컬 발동 주체 | RPC 전송 주체 |
|---|---|---|
| `InputPressed` | `AbilitySpecInputPressed()` (ASC) | `WaitInputPress::OnPressCallback()` |
| `InputReleased` | `AbilitySpecInputReleased()` (ASC) | `WaitInputRelease::OnReleaseCallback()` |
| `GenericConfirm` | 없음 (클라는 LocalConfirmCallbacks 경유) | `WaitConfirmCancel`, `WaitTargetData` |
| `GenericCancel` | 없음 (클라는 LocalCancelCallbacks 경유) | `WaitConfirmCancel`, `WaitCancel`, `WaitTargetData` |
| `GenericSignalFromClient` | 없음 | `WaitNetSync` (클라 측) |
| `GenericSignalFromServer` | 없음 | `WaitNetSync` (서버 측) |
| `GameCustom1~6` | 게임 코드가 직접 `InvokeReplicatedEvent()` | 게임 코드가 직접 RPC 호출 |

---

## GenericReplicatedEvent를 구독하고 사후 처리하는 API는 어떻게 사용하는가?

```cpp
// 구독
DelegateHandle = ASC->AbilityReplicatedEventDelegate(
    EAbilityGenericReplicatedEvent::InputPressed,
    GetAbilitySpecHandle(),       // 이 GA 인스턴스에만 반응
    GetActivationPredictionKey()
).AddUObject(this, &ThisClass::OnCallback);

// 이미 발동된 이벤트 사후 처리 (타이밍 레이스 방어)
ASC->CallReplicatedEventDelegateIfSet(InputPressed, Handle, PredKey);

// 구독 해제
ASC->AbilityReplicatedEventDelegate(InputPressed, Handle, PredKey).Remove(DelegateHandle);
```

**WaitInputPress 전체 체인** (대표 예시):

```
[Activate()]
  AbilityReplicatedEventDelegate(InputPressed, handle, predKey).Add(OnPressCallback)

[ProcessAbilityInput — 이미 활성화된 스펙에 같은 입력]
  AbilitySpecInputPressed()
    → InvokeReplicatedEvent(InputPressed, handle, predKey)
        → OnPressCallback()
            ├─ Remove(DelegateHandle)
            ├─ ServerSetReplicatedEvent(InputPressed)  [PredictingClient인 경우]
            ├─ OnPress.Broadcast(ElapsedTime)          [GA로 결과 전달]
            └─ EndTask()
```

---

## GenericReplicatedEvent와 WaitGameplayEvent는 어떻게 다르며, 각각 언제 사용해야 하는가?

GenericReplicatedEvent는 **이 GA 인스턴스와 클라/서버가 통신하는 전용 채널**이다. 키가 `(Handle + PredKey)`이므로 발동자가 GA의 핸들을 알아야 하고, 입력 처리 흐름은 해당 입력에 매핑된 GA의 핸들만 다루기 때문에 "GA_A 실행 중 B 입력 받기" 같은 크로스 신호에는 쓸 수 없다.

`WaitGameplayEvent`는 Tag 기반이라 누가 발동하든 수신할 수 있지만, `HandleGameplayEvent`는 **로컬 전용**이다. RPC 메커니즘이 없어서 서버·클라 양쪽에서 발동하려면 개발자가 직접 처리해야 한다.

| | `GenericReplicatedEvent` | `WaitGameplayEvent` |
|---|---|---|
| 수신 조건 | 발동자가 GA Handle+PredKey를 알아야 함 | Tag만 맞으면 누구든 수신 |
| 크로스 GA 신호 | 불가 | 가능 |
| 동시 수신자 | 그 GA 인스턴스 하나 | Tag를 기다리는 모든 태스크 |
| 복제 | 내장 RPC (ServerSetReplicatedEvent 등) | 없음 — 로컬 전용 |
| 주 용도 | 같은 GA의 클라↔서버 이벤트 동기화 | GA 간 / 입력 → GA 신호 전달 |

WaitGameplayEvent를 쓸 때 서버에서 발동시키는 실용 패턴:

```
// GA_B를 서버 권한으로 실행해서 서버에서 HandleGameplayEvent 호출
B 입력 → GA_B 활성화 (서버 실행)
  GA_B::ActivateAbility()
    → ASC->HandleGameplayEvent(Tag_B, ...)
    → EndAbility()
// GA_A의 WaitGameplayEvent(Tag_B)가 서버에서 수신
```
