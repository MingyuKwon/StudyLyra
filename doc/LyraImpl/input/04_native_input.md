# Native 입력 경로

> 출처: `Character/LyraHeroComponent.cpp:374-468`

---

## 개요

Native 입력은 GA를 거치지 않고 **C++ 콜백이 직접 Pawn에 명령을 내리는** 경로다.  
Enhanced Input의 `ETriggerEvent::Triggered` 이벤트 발생 시 즉시 콜백이 호출된다.

---

## 이동 — Input_Move

```cpp
void ULyraHeroComponent::Input_Move(const FInputActionValue& InputActionValue)
{
    // AutoRun 중 이동 입력이 들어오면 AutoRun 해제
    if (ALyraPlayerController* LyraController = Cast<ALyraPlayerController>(Controller))
        LyraController->SetIsAutoRunning(false);

    const FVector2D Value = InputActionValue.Get<FVector2D>();
    const FRotator MovementRotation(0.0f, Controller->GetControlRotation().Yaw, 0.0f);

    // X = 좌우(Strafe), Y = 전후
    if (Value.X != 0.0f)
    {
        const FVector MovementDirection = MovementRotation.RotateVector(FVector::RightVector);
        Pawn->AddMovementInput(MovementDirection, Value.X);
    }
    if (Value.Y != 0.0f)
    {
        const FVector MovementDirection = MovementRotation.RotateVector(FVector::ForwardVector);
        Pawn->AddMovementInput(MovementDirection, Value.Y);
    }
}
```

컨트롤러의 Yaw를 기준으로 이동 방향을 계산해 `AddMovementInput`에 전달.  
방향 계산에 Pitch와 Roll은 제외 — 경사면에서도 수평 방향 이동을 보장.

---

## 마우스 시점 — Input_LookMouse

```cpp
void ULyraHeroComponent::Input_LookMouse(const FInputActionValue& InputActionValue)
{
    const FVector2D Value = InputActionValue.Get<FVector2D>();
    if (Value.X != 0.0f) Pawn->AddControllerYawInput(Value.X);
    if (Value.Y != 0.0f) Pawn->AddControllerPitchInput(Value.Y);
}
```

마우스 델타값을 그대로 전달. 감도 스케일은 Enhanced Input의 `InputModifier`나 `LyraAimSensitivityData`에서 처리.

---

## 스틱 시점 — Input_LookStick

```cpp
// LyraHeroComponent.cpp 상단
namespace LyraHero
{
    static const float LookYawRate = 300.0f;    // deg/sec
    static const float LookPitchRate = 165.0f;  // deg/sec
};

void ULyraHeroComponent::Input_LookStick(const FInputActionValue& InputActionValue)
{
    const FVector2D Value = InputActionValue.Get<FVector2D>();
    if (Value.X != 0.0f)
        Pawn->AddControllerYawInput(Value.X * LyraHero::LookYawRate * World->GetDeltaSeconds());
    if (Value.Y != 0.0f)
        Pawn->AddControllerPitchInput(Value.Y * LyraHero::LookPitchRate * World->GetDeltaSeconds());
}
```

마우스와의 차이: **DeltaSeconds를 곱해 프레임 독립적인 회전속도(deg/sec)로 변환**.  
스틱은 절대 위치가 아니라 기울기 비율(-1~1)을 반환하므로 필요한 처리.

---

## 웅크리기 — Input_Crouch

```cpp
void ULyraHeroComponent::Input_Crouch(const FInputActionValue& InputActionValue)
{
    if (ALyraCharacter* Character = GetPawn<ALyraCharacter>())
        Character->ToggleCrouch();  // 토글 방식
}
```

Hold가 아닌 **토글** 방식. `ToggleCrouch()`는 `ALyraCharacter`에 구현.

---

## 자동 달리기 — Input_AutoRun

```cpp
void ULyraHeroComponent::Input_AutoRun(const FInputActionValue& InputActionValue)
{
    if (ALyraPlayerController* Controller = ...)
        Controller->SetIsAutoRunning(!Controller->GetIsAutoRunning());  // 토글
}
```

`SetIsAutoRunning` / `GetIsAutoRunning`은 `ALyraPlayerController`에서 관리.  
이동 입력이 들어오면 `Input_Move`에서 AutoRun을 해제한다 (상호 연동).

---

## Native vs Ability 입력 비교

| 항목 | Native | Ability |
|------|--------|---------|
| 처리 시점 | Enhanced Input 이벤트 즉시 | 매 틱 ProcessAbilityInput |
| 처리 주체 | HeroComponent 콜백 | LyraASC |
| 취소/차단 | 불가 (항상 실행) | TAG_Gameplay_AbilityInputBlocked로 차단 가능 |
| 네트워크 예측 | CharacterMovement가 처리 | GAS Prediction Key 사용 |
| 용도 | 이동, 시점, 기본 조작 | 스킬, 공격 등 GA 기반 능력 |
