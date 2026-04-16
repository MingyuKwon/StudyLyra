# Modifier & ModifierMagnitudeCalculation (MMC)

> 참고: [GAS Doc 캐시](../cache/gas_doc_cache.md)

---

## 4가지 Modifier Operation

| Op | 연산 | 설명 |
|---|---|---|
| `Additive` | `CurrentValue += Magnitude` | 덧셈 |
| `Multiplicative` | `CurrentValue *= (1 + sum of (m-1))` | 곱셈 (Aggregator 내부: 덧셈 기반) |
| `Division` | `CurrentValue /= Magnitude` | 나눗셈 |
| `Override` | `CurrentValue = 마지막 Override 값` | 강제 덮어쓰기 |

### Multiplicative 내부 동작

```
Modifier A: Multiplicative, Magnitude = 1.5 (50% 증가)
Modifier B: Multiplicative, Magnitude = 1.2 (20% 증가)

실제 계산: BaseValue * (1 + (1.5-1) + (1.2-1)) = BaseValue * 1.7
(단순 곱셈이 아닌 덧셈 기반이므로 순서 무관)
```

---

## Magnitude 설정 방식

| 방식 | 설명 |
|---|---|
| `Scalable Float` | 에디터에서 직접 입력한 값 (레벨 커브 적용 가능) |
| `Attribute Based` | 다른 Attribute 값에 비례 |
| `Custom Calculation Class (MMC)` | C++ 클래스로 계산 |
| `Set By Caller` | 런타임에 GA에서 주입 |

---

## ModifierMagnitudeCalculation (MMC)

복잡한 계산 로직을 C++ 클래스로 분리하는 방법.

### MMC vs ExecCalc

| | MMC | ExecCalc |
|---|---|---|
| 쓰기 대상 | Modifier 1개 | 여러 Attribute |
| 예측 | 가능 | 불가 (서버 전용) |
| 재계산 | Non-snapshot 시 자동 | 없음 |
| 클래스 | `UGameplayModMagnitudeCalculation` | `UGameplayEffectExecutionCalculation` |

### MMC 구조

```cpp
UCLASS()
class UMyMMC : public UGameplayModMagnitudeCalculation
{
    GENERATED_BODY()

    // 생성자에서 캡처할 Attribute 등록
    UMyMMC()
    {
        StrengthDef = FGameplayEffectAttributeCaptureDefinition(
            UMyAttributeSet::GetStrengthAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            false  // Non-snapshot: 매번 현재 값
        );
        RelevantAttributesToCapture.Add(StrengthDef);
    }

    // 계산 구현
    float CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec& Spec) const override
    {
        const FGameplayTagContainer* SourceTags = Spec.CapturedSourceTags.GetAggregatedTags();
        const FGameplayTagContainer* TargetTags = Spec.CapturedTargetTags.GetAggregatedTags();
        
        FAggregatorEvaluateParameters EvalParams;
        EvalParams.SourceTags = SourceTags;
        EvalParams.TargetTags = TargetTags;
        
        float Strength = 0.0f;
        GetCapturedAttributeMagnitude(StrengthDef, Spec, EvalParams, Strength);
        
        return Strength * 1.5f;  // 예: 힘의 1.5배를 Magnitude로 반환
    }

    FGameplayEffectAttributeCaptureDefinition StrengthDef;
};
```

### Non-snapshot 자동 재계산

Duration/Infinite GE + Non-snapshot MMC 조합:
- 참조하는 Attribute가 변하면 MMC가 자동으로 재계산됨
- 예: MaxHealth가 증가하면 체력 재생 속도도 자동 증가

---

## Aggregator와 MostNegativeMod

`OnAttributeAggregatorCreated` 콜백에서 평가 메타데이터를 설정할 수 있다.

```cpp
void UMyAttributeSet::OnAttributeAggregatorCreated(
    const FGameplayAttribute& Attribute,
    FAggregator* NewAggregator) const
{
    if (Attribute == GetMoveSpeedAttribute())
    {
        // "가장 강한 디버프만 적용, 버프는 모두 적용" 패턴
        // Paragon 둔화 스택 구현에 사용
        NewAggregator->EvaluationMetaData =
            &FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods;
    }
}
```

`MostNegativeMod_AllPositiveMods`:
- 네거티브 Modifier 중 가장 강한 것만 적용
- 포지티브 Modifier는 모두 적용
- 결과: 여러 둔화가 중첩되지 않고 가장 강한 것만 적용됨
