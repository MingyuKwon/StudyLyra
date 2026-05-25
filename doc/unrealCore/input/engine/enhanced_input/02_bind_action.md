# BindAction 오버로드 구조

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedInputComponent.h`

---

## 미리 정의된 핸들러 시그니처 3종

```cpp
DECLARE_DELEGATE(FEnhancedInputActionHandlerSignature);                              // void Func()
DECLARE_DELEGATE_OneParam(FEnhancedInputActionHandlerValueSignature,    FInputActionValue&);
DECLARE_DELEGATE_OneParam(FEnhancedInputActionHandlerInstanceSignature, FInputActionInstance&);
```

`DEFINE_BIND_ACTION` 매크로가 이 3종에 대한 `BindAction` 오버로드를 생성한다.

---

## 함수 파라미터로 오버로드 자동 선택

```cpp
void Input_Move(const FInputActionValue& Value)      // → ValueSignature 매칭
void Input_Charge(const FInputActionInstance& Inst)  // → InstanceSignature 매칭
void Input_AbilityPressed(FGameplayTag Tag)          // → HandlerSignature + VarTypes={FGameplayTag}
```

컴파일러가 함수 포인터의 파라미터 타입을 보고 어느 오버로드인지 자동 추론한다.

---

## Execute 특수화 — 실제 전달 방식

```cpp
// ValueSignature: 입력값만 꺼내서 전달
Delegate.Execute(ActionData.GetValue());

// InstanceSignature: Instance 통째로 전달 (타이밍 정보 포함)
Delegate.Execute(ActionData);

// HandlerSignature: 입력 데이터 무시, 델리게이트에 저장된 VarTypes 전달
Delegate.Execute();
```

---

## FInputActionValue vs FInputActionInstance

| | FInputActionValue | FInputActionInstance |
|---|---|---|
| **담긴 것** | 입력값만 | 입력값 + 타이밍 + 소스 |
| **추가 API** | `Get<FVector2D>()` 등 | `GetElapsedTime()`, `GetTriggeredTime()`, `GetSourceAction()` |
| **용도** | 이동/시점처럼 값만 필요할 때 | 차징/홀드처럼 지속 시간이 필요할 때 |

---

## VarTypes 바인딩 — 태그 고정 패턴

```cpp
// BindAbilityActions 내부
BindAction(Action.InputAction, Triggered, Object, PressedFunc, Action.InputTag);
//                                                              ↑ FGameplayTag 고정
```

`Action.InputTag`가 델리게이트 내부에 저장된다. Execute 시 저장된 태그를 꺼내 `Func(storedTag)` 호출. 입력값은 무시된다.

---

## 4번째 오버로드 — UFUNCTION 동적 바인딩

```cpp
BindAction(Action, TriggerEvent, UObject* Object, FName FunctionName)
```

C++ 함수 포인터가 아닌 UFUNCTION 이름(문자열)으로 런타임에 함수를 찾는 Blueprint용 경로. 타입 체크가 런타임에 일어나며 `DynamicSignature` 델리게이트를 사용한다.

---

## 오버로드가 컴파일 타임에 걸러내는 원리

핵심은 `BindUObject` 함수 포인터 파라미터 타입에 델리게이트 시그니처가 이미 박혀 있다는 것이다.

```cpp
// TDelegate<void(FInputActionValue&)> 내부의 BindUObject
template<class UserClass, typename... VarTypes>
void BindUObject(
    UserClass* Object,
    void (UserClass::*Func)(FInputActionValue&, VarTypes...),  // ← 시그니처 고정
    VarTypes... Payload
);
```

맞지 않는 함수를 넘기면 **템플릿 인자 추론 자체가 실패**해서 컴파일 에러가 난다.

```cpp
void Input_Move(const FInputActionValue& Value) { ... }
void Input_Jump() { ... }

BindAction(IA_Move, Triggered, this, &Input_Move);  // ValueSignature 오버로드 ✔
BindAction(IA_Jump, Triggered, this, &Input_Move);  // HandlerSignature에 맞지 않음 → 컴파일 에러 ✘
```

### 왜 오버로드인가 — 템플릿 특수화가 아닌 이유

`BindAction` 3개는 함수 포인터 파라미터 타입 자체가 처음부터 다르다.

```
HandlerSignature  버전: Func(VarTypes...)
ValueSignature    버전: Func(FInputActionValue&, VarTypes...)
InstanceSignature 버전: Func(FInputActionInstance&, VarTypes...)
```

특수화할 primary template이 없다. `DEFINE_BIND_ACTION` 매크로를 3번 전개해서 이름은 같지만 파라미터 타입이 다른 별개의 함수 3개를 만드는 것이다.
