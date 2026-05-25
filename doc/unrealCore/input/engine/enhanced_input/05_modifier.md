# Modifier 체인

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputModifiers.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/InputModifiers.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

---

## 두 레벨 적용 순서

Modifier는 두 곳에 정의할 수 있고 항상 이 순서로 적용된다.

```
1. Mapping 레벨  (IMC 에셋의 키 매핑에 붙은 Modifier)
       ApplyModifiers(Mapping.Modifiers, RawKeyValue, DeltaTime)

2. Action 레벨  (InputAction 에셋에 붙은 Modifier)
       ApplyModifiers(ActionData.Modifiers, AccumulatedValue, DeltaTime)
```

Mapping 레벨은 `ProcessActionMappingEvent` 내부(값 누적 전), Action 레벨은 Post-tick(모든 키 누적 후)에 실행된다.

---

## ApplyModifiers 구현

```cpp
FInputActionValue UEnhancedPlayerInput::ApplyModifiers(
    const TArray<UInputModifier*>& Modifiers,
    FInputActionValue RawValue,
    float DeltaTime) const
{
    FInputActionValue ModifiedValue = RawValue;
    for (UInputModifier* Modifier : Modifiers)
    {
        if (Modifier)
        {
            // 반환값 타입은 항상 원본 ValueType으로 강제 복원
            ModifiedValue = FInputActionValue(
                RawValue.GetValueType(),
                Modifier->ModifyRaw(this, ModifiedValue, DeltaTime).Get<FVector>()
            );
        }
    }
    return ModifiedValue;
}
```

핵심: 각 Modifier가 반환한 값의 타입이 무엇이든, `ValueType`은 항상 원본 `RawValue`의 타입으로 고정된다. Modifier 내부에서 타입을 바꿀 수 없다.

---

## UInputModifier 기반 클래스

```cpp
class UInputModifier : public UObject
{
    virtual FInputActionValue ModifyRaw_Implementation(
        const UEnhancedPlayerInput* PlayerInput,
        FInputActionValue CurrentValue,
        float DeltaTime);
};
```

- `CurrentValue` = 이전 Modifier가 반환한 값 (체인의 첫 번째면 RawKeyValue)
- 배열 순서대로 실행. 순서가 결과에 영향을 준다.
- `BlueprintNativeEvent` — C++은 `_Implementation`을 오버라이드, Blueprint는 Event 노드 구현

---

## 내장 Modifier 목록

| 클래스 | 동작 |
|---|---|
| **DeadZone** | 임계값 이하 입력 무시, 이상이면 0~1로 정규화. `Axial`(축별) / `Radial`(원형) 두 방식 |
| **Negate** | 값 부호 반전. 스틱 Y축 반전, "S키를 -1로" 패턴에 사용 |
| **Scalar** | 스칼라 곱. 감도 조절 |
| **ScalarByValue** | 입력값 크기에 비례한 스칼라 곱 |
| **SwizzleInputAxisValues** | 축 순서 변경 (X→Y, Y→X 등). WASD를 XY 평면 이동으로 변환할 때 |
| **Normalize** | 값을 단위 벡터로 정규화 |
| **SmoothDelta** | 이전 틱과 현재 틱 값의 차이를 평활화 (Lerp, Interp_To 등 여러 방식) |
| **ResponseCurveExponential** | 지수 응답 곡선 적용. 아날로그 스틱 비선형 감도 |
| **ResponseCurveUser** | 커스텀 커브 에셋으로 응답 곡선 적용 |
| **FOVScaling** | FOV에 비례해 값 보정. 줌 인 시 마우스 감도 낮추기 |
| **ToWorldSpace** | 카메라 방향 기준 월드 공간 벡터로 변환 |
| **Collection** | 다른 Modifier 목록을 그룹으로 묶어 재사용 |

---

## WASD 이동 Modifier 패턴

WASD 4키를 `IA_Move`(Axis2D) 하나에 매핑하는 전형적인 패턴이다.

```
W키 Mapping:
    Modifier없음 → (1, 0, 0) → SwizzleInputAxisValues(YXZ) → (0, 1, 0) [전진]

S키 Mapping:
    Negate       → (-1, 0, 0)
    SwizzleInputAxisValues(YXZ) → (0, -1, 0) [후진]

D키 Mapping:
    Modifier없음 → (1, 0, 0) [오른쪽]

A키 Mapping:
    Negate       → (-1, 0, 0) [왼쪽]
```

AccumulationBehavior = `Cumulative`로 설정하면 W+S 동시 입력 시 서로 상쇄된다.

---

## 커스텀 Modifier 작성

```cpp
UCLASS()
class UMyInputModifier : public UInputModifier
{
    GENERATED_BODY()
protected:
    virtual FInputActionValue ModifyRaw_Implementation(
        const UEnhancedPlayerInput* PlayerInput,
        FInputActionValue CurrentValue,
        float DeltaTime) override
    {
        // CurrentValue를 받아서 변환 후 반환
        FVector V = CurrentValue.Get<FVector>();
        V *= 2.0f;
        return FInputActionValue(CurrentValue.GetValueType(), V);
    }
};
```

`EditInlineNew`, `BlueprintType`으로 마크하면 에셋에서 인라인 생성 가능.
