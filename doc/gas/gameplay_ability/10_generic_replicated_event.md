# GenericReplicatedEvent

> 소스: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/GameplayAbilityTargetTypes.h:662`  
> `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:3880`

---

## 개념

`EAbilityGenericReplicatedEvent`는 **활성화된 GA 인스턴스에 묶인 신호 슬롯**이다.
이름의 "Replicated"는 클라↔서버 RPC로 동기화되기 때문에 붙었다.

```cpp
// GameplayAbilityTargetTypes.h:662
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

슬롯이 많은 이유는 **하나의 GA가 여러 이벤트를 동시에 기다릴 수 있기 때문**이다.
`FAbilityReplicatedDataCache` 안에 `GenericEvents[MAX]`로 고정 배열이 선언돼 있어, 사용하지 않는 슬롯도 항상 메모리에 존재한다. 동적 할당이 없으므로 슬롯 수가 많아도 오버헤드는 없다.

### 슬롯별 용도

#### InputPressed / InputReleased — 버튼 재입력 감지

같은 버튼을 누르거나 뗄 때를 GA 실행 도중 감지한다.

```
// 차지 후 발사 — Q 누름으로 활성화, Q 뗌으로 발사
GA::ActivateAbility()
  → WaitInputRelease 시작 (InputReleased 슬롯 구독)
  → 뗄 때까지 차지 애니메이션 재생

Q 뗌 → InputReleased 발동 → 발사 처리
```

```
// 2단계 어빌리티 — Q 다시 눌러 2단계 발동
GA::ActivateAbility()
  → 1단계 시작
  → WaitInputPress 시작 (InputPressed 슬롯 구독)

Q 다시 누름 → InputPressed 발동 → 2단계 발동
```

#### GenericConfirm / GenericCancel — 타겟 확인/취소

타겟 선택 UI에서 확인 또는 취소를 받을 때 쓴다.
`WaitTargetData`와 함께 쓰이는 경우가 가장 많다.

```
// R로 스킬 활성화 → 타겟 선택 → 좌클릭 확인 or ESC 취소
GA::ActivateAbility()
  → WaitTargetData + WaitConfirm 시작 (GenericConfirm 슬롯 구독)
  → 타겟 선택 UI 표시

좌클릭 → LocalInputConfirm() → GenericConfirm 발동 → 스킬 시전
ESC    → LocalInputCancel()  → GenericCancel 발동  → 취소
```

`LocalInputConfirm()` / `LocalInputCancel()`은 `ProcessAbilityInput`과 별개로 ASC에서 직접 호출된다.

#### GenericSignalFromClient / GenericSignalFromServer — WaitNetSync

클라↔서버 실행 타이밍을 맞출 때 쓴다.
`WaitNetSync` AbilityTask가 이 두 슬롯을 내부적으로 사용한다.

```
// 서버만 기다리는 경우 (OnlyServerWait)
[Client] WaitNetSync → ServerSetReplicatedEvent(GenericSignalFromClient) RPC 전송 후 즉시 진행
[Server] WaitNetSync → GenericSignalFromClient 신호를 받을 때까지 대기 → 이후 진행

// 클라만 기다리는 경우 (OnlyClientWait)
[Server] WaitNetSync → ClientSetReplicatedEvent(GenericSignalFromServer) RPC 전송 후 즉시 진행
[Client] WaitNetSync → GenericSignalFromServer 신호를 받을 때까지 대기 → 이후 진행
```

#### GameCustom1~6 — 게임 전용 확장

엔진이 정의한 슬롯(Confirm/Cancel/InputPressed/Released/Signal)으로 해결되지 않는 경우에 쓴다.
주로 다단계 어빌리티에서 단계 간 동기화 신호로 활용한다.

```
// 3단계 콤보 어빌리티 — 각 단계를 커스텀 이벤트로 동기화
GA::ActivateAbility()
  → 1단계 애니메이션 재생
  → WaitCustomEvent(GameCustom1) 대기     ← 애니 노티파이 → 2단계 준비 신호

2단계 시작:
  → InvokeReplicatedEvent(GameCustom1, Handle, PredKey)
  → 2단계 애니메이션 재생
  → WaitCustomEvent(GameCustom2) 대기

3단계 시작: ...
```

실제로 같은 GA 인스턴스에서 여러 슬롯을 동시에 쓰는 예시:

```
GA::ActivateAbility()
  → WaitInputRelease (InputReleased 슬롯)  ← "중간에 취소하면 즉시 종료"
  → WaitConfirm      (GenericConfirm 슬롯) ← "다른 버튼으로 즉시 발동"
  → WaitNetSync      (GenericSignalFromServer 슬롯) ← "서버 준비 대기"
  // 셋 중 먼저 오는 이벤트에 반응
```

슬롯이 12개인 덕분에 이런 복합 대기가 동일한 GA 인스턴스 안에서 겹치지 않고 동작한다.

---

## 저장소 — AbilityTargetDataMap

이벤트 상태는 ASC의 `AbilityTargetDataMap` (`FGameplayAbilityReplicatedDataContainer`)에 저장된다.
이름에 "Map"이 붙어 있지만 실제 구현은 `TArray<(Key, TSharedRef<Cache>)>` 기반의 커스텀 컨테이너다.

**키** — `FGameplayAbilitySpecHandleAndPredictionKey`

```
AbilityHandle + PredictionKeyAtCreation(int32)
```

PredictionKey까지 키에 포함시키는 이유는 같은 GA를 빠르게 연타했을 때 각 활성화 인스턴스의 이벤트가 충돌하지 않게 하기 위해서다.

**값** — `FAbilityReplicatedDataCache`

원래 `WaitTargetData` AbilityTask를 위해 만들어졌고 나중에 GenericEvents가 합류했다. 이름이 "TargetDataMap"인 이유가 여기 있다.

```cpp
struct FAbilityReplicatedDataCache
{
    // WaitTargetData가 사용
    FGameplayAbilityTargetDataHandle TargetData;
    bool bTargetConfirmed;
    bool bTargetCancelled;
    FAbilityTargetDataSetDelegate TargetSetDelegate;
    FSimpleMulticastDelegate      TargetCancelledDelegate;

    // WaitInputPress / WaitConfirm / WaitCancel 등이 사용
    FAbilityReplicatedData GenericEvents[EAbilityGenericReplicatedEvent::MAX];
    //   └─ bTriggered, VectorPayload, Delegate(FSimpleMulticastDelegate)
};
```

**TMap 대신 TArray를 쓰는 이유**

`Delegate.Broadcast()` 콜백 안에서 GA가 종료되면 `Remove()`가 호출된다. TMap이었다면 rehash로 메모리가 이동해 Broadcast 도중 잡고 있던 포인터가 댕글링된다. `TSharedRef` + `TArray`로 관리하면 배열이 바뀌어도 참조는 안전하다.

---

## InvokeReplicatedEvent — 로컬 발동

```cpp
// AbilitySystemComponent_Abilities.cpp:3880
bool UAbilitySystemComponent::InvokeReplicatedEvent(EventType, Handle, PredKey, ...)
{
    auto& Cache = AbilityTargetDataMap.FindOrAdd(Handle + PredKey);
    Cache->GenericEvents[(uint8)EventType].bTriggered = true;

    if (Cache->GenericEvents[EventType].Delegate.IsBound())
    {
        Cache->GenericEvents[EventType].Delegate.Broadcast();
        return true;
    }
    return false;  // bTriggered=true만 저장 — 구독자가 나중에 사후 처리 가능
}
```

구독자가 없을 때 `bTriggered = true`만 저장하는 이유는 **타이밍 레이스** 방어다.
서버에서 이벤트가 먼저 발동됐는데 클라의 `WaitInputPress`가 아직 `Activate()`를 호출하지 않은 경우,
나중에 `Activate()` 안에서 `CallReplicatedEventDelegateIfSet()`으로 사후 처리할 수 있다.

---

## RPC 동기화

로컬 발동만으로는 반대편에 이벤트가 전달되지 않는다. 별도 RPC 호출이 필요하다.

```
클라 → 서버:  ServerSetReplicatedEvent()  → 서버에서 InvokeReplicatedEvent()
서버 → 클라:  ClientSetReplicatedEvent()  → 클라에서 InvokeReplicatedEvent()
```

LocalPredicted GA라면 클라가 먼저 로컬에서 `InvokeReplicatedEvent()`를 호출하고,
이어서 `ServerSetReplicatedEvent()` RPC로 서버에도 같은 이벤트를 발동시킨다.

---

## 구독 방법 — AbilityReplicatedEventDelegate

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

---

## WaitInputPress 전체 체인

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
  Remove(DelegateHandle)                       ← 구독 해제
  if (IsPredictingClient())
      ServerSetReplicatedEvent(InputPressed)   ← 서버에 알림
  else
      ConsumeGenericReplicatedEvent()          ← 서버 측: 이벤트 소비
  OnPress.Broadcast(ElapsedTime)               ← GA로 결과 전달
  EndTask()
```

---

## 설계 의도 — "같은 GA 인스턴스 내 통신"

GenericReplicatedEvent는 **이 GA 인스턴스와 클라/서버 양측이 통신하는 채널**이다.
`AbilityReplicatedEventDelegate`의 키가 `(Handle + PredKey)` — GA 인스턴스에 묶여 있다.

이 때문에 `GameCustom1~6` 슬롯이 있어도 "A GA 실행 중 B 키 입력 받기" 같은 **크로스 입력 신호**에는 쓸 수 없다.

B 키가 눌렸을 때의 흐름을 보면 이유가 명확하다:

```
[B 키 누름]
  ProcessAbilityInput()
    → B에 매핑된 GA_B의 Spec 핸들을 찾음
        → InvokeReplicatedEvent(InputPressed, GA_B_Handle, ...)
```

이 흐름은 GA_A의 핸들을 전혀 모른다. GA_A의 `GameCustom1` 슬롯을 발동시키려면
GA_A의 Handle + PredKey를 알고 직접 `InvokeReplicatedEvent`를 호출하는 코드가 있어야 하는데,
입력 처리 흐름에 그 경로가 없다.

"실행 중인 GA에서 다른 입력을 받아야 할 때"는 `WaitGameplayEvent`를 써야 한다.
`HandleGameplayEvent(Tag_B, ...)` 는 Tag만 맞으면 누가 어느 GA 핸들을 쓰는지 무관하게 브로드캐스트하기 때문이다.

| | `GenericReplicatedEvent (GameCustom1~6)` | `WaitGameplayEvent` |
|---|---|---|
| 수신 조건 | 발동자가 GA의 Handle+PredKey를 알아야 함 | Tag만 맞으면 누구든 수신 |
| 크로스 GA 신호 | 불가 | 가능 |
| 동시 수신자 | 그 GA 인스턴스 하나 | 해당 Tag를 기다리는 모든 태스크 |
| 슬롯 수 | 6개 고정 | GameplayTag 무제한 |
| 주 용도 | 같은 GA의 클라↔서버 동기화 | GA 간 / 입력 → GA 신호 전달 |

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

`WaitConfirm` / `WaitCancel`은 `ProcessAbilityInput`이 아니라 ASC의 `LocalInputConfirm()` / `LocalInputCancel()`이 각각 `InvokeReplicatedEvent`를 발동시킨다.
