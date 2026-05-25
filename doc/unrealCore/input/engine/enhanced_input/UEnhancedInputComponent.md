# UEnhancedInputComponent

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedInputComponent.h`

---

## 무엇인가

**Actor에 붙는 컴포넌트**로, `UInputAction`이 발동됐을 때 어떤 함수를 호출할지 바인딩을 저장한다.

- "IA_Move가 Triggered → Input_Move() 호출"
- "IA_Jump가 Triggered → Input_Jump() 호출"

이런 연결 목록을 갖고 있다가, `UEnhancedPlayerInput`이 매 틱 Action 상태를 결정하면 이 컴포넌트의 바인딩을 순회하며 해당 콜백을 실행한다.

---

## 클래스 위치

```
UActorComponent → UInputComponent → UEnhancedInputComponent
```

`UInputComponent`를 상속한다. `PlayerController`와 `Pawn` 각각에 하나씩 생성될 수 있다. 레거시 바인딩 메서드(`BindAction(FName, ...)` 등)는 `= delete`로 막혀 있다.

---

## 내부 저장소

```cpp
// 이벤트 바인딩 (BindAction 결과)
TArray<TUniquePtr<FEnhancedInputActionEventBinding>> EnhancedActionEventBindings;

// 값 구독 바인딩 (BindActionValue 결과 — 델리게이트 없이 현재 값만 추적)
TArray<FEnhancedInputActionValueBinding> EnhancedActionValueBindings;

// 비배포 전용 디버그 키 바인딩
TArray<TUniquePtr<FInputDebugKeyBinding>> DebugKeyBindings;
```

---

## 핵심 API

### BindAction — 이벤트 바인딩

Action이 특정 ETriggerEvent 상태가 됐을 때 콜백을 실행한다.

```cpp
// 시그니처 3종 (컴파일 타임에 자동 선택)
BindAction(Action, ETriggerEvent::Triggered, this, &UMyClass::OnTriggered);
//   → void OnTriggered()

BindAction(Action, ETriggerEvent::Triggered, this, &UMyClass::OnMove);
//   → void OnMove(const FInputActionValue& Value)

BindAction(Action, ETriggerEvent::Triggered, this, &UMyClass::OnCharge);
//   → void OnCharge(const FInputActionInstance& Instance)
```

**ETriggerEvent 선택 가이드**:

| ETriggerEvent | 사용 상황 |
|---|---|
| `Triggered` | 가장 일반적. 발동 조건이 충족된 동안 |
| `Started` | 발동 시작 순간 1회 |
| `Completed` | 발동 종료 순간 1회 (Triggered → None) |
| `Canceled` | 조건 미달로 취소된 순간 (Ongoing → None) |
| `Ongoing` | 조건 진행 중 매 틱 |

### VarTypes 패턴 — 값 고정 바인딩

```cpp
// FGameplayTag 같은 추가 인자를 바인딩 시점에 고정
BindAction(Action, ETriggerEvent::Triggered, this, &Input_AbilityPressed, InputTag);
//   → void Input_AbilityPressed(FGameplayTag Tag)
//   콜백 실행 시 Tag가 자동으로 전달됨. 입력값은 무시.
```

Lyra의 Ability 입력 패턴 핵심이다. 같은 함수 하나로 여러 Action을 처리할 수 있다.

### UFUNCTION 동적 바인딩 (Blueprint용)

```cpp
BindAction(Action, ETriggerEvent::Triggered, MyObject, FName("OnFire"));
```

FName 문자열로 UFUNCTION을 런타임에 찾는다. 타입 체크가 런타임에 일어난다.

### Lambda 바인딩

```cpp
InputComponent->BindActionValueLambda(IA_Move, ETriggerEvent::Triggered,
    [](const FInputActionValue& Value) {
        // ...
    });

InputComponent->BindActionInstanceLambda(IA_Charge, ETriggerEvent::Triggered,
    [](const FInputActionInstance& Instance) {
        // ...
    });
```

### BindActionValue — 값 구독

콜백 없이 Action의 현재 값을 폴링하고 싶을 때 사용한다.

```cpp
FEnhancedInputActionValueBinding& Binding = IC->BindActionValue(IA_Move);
// 나중에 폴링:
FInputActionValue CurrentVal = Binding.GetValue();
```

매 틱 자동으로 업데이트된다. 이벤트 기반이 아닌 폴링 방식이 필요할 때 유용하다.

### 바인딩 제거

```cpp
// 인덱스로 제거
IC->RemoveActionEventBinding(BindingIndex);

// 핸들로 제거 (BindAction 반환값의 GetHandle())
IC->RemoveBindingByHandle(Handle);

// FInputBindingHandle 레퍼런스로 제거
IC->RemoveBinding(BindingRef);

// 전체 초기화
IC->ClearActionEventBindings();
```

---

## FEnhancedInputActionEventBinding — 바인딩 단위 (non-UObject)

```cpp
struct FEnhancedInputActionEventBinding : FInputBindingHandle
{
    TWeakObjectPtr<const UInputAction> Action;  // 구독 대상 Action
    ETriggerEvent TriggerEvent;                 // 발동 조건 이벤트
    uint8 bConsumes : 1;                        // true이면 하위 우선순위 바인딩 차단
    
    virtual void Execute(const FInputActionInstance& ActionData) = 0;
};
```

실제 구현체는 `FEnhancedInputActionEventDelegateBinding<TSignature>`. 템플릿으로 3종 시그니처를 처리하며, Execute 시 시그니처에 맞는 인자만 추출해 델리게이트에 전달한다.

```
HandlerSignature  : Execute() → Delegate.Execute()                        // 인자 없음
ValueSignature    : Execute() → Delegate.Execute(ActionData.GetValue())   // 값만
InstanceSignature : Execute() → Delegate.Execute(ActionData)              // 값+타이밍 전체
```

### bConsumes — 하위 우선순위 차단

```cpp
// BindAction 반환값에서 설정
FEnhancedInputActionEventBinding& Binding = IC->BindAction(...);
Binding.SetShouldConsume(true);
```

`bConsumes = true`인 바인딩이 실행되면 같은 Action에 대한 하위 InputComponent의 바인딩이 이번 틱에 실행되지 않는다. `EnhancedInput.EnableListenerConsumption = 1`(기본)일 때 작동한다.

---

## 실행 흐름

```
UEnhancedPlayerInput::EvaluateInputComponentDelegates(InputComponent)
    ↓
    IC의 EnhancedActionEventBindings 순회
        ActionInstanceData에서 Action의 TriggerEvent 조회
        Binding.TriggerEvent == ActionData.TriggerEvent?
            → Binding.Execute(ActionData) 호출
            → 델리게이트 실행 → 바인딩된 함수 호출
```

---

## Lyra에서의 사용

```cpp
// LyraInputComponent.h (UEnhancedInputComponent 서브클래스)
class ULyraInputComponent : public UEnhancedInputComponent
{
    // 헬퍼 함수 추가
    void BindNativeAction(Config, Tag, TriggerEvent, Object, Func);
    void BindAbilityActions(Config, Object, PressedFunc, ReleasedFunc);
};
```

`BindAbilityActions`가 내부적으로 각 AbilityInputAction에 대해:
```cpp
BindAction(Action, Triggered, Object, PressedFunc, InputTag);   // VarTypes 패턴
BindAction(Action, Completed, Object, ReleasedFunc, InputTag);
```

---

## 요약

```
UEnhancedInputComponent
  = Actor에 붙는 Action→콜백 바인딩 저장소

핵심 API:
  BindAction(Action, ETriggerEvent, Object, Func [, VarTypes...])
  BindActionValue(Action)   ← 폴링용, 콜백 없음
  RemoveBinding(...)

UEnhancedPlayerInput이 매 틱 이 바인딩을 순회하며
Action의 TriggerEvent가 일치하면 Execute() 호출.
```
