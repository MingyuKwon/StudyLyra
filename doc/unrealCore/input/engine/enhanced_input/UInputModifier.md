# UInputModifier

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputModifiers.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/InputModifiers.cpp`

---

## 무엇인가

**입력값을 변환하는 오브젝트**다. 물리 키에서 읽은 원시값(RawValue)을 게임 로직에 맞는 값으로 바꾸는 역할을 한다.

- 데드존 처리
- 스케일·부호 변환
- 축 순서 변경
- 감도 곡선 적용

이런 처리를 코드 없이 에셋에서 설정할 수 있게 해준다.

---

## 클래스 위치

```
UObject → UInputModifier (abstract, EditInlineNew)
```

abstract이므로 직접 인스턴스화하지 않는다. `EditInlineNew`이므로 IMC 에셋이나 IA 에셋에서 인라인으로 생성·편집 가능하다.

---

## 인터페이스 — ModifyRaw

```cpp
virtual FInputActionValue ModifyRaw_Implementation(
    const UEnhancedPlayerInput* PlayerInput,  // 현재 PlayerInput (다른 키 상태 참조 가능)
    FInputActionValue CurrentValue,           // 이전 Modifier가 반환한 값 (체인 입력)
    float DeltaTime                           // 이번 틱 경과 시간
);
```

배열 순서대로 체인 실행된다. 첫 번째 Modifier의 입력은 RawKeyValue, 이후 Modifier들은 앞 Modifier의 반환값을 입력으로 받는다.

**타입 고정**: 각 Modifier가 반환한 값의 타입이 무엇이든, 최종적으로 **원본 RawValue의 ValueType으로 강제 복원**된다. Modifier 내부에서 타입을 바꿀 수 없다.

```cpp
// ApplyModifiers 내부 (EnhancedPlayerInput.cpp)
ModifiedValue = FInputActionValue(
    RawValue.GetValueType(),          // ← 항상 원본 타입으로 강제
    Modifier->ModifyRaw(...).Get<FVector>()
);
```

---

## 두 레벨

Modifier는 두 곳에 정의할 수 있고, 항상 이 순서로 적용된다.

```
1. Mapping 레벨 (FEnhancedActionKeyMapping.Modifiers)
       → 각 키 매핑에 붙임. ProcessActionMappingEvent 내부에서 값 누적 전 적용
       → 키별로 다른 변환이 필요할 때 사용

2. Action 레벨 (UInputAction.Modifiers)
       → IA 에셋에 붙임. 모든 키 값이 누적된 후 한 번 적용
       → 키 종류와 무관하게 공통으로 적용할 변환
```

---

## 내장 Modifier 목록

### DeadZone
아날로그 스틱의 미세한 떨림(드리프트)을 제거한다. 임계값 이하 입력을 0으로 처리하고, 이상이면 0~1로 정규화한다.

- `LowerThreshold` — 이 이하는 0으로 처리 (기본 0.2)
- `UpperThreshold` — 이 이상은 1.0으로 처리 (기본 1.0)
- `Type`:
  - `Axial` — X, Y 축 각각 독립적으로 처리. 코너에서 값이 잘릴 수 있음
  - `Radial` — 벡터 전체 크기로 판단. 원형 데드존. 자연스러운 스틱 감도

### Negate
입력값의 부호를 반전한다(`value * -1`).

- WASD에서 S키를 "후진(-)"으로 만들 때
- 마우스 Y축 반전 옵션 구현 시

### Scalar
입력값에 스칼라를 곱한다. 감도 조절에 사용.

```cpp
FVector ScaleVector = FVector(1.f, 1.f, 1.f);  // 축별 배율
```

### SwizzleInputAxisValues
축 순서를 변경한다. WASD를 2D 이동으로 바꿀 때 필수.

```
기본 키 값: (1, 0, 0) — X축에 담긴 값
SwizzleAxis(YXZ) 적용 후: (0, 1, 0) — W키를 Y축(전진)으로 변환
```

| Order | 결과 |
|---|---|
| `XYZ` | 변환 없음 |
| `YXZ` | X↔Y 교환. W키 전진에 사용 |
| `ZYX` | X↔Z 교환 |

### Normalize
입력값을 단위 벡터(크기 1)로 정규화한다. 대각 이동 시 속도가 빨라지는 문제 방지.

### SmoothDelta
현재 틱과 이전 틱 값의 차이를 평활화한다. 급격한 입력 변화를 부드럽게 만든다.

- `SmoothingMethod` — Lerp, Interp_To, Interp_Circular 등 다양한 보간 방식

### ResponseCurveExponential
지수 응답 곡선을 적용한다. 스틱의 미세 조작 영역을 더 세밀하게, 큰 입력은 더 빠르게.

### ResponseCurveUser
에디터에서 편집 가능한 커스텀 커브 에셋으로 응답 곡선을 정의한다.

### FOVScaling
현재 카메라 FOV에 비례해서 입력값을 보정한다. 줌 인 시 마우스 감도를 자동으로 낮춘다.

### ToWorldSpace
카메라 방향을 기준으로 입력값을 월드 공간 벡터로 변환한다.

### Collection
다른 Modifier 목록을 하나의 Modifier로 묶어 재사용 가능한 그룹으로 만든다.

---

## 커스텀 Modifier 작성

```cpp
UCLASS(EditInlineNew, BlueprintType, meta=(DisplayName="My Modifier"))
class UMyInputModifier : public UInputModifier
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category="Settings")
    float Multiplier = 1.0f;

protected:
    virtual FInputActionValue ModifyRaw_Implementation(
        const UEnhancedPlayerInput* PlayerInput,
        FInputActionValue CurrentValue,
        float DeltaTime) override
    {
        FVector V = CurrentValue.Get<FVector>();
        V *= Multiplier;
        return FInputActionValue(CurrentValue.GetValueType(), V);
    }
};
```

---

## WASD 이동 Modifier 패턴

```
IA_Move (Axis2D)에 대한 각 키 매핑:

W키:  SwizzleAxis(YXZ) → (0, 1, 0)  전진
S키:  Negate, SwizzleAxis(YXZ) → (0, -1, 0)  후진
D키:  없음 → (1, 0, 0)  오른쪽
A키:  Negate → (-1, 0, 0)  왼쪽
```

`AccumulationBehavior = Cumulative`이면 W+S 동시 입력 시 합산되어 0이 된다(상쇄).

---

## 요약

```
UInputModifier = 입력값 변환기
  ModifyRaw_Implementation()  ← 오버라이드 포인트
  배열 순서대로 체인 실행
  반환 타입은 항상 원본 ValueType으로 고정
  
두 레벨:
  Mapping 레벨 → 키별 변환 (SwizzleAxis, Negate 등)
  Action 레벨  → 공통 변환 (전체 누적 후 1회)
```
