# 패드(게임패드) 입력

> 출처: `C:/UE_5.7/Engine/Source/Runtime/InputCore/Classes/InputCoreTypes.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputModifiers.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Classes/GameFramework/PlayerController.h`

---

## 핵심 전제 — 패드도 같은 파이프라인을 쓴다

패드 버튼과 스틱은 키보드 키와 동일하게 `FKey`로 추상화된다.  
OS 이벤트 → `UPlayerInput::InputKey()` → `EventAccumulator` → 매 틱 flush 흐름이 **완전히 동일**하다.

```cpp
// InputCoreTypes.h — 패드 키 목록
FKey Gamepad_FaceButton_Bottom   // Xbox: A, PS: Cross(×)
FKey Gamepad_FaceButton_Right    // Xbox: B, PS: Circle(○)
FKey Gamepad_LeftX               // 왼쪽 스틱 수평축 (-1 ~ 1)
FKey Gamepad_RightY              // 오른쪽 스틱 수직축 (-1 ~ 1)
FKey Gamepad_LeftTriggerAxis     // L2 아날로그 (0 ~ 1)
FKey Gamepad_LeftTrigger         // L2 디지털 (0 or 1) — 같은 하드웨어, 다른 해석
```

---

## 키보드와의 결정적 차이 — 디지털 vs 아날로그

키보드 키는 누르면 1, 놓으면 0이다.  
패드 스틱과 트리거는 **소수점 값**을 매 프레임 보낸다.

```
키보드 A키    → EventAccumulator에 IE_Pressed 이벤트 1개 추가
패드 왼쪽 스틱 → RawValueAccumulator에 (X=-0.73, Y=0.41) 누적 (매 틱)
```

| 입력 종류 | 타입 | 범위 | FKey 예시 |
|----------|------|------|-----------|
| 버튼 | 디지털 | 0 or 1 | `Gamepad_FaceButton_Bottom` |
| 스틱 축 | 아날로그 | -1.0 ~ 1.0 | `Gamepad_LeftX`, `Gamepad_RightY` |
| 트리거 (아날로그) | 아날로그 | 0.0 ~ 1.0 | `Gamepad_LeftTriggerAxis` |
| 트리거 (디지털) | 디지털 | 0 or 1 | `Gamepad_LeftTrigger` |

트리거가 두 FKey로 분리된 이유: 같은 하드웨어를 **조금만 눌러도 반응하는 버튼**으로 쓸 수도 있고, **얼마나 눌렀는지 측정하는 축**으로 쓸 수도 있기 때문이다.

---

## 데드존 — 스틱이 0으로 돌아오지 않는 문제

물리 스틱은 손을 떼도 정확히 (0, 0)으로 돌아오지 않는다.  
그대로 두면 캐릭터가 미세하게 표류한다.

**해결: `UInputModifierDeadZone`** — InputAction에 붙이는 Modifier

```
LowerThreshold = 0.2  → 이 값 미만은 0으로 처리
UpperThreshold = 1.0  → 이 값 초과는 1로 클램프
LowerThreshold ~ UpperThreshold 사이 → 0 ~ 1로 재매핑
```

### 데드존 타입 3종

| 타입 | 동작 | 사용 시점 |
|------|------|-----------|
| `Axial` | X축, Y축 각각 독립 적용 | 단순한 경우, UE4 호환 |
| `Radial` (Smoothed) | 두 축을 원형으로 함께 처리 + 경계 부드럽게 | 대부분의 게임, 추천 |
| `UnscaledRadial` | 원형 처리하되 경계에서 갑자기 점프 | 레트로 느낌, 특수 용도 |

**Axial의 문제점:** X와 Y를 각각 처리하면 대각선 방향에서 데드존이 마름모꼴이 된다. 스틱을 조금 기울이면 한 축은 죽고 한 축만 살아있는 현상이 생긴다.  
**Radial이 권장되는 이유:** 원형으로 처리하면 어느 방향으로 기울여도 일관된 감도가 나온다.

---

## InputModifier 체인 — 패드에 자주 쓰이는 것들

InputAction에 Modifier를 여러 개 순서대로 붙인다. 앞 Modifier의 출력이 다음 Modifier의 입력이 된다.

| Modifier | 역할 | 패드 사용 예 |
|----------|------|-------------|
| `DeadZone` | 소음 제거, 재매핑 | 스틱 필수 |
| `Scalar` | 감도 배율 (축별 독립) | 스틱 감도 조정 |
| `ScaleByDeltaTime` | 값 × DeltaTime | 스틱 카메라 Rate 변환 |
| `Negate` | 축 반전 | Y축 반전 옵션 |
| `SwizzleAxis` | 축 순서 교체 | 1D 입력을 Y축으로 올릴 때 |
| `ResponseCurveExponential` | 지수 곡선 감도 | 느리게 시작 → 빠르게 끝 느낌 |
| `ResponseCurveUser` | 커스텀 커브 | 섬세한 감도 튜닝 |
| `Smooth` | 여러 프레임에 걸쳐 평균화 | 입력 떨림 제거 |
| `FOVScaling` | 줌 배율에 따라 감도 조정 | 조준 시 감도 자동 감소 |

### 실제 Lyra 패턴 — 마우스 vs 스틱

```cpp
// 마우스: 델타 그대로 → Modifier 없음 (OS가 이미 델타 처리)
void Input_LookMouse(const FInputActionValue& Value)
{
    Pawn->AddControllerYawInput(Value.Get<FVector2D>().X);
}

// 스틱: 기울기(-1~1) × Rate × DeltaSeconds → Rate 변환
void Input_LookStick(const FInputActionValue& Value)
{
    Pawn->AddControllerYawInput(Value.X * 300.0f * World->GetDeltaSeconds());
}
```

마우스는 이미 OS 레벨에서 이동량(델타)을 주기 때문에 DeltaSeconds가 필요 없다.  
스틱은 "지금 얼마나 기울어져 있나"이므로, 시간을 곱해야 프레임 독립적인 회전이 된다.

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

## 모션 입력 (자이로스코프) — 플스 패드의 특수 기능

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

## 터치패드 (PlayStation 전용)

DualShock 4/DualSense의 터치패드는 별도 FKey로 제공된다.

| FKey | 의미 |
|------|------|
| `Gamepad_Special_Left` | 터치패드 클릭 (버튼) |
| `Gamepad_Special_Left_X` | 터치패드 X 위치 (0 ~ 1) |
| `Gamepad_Special_Left_Y` | 터치패드 Y 위치 (0 ~ 1) |
| `Gamepad_Special_Left_Touched` | 클릭 없이 터치만 |

Xbox의 `View` 버튼이 `Gamepad_Special_Left`에 매핑되기도 한다. 두 패드를 동시 지원할 때 주의.

---

## 어댑티브 트리거 (PS5 DualSense 전용)

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
