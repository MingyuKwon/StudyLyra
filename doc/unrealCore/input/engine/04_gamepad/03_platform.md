# 패드 플랫폼 특수 기능

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Classes/GameFramework/PlayerController.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/InputCore/Classes/InputCoreTypes.h`

---

## 진동 피드백 — ForceFeedback vs Haptic

### ForceFeedback (범용 진동)

```cpp
// PlayerController.h:1253
void ClientPlayForceFeedback_Internal(UForceFeedbackEffect* Effect, FForceFeedbackParameters Params);
```

`UForceFeedbackEffect`에 Float 커브 4개를 지정한다.

| 채널 | 대응 모터 |
|------|----------|
| `bAffectsLeftLarge` | 왼쪽 대형 모터 (저주파, 강한 진동) |
| `bAffectsLeftSmall` | 왼쪽 소형 모터 (고주파, 세밀한 진동) |
| `bAffectsRightLarge` | 오른쪽 대형 모터 |
| `bAffectsRightSmall` | 오른쪽 소형 모터 |

Xbox/PS 패드 모두 4채널을 가지고 있다. 단, 실제 매핑은 플랫폼마다 다를 수 있다.

### Haptic (정밀 촉각 피드백)

```cpp
// PlayerController.h:1322
void PlayHapticEffect(UHapticFeedbackEffect_Base* HapticEffect, EControllerHand Hand, float Scale, bool bLoop);
void SetHapticsByValue(const float Frequency, const float Amplitude, EControllerHand Hand);
```

ForceFeedback보다 정밀하다. DualSense는 기존 진동보다 훨씬 세밀한 햅틱 모터를 탑재해, 이 API로 빗소리·질감 등을 표현할 수 있다.  
단, DualSense의 고급 햅틱 기능을 완전히 사용하려면 **Sony 플랫폼 SDK가 필요**하다.

---

## 모션 입력 (자이로스코프) — PlayStation 전용

PlayStation 패드(DualShock 4, DualSense)에는 자이로스코프와 가속도계가 내장되어 있다.  
Xbox 패드에는 없다.

```cpp
// PlayerInput.cpp:583
bool UPlayerInput::InputMotion(const FInputDeviceId DeviceId,
    const FVector& InTilt, const FVector& InRotationRate,
    const FVector& InGravity, const FVector& InAcceleration, ...)
{
    KeyStateMap.FindOrAdd(EKeys::Tilt).RawValueAccumulator         += InTilt;
    KeyStateMap.FindOrAdd(EKeys::RotationRate).RawValueAccumulator += InRotationRate;
    KeyStateMap.FindOrAdd(EKeys::Gravity).RawValueAccumulator      += InGravity;
    KeyStateMap.FindOrAdd(EKeys::Acceleration).RawValueAccumulator += InAcceleration;
}
```

모션 데이터도 **동일한 KeyStateMap/RawValueAccumulator 구조**로 처리된다. 별도 시스템이 아니다.

| FKey | 의미 |
|------|------|
| `EKeys::Tilt` | 패드의 기울기 (롤/피치/요) |
| `EKeys::RotationRate` | 각속도 (자이로스코프) |
| `EKeys::Gravity` | 중력 방향 벡터 |
| `EKeys::Acceleration` | 선형 가속도 (가속도계) |

Enhanced Input에서 이 키들을 InputAction에 바인딩하면 모션 입력을 게임에서 사용할 수 있다.

---

## 터치패드 — PlayStation 전용

DualShock 4/DualSense의 터치패드는 별도 FKey로 제공된다.

| FKey | 의미 |
|------|------|
| `Gamepad_Special_Left` | 터치패드 클릭 (버튼) |
| `Gamepad_Special_Left_X` | 터치패드 X 위치 (0 ~ 1) |
| `Gamepad_Special_Left_Y` | 터치패드 Y 위치 (0 ~ 1) |
| `Gamepad_Special_Left_Touched` | 클릭 없이 터치만 |

Xbox의 `View` 버튼이 `Gamepad_Special_Left`에 매핑되기도 한다. 두 패드를 동시 지원할 때 주의.

---

## 어댑티브 트리거 — PS5 DualSense 전용

DualSense의 L2/R2는 소프트웨어로 **물리적 저항을 제어**할 수 있다.  
활시위를 당기면 트리거가 딱딱해지는 식의 피드백이 가능하다.

언리얼 표준 API(`ForceFeedback`, `Haptic`)로는 **접근 불가**.  
Sony의 **PlayStation 5 플랫폼 SDK 플러그인**이 별도로 필요하다.  
표준 PC/Xbox 빌드에서는 사용할 수 없고, PS5 인증을 받은 개발자에게만 제공된다.

---

## PS 패드 버튼 명칭 혼란

언리얼은 패드 버튼을 위치(Bottom/Right/Left/Top)로 명명한다.

| FKey | Xbox 이름 | PlayStation 이름 | 기능 |
|------|-----------|------------------|------|
| `Gamepad_FaceButton_Bottom` | A | Cross (×) | 확인/점프 |
| `Gamepad_FaceButton_Right` | B | Circle (○) | 취소/뒤로 |
| `Gamepad_FaceButton_Left` | X | Square (□) | 액션 |
| `Gamepad_FaceButton_Top` | Y | Triangle (△) | 액션 |

**주의**: PlayStation에서는 전통적으로 ○(Circle)이 "확인", ×(Cross)가 "취소"였다 (특히 일본).  
Xbox는 A(Bottom)가 "확인", B(Right)가 "취소"다.  
언리얼의 `Gamepad_FaceButton_Bottom`이 두 패드에서 물리적으로 같은 위치지만, 플랫폼마다 **사용자가 기대하는 의미가 다를 수 있다**.
