# IMC 평가 파이프라인

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

`PrepareInputDelegatesForEvaluation`이 매 틱 IMC → ActionMappings 변환 + Modifier/Trigger 평가 + 값 누적을 수행한다. `EvaluateInputDelegates` 내부에서 Super보다 먼저 호출된다.

---

## 전체 단계

```
PrepareInputDelegatesForEvaluation()
    1. DeltaTime 보정 (Time Dilation 제거)
    2. EnhancedActionMappings 순회        ← AddMappingContext 결과물
       각 Mapping per-tick:
          KeyState 조회 (RawValue)
          EKeyEvent 결정
          ProcessActionMappingEvent()
             ApplyModifiers(Mapping.Modifiers)   ← Mapping 레벨 Modifier
             EvaluateTriggers(Mapping.Triggers)  ← Mapping 레벨 Trigger
             값 누적 (AccumulationBehavior)
    3. InjectedInput 처리 (코드에서 직접 주입한 입력)
    4. Post-tick (ActionsWithEventsThisTick 순회):
          ApplyModifiers(Action.Modifiers)    ← Action 레벨 Modifier
          EvaluateTriggers(Action.Triggers)   ← Action 레벨 Trigger
          GetTriggerStateChangeEvent()        ← ETriggerEvent 확정
          ElapsedProcessedTime / ElapsedTriggeredTime 누적
```

---

## DeltaTime 보정

```cpp
const float Dilation = GetEffectiveTimeDilation();
const float NonDilatedDeltaTime = Dilation != 0.0f ? DeltaTime / Dilation : RealTimeDeltaSeconds;
```

Time Dilation이 적용된 DeltaTime을 제거해서 Timed Trigger(Hold 등)가 실제 시간 기준으로 작동하도록 한다. Dilation이 0이면 실제 경과 시간(`RealTimeDeltaSeconds`)을 fallback으로 사용한다.

---

## EKeyEvent 결정

```cpp
bool bKeyIsDown     = KeyState && (KeyState->bDown || IE_Pressed 이벤트 있음);
bool bKeyIsReleased = !bKeyIsDown && bDownLastTick;
bool bKeyIsHeld     = bKeyIsDown  && bDownLastTick;

EKeyEvent = bKeyIsHeld ? Held : ((bKeyIsDown || bKeyIsReleased) ? Actuated : None);
```

| EKeyEvent | 의미 |
|---|---|
| `None` | 이번 틱 이벤트 없음, 홀드도 아님 |
| `Actuated` | 이번 틱 상태 변화 발생 (Pressed/Released) |
| `Held` | 키 누름 지속 중 |

`EKeyEvent::None`이어도 `bHasAlwaysTickTrigger`(= `bShouldAlwaysTick`이 true인 Trigger 있음)이면 ProcessActionMappingEvent를 실행한다.

### 동일 틱 Pressed+Released 처리

OS에서 같은 프레임 안에 Pressed/Released가 모두 들어왔을 때 `RawValue`가 0으로 보이는 문제를 방지하기 위해:

```cpp
if (PressedThisTickValue && bKeyIsDown && IE_Pressed 이벤트 있음 && IE_Released 이벤트 있음 && RawKeyValue.IsZero())
    RawKeyValue = *PressedThisTickValue;
```

`InputKey()` 오버라이드에서 ButtonAxis 키의 Pressed 시 값을 `KeysPressedThisTick`에 저장해두고 여기서 복원한다.

---

## ProcessActionMappingEvent 내부

```cpp
// 1. 같은 Action을 처음 처리하는 틱이면 ActionData.Value를 0으로 리셋
if (!ActionsWithEventsThisTick.Contains(Action))
{
    ActionsWithEventsThisTick.Add(Action);
    ActionData.Value.Reset();
}

// 2. Mapping 레벨 Modifier 적용
FInputActionValue ModifiedValue = ApplyModifiers(Modifiers, RawKeyValue, DeltaTime);

// 3. Mapping 레벨 Trigger 평가
ETriggerState CalcedState = TriggerStateTracker.EvaluateTriggers(this, Triggers, ModifiedValue, DeltaTime);

// 4. 값 누적 (AccumulationBehavior)
//    TakeHighestAbsoluteValue (기본): 컴포넌트별로 절댓값이 더 큰 쪽 채택
//    Cumulative: 그냥 더함
ActionData.Value = Merged(ActionData.Value, ModifiedValue);

// 5. 이번 틱 가장 "강한" TriggerStateTracker 보존
ActionData.TriggerStateTracker = Max(ActionData.TriggerStateTracker, TriggerStateTracker);
```

같은 InputAction에 키가 여러 개 매핑된 경우(예: W키와 게임패드 스틱 모두 IA_Move), 이 함수가 키마다 호출되고 `ActionData.Value`에 누적된다.

---

## Post-tick — Action 레벨 처리

매핑 순회가 끝난 뒤 `ActionsWithEventsThisTick`에 등록된 Action들에 대해 Action 에셋에 정의된 Modifier/Trigger를 적용한다.

```cpp
// Action 레벨 Modifier
ActionData.Value = ApplyModifiers(ActionData.Modifiers, ActionData.Value, NonDilatedDeltaTime);

// Action 레벨 Trigger
TriggerState = ActionData.TriggerStateTracker.EvaluateTriggers(this, ActionData.Triggers, ActionData.Value, NonDilatedDeltaTime);

// Mapping 트리거가 있었으면 Action 트리거와 더 낮은 쪽(덜 발동된 쪽) 선택
TriggerState = ActionData.TriggerStateTracker.GetMappingTriggerApplied()
    ? Min(TriggerState, PrevState)
    : TriggerState;

// 게임 일시정지 중이고 bTriggerWhenPaused가 false면 강제 None
if (bGamePaused && !Action->bTriggerWhenPaused)
    TriggerState = ETriggerState::None;
```

### Mapping 트리거 vs Action 트리거 우선순위

Mapping 트리거가 존재하면 Action 트리거와 비교해서 더 엄격한(낮은) 쪽을 선택한다. 예: Mapping이 `Ongoing`인데 Action이 `Triggered`면 결과는 `Ongoing`.

---

## TriggerEvent 확정

```cpp
ActionData.TriggerEventInternal = GetTriggerStateChangeEvent(ActionData.LastTriggerState, TriggerState);
ActionData.TriggerEvent = ConvertInternalTriggerEvent(ActionData.TriggerEventInternal);
ActionData.LastTriggerState = TriggerState;
```

`GetTriggerStateChangeEvent`는 이전 프레임 상태와 이번 프레임 상태의 전환을 보고 이벤트를 결정한다. 자세한 전환 테이블은 [04_trigger.md](04_trigger.md) 참고.

---

## InjectInputForAction

코드에서 직접 입력을 주입하는 API. 단위 테스트나 AI 제어에 사용된다.

```cpp
PlayerInput->InjectInputForAction(IA_Jump, FInputActionValue(true), {}, {});
```

`InputsInjectedThisTick`에 저장되고 실제 키 매핑 순회 이후에 `ProcessActionMappingEvent`를 통해 동일하게 처리된다. 재주입이 없으면 다음 틱에 자동으로 "릴리즈" 처리된다.

---

## 매핑 제거 시 Canceled 이벤트

IMC가 제거되거나 매핑이 갱신될 때 기존 ActionInstanceData를 즉시 삭제하지 않는다.

```cpp
// EnhancedInput.ReconcileRemovedMappingDelegates = true (기본)
// 값을 0으로 리셋 → 다음 틱 평가에서 Canceled 이벤트 발생
ActionData.Value.Reset();
ActionsThatHaveBeenRemovedFromMappings.Add(Action);
```

바인딩 코드가 갑작스러운 종료 없이 `Canceled`를 받아 정리할 수 있도록 한다.
