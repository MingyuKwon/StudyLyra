# FInputActionValue와 FInputActionInstance

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputActionValue.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputAction.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

---

## FInputActionValue 내부 구조

```cpp
struct FInputActionValue
{
    FVector Value = FVector::ZeroVector;  // 실제 저장소. 항상 FVector
    EInputActionValueType ValueType;      // 논리적 타입
};
```

내부는 항상 `FVector`로 저장한다. ValueType이 실제 의미 있는 컴포넌트 수를 결정한다.

### EInputActionValueType

| 타입 | 에디터 표시 | 유효 컴포넌트 |
|---|---|---|
| `Boolean` | Digital (bool) | X만 (0.0 or 1.0) |
| `Axis1D` | Axis1D (float) | X만 |
| `Axis2D` | Axis2D (Vector2D) | X, Y |
| `Axis3D` | Axis3D (Vector) | X, Y, Z |

### 타입별 Get 특수화

```cpp
Value.Get<bool>()      // IsNonZero() — 어느 컴포넌트든 0이 아니면 true
Value.Get<float>()     // Value.X
Value.Get<FVector2D>() // {Value.X, Value.Y}
Value.Get<FVector>()   // Value 전체
```

### GetMagnitudeSq / GetMagnitude

ValueType에 따라 크기 계산 방식이 달라진다.

```cpp
switch (GetValueType())
{
case Boolean:
case Axis1D: return Value.X * Value.X;   // 1D 크기
case Axis2D: return Value.SizeSquared2D();
case Axis3D: return Value.SizeSquared();
}
```

`IsActuated()`(Trigger 내부에서 사용)가 `GetMagnitudeSq() >= Threshold * Threshold`이므로 타입에 맞는 크기 비교가 자동으로 이루어진다.

---

## 값 누적 — EInputActionAccumulationBehavior

같은 `InputAction`에 여러 키가 매핑된 경우(WASD + 스틱) `ProcessActionMappingEvent`가 키마다 호출되며 값을 누적한다.

```cpp
// InputAction 에셋에서 설정
EInputActionAccumulationBehavior AccumulationBehavior = TakeHighestAbsoluteValue; // 기본값
```

| AccumulationBehavior | 동작 |
|---|---|
| **TakeHighestAbsoluteValue** (기본) | 컴포넌트별로 절댓값이 더 큰 쪽 채택. 키보드와 스틱 동시 사용 시 더 강한 입력 우선 |
| **Cumulative** | 단순 합산. WASD에서 W(+1)와 S(-1)가 상쇄되길 원할 때 |

```cpp
// TakeHighestAbsoluteValue 구현 (컴포넌트별)
if (FMath::Abs(Modified[Component]) >= FMath::Abs(Merged[Component]))
    Merged[Component] = Modified[Component];
```

---

## FInputActionInstance — 타이밍 정보 포함

`ActionInstanceData`에 저장되는 실제 인스턴스 자료구조. `FInputActionValue`에 타이밍 필드가 추가된 형태다.

```
FInputActionValue Value         // 현재 값
ETriggerEvent TriggerEvent      // 이번 틱 이벤트
ETriggerState LastTriggerState  // 이전 프레임 상태 (전환 계산용)
float ElapsedProcessedTime      // None이 아닌 상태로 지속된 시간
float ElapsedTriggeredTime      // Triggered 상태로 지속된 시간
double LastTriggeredWorldTime   // 마지막 Triggered World Time
```

### 시간 누적 규칙

```cpp
// ElapsedProcessedTime: TriggerState가 None이 아닌 동안 누적
ActionData.ElapsedProcessedTime += TriggerState != ETriggerState::None ? NonDilatedDeltaTime : 0.f;

// ElapsedTriggeredTime: TriggerEvent가 Triggered일 때만 누적
ActionData.ElapsedTriggeredTime += (ActionData.TriggerEvent == ETriggerEvent::Triggered) ? NonDilatedDeltaTime : 0.f;
```

Canceled / Completed 이벤트가 발생하면 두 시간 모두 0으로 리셋된다.

---

## FindOrAddActionEventData — 인스턴스 생성 시점

```cpp
FInputActionInstance& UEnhancedPlayerInput::FindOrAddActionEventData(
    TObjectPtr<const UInputAction> Action) const
{
    FInputActionInstance* Instance = ActionInstanceData.Find(Action);
    if (!Instance)
    {
        Instance = &ActionInstanceData.Emplace(Action, FInputActionInstance(Action));
    }
    return *Instance;
}
```

첫 번째로 해당 Action의 키 이벤트가 처리될 때 생성된다. 이후 매핑이 제거되면 `Canceled` 이벤트 발송 후 `ActionsThatHaveBeenRemovedFromMappings` 처리 단계에서 삭제된다.

---

## InstanceSignature가 필요한 경우

```cpp
void Input_Charge(const FInputActionInstance& Inst)
{
    float HeldSeconds = Inst.GetElapsedTime();     // 눌린 총 시간
    float TriggeredSec = Inst.GetTriggeredTime();  // Triggered 상태 지속 시간
    UInputAction* Source = Inst.GetSourceAction(); // 어느 IA에서 왔는가
}
```

`FInputActionValue`만으로는 알 수 없는 지속 시간 정보가 필요한 차징, 홀드 피드백, 애니메이션 블렌딩 등에 사용한다.
