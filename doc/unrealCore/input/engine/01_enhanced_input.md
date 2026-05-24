# Enhanced Input — Subsystem vs Component

> 소스: `Source/LyraGame/Character/LyraHeroComponent.cpp`

Enhanced Input은 역할이 다른 두 클래스로 분리되어 있다.

PreProcessor와의 관계(FEnhancedInputWorldProcessor — WorldSubsystem 전달 경로): [02_preprocessor.md](02_preprocessor.md)

---

## 역할 분리

| | UEnhancedInputLocalPlayerSubsystem | UEnhancedInputComponent |
|---|---|---|
| **부착 대상** | LocalPlayer (플레이어당 하나) | Actor (Pawn, PC 등) |
| **역할** | 활성 IMC 관리, 키 → Action 변환 | Action → 콜백 바인딩 |

---

## 처리 흐름

```
[키 입력]
    ↓
UEnhancedInputLocalPlayerSubsystem
  활성 IMC 목록을 보고 "W키 → IA_Move" 변환
    ↓
UEnhancedInputComponent
  "IA_Move Triggered → Input_Move() 호출"
    ↓
[함수 실행]
```

**Subsystem** = 키 → Action 번역기 (어떤 컨텍스트가 켜져 있는가)  
**Component** = Action → 함수 라우터 (발생한 Action을 누구에게 전달하는가)

---

## Lyra 코드에서의 분리

```cpp
// Subsystem: IMC 활성화 (어떤 키가 어떤 Action으로 바뀌는가)
Subsystem->AddMappingContext(IMC, Mapping.Priority, Options);

// Component: 콜백 바인딩 (Action 발생 시 뭘 실행하는가)
LyraIC->BindNativeAction(InputConfig, TAG_Move, ETriggerEvent::Triggered, this, &Input_Move);
```

두 작업이 모두 `InitializePlayerInput()`에서 일어나지만 역할은 완전히 다르다.

---

## BindAction 오버로드 구조 — 어떻게 다른 시그니처를 받는가

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedInputComponent.h`

### 미리 정의된 핸들러 시그니처 3종

```cpp
DECLARE_DELEGATE(FEnhancedInputActionHandlerSignature);                              // void Func()
DECLARE_DELEGATE_OneParam(FEnhancedInputActionHandlerValueSignature,    FInputActionValue&);  // void Func(Value)
DECLARE_DELEGATE_OneParam(FEnhancedInputActionHandlerInstanceSignature, FInputActionInstance&); // void Func(Instance)
```

`DEFINE_BIND_ACTION` 매크로가 이 3종에 대한 `BindAction` 오버로드를 생성한다.

```cpp
template<class UserClass, typename... VarTypes>
FEnhancedInputActionEventBinding& BindAction(
    ...,
    typename HANDLER_SIG::template TMethodPtr<UserClass, VarTypes...> Func,
    VarTypes... Vars)   // 추가 인자를 가변 템플릿으로 받음
```

### 함수 파라미터로 오버로드 자동 선택

```cpp
void Input_Move(const FInputActionValue& Value)      // → ValueSignature 매칭
void Input_Charge(const FInputActionInstance& Inst)  // → InstanceSignature 매칭
void Input_AbilityPressed(FGameplayTag Tag)          // → HandlerSignature + VarTypes={FGameplayTag} 매칭
```

컴파일러가 함수 포인터의 파라미터 타입을 보고 어느 오버로드인지 자동으로 추론한다.

### Execute 특수화 — 실제 전달 방식

```cpp
// ValueSignature: 입력값만 꺼내서 전달
Delegate.Execute(ActionData.GetValue());

// InstanceSignature: Instance 통째로 전달 (타이밍 정보 포함)
Delegate.Execute(ActionData);

// HandlerSignature: 입력 데이터 무시, 델리게이트에 저장된 VarTypes 전달
Delegate.Execute();
```

### FInputActionValue vs FInputActionInstance

| | FInputActionValue | FInputActionInstance |
|---|---|---|
| **담긴 것** | 입력값만 | 입력값 + 타이밍 + 소스 |
| **추가 API** | `Get<FVector2D>()` 등 | `GetElapsedTime()`, `GetTriggeredTime()`, `GetSourceAction()` |
| **용도** | 이동/시점처럼 값만 필요할 때 | 차징/홀드처럼 지속 시간이 필요할 때 |

### VarTypes 바인딩 (태그 고정 패턴)

```cpp
// BindAbilityActions 내부
BindAction(Action.InputAction, Triggered, Object, PressedFunc, Action.InputTag);
//                                                              ↑ FGameplayTag 고정
```

`Action.InputTag`가 `CreateUObject(Object, Func, InputTag)`로 델리게이트 내부에 저장된다.
Execute 시 `Delegate.Execute()`가 불리면 저장된 태그를 꺼내 `Func(storedTag)` 호출.
입력값은 무시되고 바인딩 시점에 고정한 값만 전달된다.

### 4번째 오버로드 — UFUNCTION 동적 바인딩

```cpp
BindAction(Action, TriggerEvent, UObject* Object, FName FunctionName)
```

C++ 함수 포인터가 아닌 UFUNCTION 이름(문자열)으로 런타임에 함수를 찾는 Blueprint용 경로.
타입 체크가 런타임에 일어나며 `DynamicSignature` 델리게이트를 사용한다.

---

### 오버로드 3개가 필터링하는 원리

`BindAction`에 함수를 넘기면 해당 함수가 실제로 바인딩 가능한지를 **컴파일 타임에** 걸러낸다. 런타임 체크나 if 분기가 없다.

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

BindAction(IA_Move, Triggered, this, &Input_Move);
// 함수 포인터 타입: void(*)(FInputActionValue&) → ValueSignature 오버로드 ✔

BindAction(IA_Jump, Triggered, this, &Input_Move);
// 함수 포인터 타입: void(*)(FInputActionValue&) → HandlerSignature 오버로드에 맞지 않음
// → 템플릿 인자 추론 실패, 컴파일 에러 ✘
```

### 왜 오버로드인가 — 템플릿 특수화가 아닌 이유

템플릿 특수화는 하나의 primary template을 특정 타입에 대해 다르게 구현하는 것이다.

```cpp
// 특수화라면 이런 모습
template<typename T> void Func(T);   // primary
template<> void Func<int>(int);      // int 특수화
```

`BindAction` 3개는 함수 포인터 파라미터 타입 자체가 처음부터 다르다.

```
HandlerSignature  버전: Func(VarTypes...)
ValueSignature    버전: Func(FInputActionValue&, VarTypes...)
InstanceSignature 버전: Func(FInputActionInstance&, VarTypes...)
```

특수화할 primary template이 존재하지 않는다. `DEFINE_BIND_ACTION` 매크로를 3번 전개해서 이름은 같지만 파라미터 타입이 다른 **별개의 함수 3개**를 만드는 것이다.

