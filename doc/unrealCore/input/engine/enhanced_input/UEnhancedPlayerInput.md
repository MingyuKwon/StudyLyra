# UEnhancedPlayerInput

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedPlayerInput.h`

---

## 무엇인가

**Enhanced Input 파이프라인의 실제 처리 엔진**이다. `PlayerController->PlayerInput`이 가리키는 클래스다.

매 틱:
1. `UEnhancedInputLocalPlayerSubsystem`의 활성 IMC 목록을 읽어 키→Action 변환을 수행한다.
2. 각 Action의 Modifier/Trigger를 평가해 `ETriggerEvent`를 결정한다.
3. `UEnhancedInputComponent`의 바인딩을 순회하며 조건에 맞는 콜백을 실행한다.

---

## 클래스 위치

```
UObject → UPlayerInput → UEnhancedPlayerInput
```

`UPlayerInput`의 서브클래스이므로 레거시 입력 처리(`KeyStateMap`, `EvaluateKeyMapState` 등)를 그대로 상속받는다. Enhanced Input 기능을 **오버라이드**로 끼워 넣는 구조다.

---

## 핵심 멤버

```cpp
// IMC에서 빌드된 런타임 매핑 (매 틱 순회 대상)
TArray<FEnhancedActionKeyMapping> EnhancedActionMappings;

// Action별 런타임 인스턴스 (값 + 타이밍 + 트리거 상태)
mutable TMap<TObjectPtr<const UInputAction>, FInputActionInstance> ActionInstanceData;

// 이번 틱 이벤트가 있었던 Action 집합 (Post-tick 처리 대상)
TSet<TObjectPtr<const UInputAction>> ActionsWithEventsThisTick;

// 이전 틱 키 Down 상태 스냅샷 (Held 판단용)
TMap<FKey, bool> KeyDownPrevious;

// 코드에서 주입한 입력
TMap<TObjectPtr<const UInputAction>, FInjectedInputArray> InputsInjectedThisTick;

// 현재 입력 모드 태그 컨테이너
FGameplayTagContainer CurrentInputMode;
```

---

## 오버라이드된 핵심 함수

### EvaluateKeyMapState — 키 상태 스냅샷 확정

```cpp
virtual void EvaluateKeyMapState(float DeltaTime, bool bGamePaused,
    OUT TArray<TPair<FKey, FKeyState*>>& KeysWithEvents) override;
```

Super(레거시) 호출 전에 `KeyDownPrevious`를 갱신한다. 이전 틱의 키 Down 상태를 기록해두어, 다음 단계에서 `Held` / `Released`를 판단하는 데 사용한다.

### PrepareInputDelegatesForEvaluation — IMC 평가 + 값 누적

```cpp
virtual void PrepareInputDelegatesForEvaluation(
    const TArray<UInputComponent*>& InputComponentStack,
    float DeltaTime, bool bGamePaused,
    const TArray<TPair<FKey, FKeyState*>>& KeysWithEvents) override;
```

Enhanced Input의 핵심 함수. 매 틱 이 순서로 실행된다:

```
1. NonDilatedDeltaTime 계산 (TimeDilation 제거)
2. EnhancedActionMappings 순회
   각 Mapping:
     KeyState 조회 → EKeyEvent 결정 (None / Actuated / Held)
     ProcessActionMappingEvent()
       Mapping 레벨 Modifier 적용
       Mapping 레벨 Trigger 평가
       AccumulationBehavior로 값 누적
3. InjectInput 처리
4. Post-tick (ActionsWithEventsThisTick):
     Action 레벨 Modifier 적용
     Action 레벨 Trigger 평가
     ETriggerEvent 확정 (GetTriggerStateChangeEvent)
     ElapsedProcessedTime / ElapsedTriggeredTime 누적
```

상세 내용 → [03_imc_evaluation.md](03_imc_evaluation.md)

### EvaluateInputComponentDelegates — 콜백 실행

```cpp
virtual bool EvaluateInputComponentDelegates(
    UInputComponent* const InputComponent,
    const TArray<TPair<FKey, FKeyState*>>& KeysWithEvents,
    float DeltaTime, bool bGamePaused) override;
```

`UEnhancedInputComponent`의 바인딩 배열을 순회하며 `ActionInstanceData`에서 해당 Action의 `TriggerEvent`를 조회한다. Binding의 `TriggerEvent`와 일치하면 `Binding.Execute(ActionData)` 호출.

---

## ProcessActionMappingEvent — 내부 처리 단위

키 하나의 매핑 이벤트를 처리한다. `PrepareInputDelegatesForEvaluation` 내부에서 Mapping마다 호출된다.

```cpp
void ProcessActionMappingEvent(
    TObjectPtr<const UInputAction> Action,
    float DeltaTime,
    bool bGamePaused,
    FInputActionValue RawKeyValue,
    EKeyEvent KeyEvent,          // None / Actuated / Held
    const TArray<UInputModifier*>& Modifiers,
    const TArray<UInputTrigger*>& Triggers,
    const bool bHasAlwaysTickTrigger = false);
```

```
1. Action을 처음 처리하는 틱이면 ActionData.Value 리셋
2. ApplyModifiers()로 RawKeyValue 변환
3. TriggerStateTracker.EvaluateTriggers()로 Trigger 평가
4. AccumulationBehavior에 따라 ActionData.Value에 누적
5. TriggerStateTracker 중 가장 강한 것 보존
```

---

## GetTriggerStateChangeEvent — 이벤트 전환 결정

이전 프레임 `ETriggerState`와 이번 프레임 `ETriggerState`를 비교해서 `ETriggerEvent`를 결정한다.

```
None → Ongoing     = Started
None → Triggered   = StartedAndTriggered (내부), 외부에는 Started+Triggered 둘 다 발생
Ongoing → None     = Canceled
Ongoing → Ongoing  = Ongoing
Ongoing → Triggered = Triggered
Triggered → Triggered = Triggered
Triggered → Ongoing  = Ongoing
Triggered → None     = Completed
```

---

## InjectInputForAction — 코드에서 입력 주입

```cpp
void InjectInputForAction(
    TObjectPtr<const UInputAction> Action,
    FInputActionValue RawValue,
    const TArray<UInputModifier*>& Modifiers,
    const TArray<UInputTrigger*>& Triggers);
```

`InputsInjectedThisTick`에 저장. 실제 키 매핑 순회 후 동일한 파이프라인으로 처리됨.  
재주입 없으면 다음 틱에 자동으로 "릴리즈" 처리된다.

주로 AI, 단위 테스트, 튜토리얼에서 사용한다.

---

## FInputActionInstance — Action 런타임 인스턴스

`ActionInstanceData` 맵에 Action당 하나씩 생성된다.

```cpp
struct FInputActionInstance
{
    FInputActionValue Value;            // 이번 틱 최종 값
    ETriggerEvent TriggerEvent;         // 이번 틱 이벤트
    ETriggerState LastTriggerState;     // 이전 틱 상태 (전환 계산용)
    float ElapsedProcessedTime;         // Trigger 비None 상태 지속 시간
    float ElapsedTriggeredTime;         // Triggered 상태 지속 시간
    double LastTriggeredWorldTime;      // 마지막 Triggered World 시각
};
```

`BindAction`의 InstanceSignature로 바인딩하면 콜백에서 이 인스턴스 전체에 접근 가능하다.

---

## 레거시와의 공존

`EvaluateInputDelegates`에서 먼저 Enhanced 처리를 수행하고, 마지막에 `Super::EvaluateInputComponentDelegates()`를 호출해 레거시 바인딩도 실행한다. 즉 Enhanced와 레거시를 같은 PlayerInput이 순서대로 처리한다.

---

## 요약

```
UEnhancedPlayerInput = 매 틱 처리 엔진 (PC->PlayerInput)

흐름:
  EvaluateKeyMapState()          ← 키 상태 스냅샷, KeyDownPrevious 갱신
  PrepareInputDelegatesForEvaluation()  ← IMC 평가, Modifier/Trigger, ETriggerEvent 확정
  EvaluateInputComponentDelegates()    ← 바인딩 순회, 콜백 실행

핵심 멤버:
  EnhancedActionMappings[]  ← IMC에서 빌드된 런타임 매핑
  ActionInstanceData{}      ← Action별 FInputActionInstance (값+타이밍+상태)
```
