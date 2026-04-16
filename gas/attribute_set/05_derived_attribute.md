# 파생 Attribute (Derived Attribute)

GAS는 "다른 Attribute 값을 바라보며 자동으로 갱신되는" 파생 Attribute를 세 가지 방식으로 구현한다.
진정한 의미의 자동 연동은 **방법 1(AttributeBased GE)** 만이고,
나머지는 코드로 수동 연동하는 패턴이다.

---

## 방법 1. AttributeBased GE Modifier — 살아있는 자동 연동

GE의 Modifier Magnitude 타입을 `AttributeBased`로 설정하면,
지정한 Backing Attribute의 현재값을 기반으로 Modifier 크기를 계산한다.

**에디터에서 설정하는 구조:**

```
GE_Modifier
  └─ MagnitudeCalculationType: AttributeBased
        └─ FAttributeBasedFloat
              ├─ BackingAttribute: Source의 Strength (캡처 대상 Attribute)
              ├─ AttributeCalculationType: AttributeMagnitude  (CurrentValue 사용)
              ├─ Coefficient: 0.5                             (최종값 = 0.5 * Strength)
              ├─ PreMultiplyAdditiveValue: 0.0
              └─ PostMultiplyAdditiveValue: 0.0
```

**수식:**
```
ModifierMagnitude = Coefficient * (PreAdd + [BackingAttribute값]) + PostAdd
```

**Duration/Infinite GE일 때 자동 갱신:**

Backing Attribute의 Aggregator가 dirty될 때마다 이 Modifier의 크기가 재계산되고,
타겟 Attribute의 CurrentValue도 자동으로 갱신된다.

```
Strength(BaseValue) = 100
  └─ GE(Infinite): AttackPower += 0.5 * Strength  →  AttackPower CurrentValue += 50

Strength가 120으로 변경됨
  └─ Strength Aggregator dirty
        └─ AttackPower Modifier 재계산: 0.5 * 120 = 60
              └─ AttackPower CurrentValue 자동 갱신
```

> **Instant GE일 때는 자동 갱신 없음.** GE 적용 시점의 Attribute 값만 스냅샷으로 찍어 사용한다.

**`EAttributeBasedFloatCalculationType` 옵션:**

| 타입 | 의미 |
|------|------|
| `AttributeMagnitude` | CurrentValue 사용 (버프 포함) |
| `AttributeBaseValue` | BaseValue만 사용 (버프 제외) |
| `AttributeBonusMagnitude` | CurrentValue - BaseValue (버프 양만) |

---

## 방법 2. PostAttributeChange 콜백 — 코드 수동 연동

AttributeSet의 `PostAttributeChange`에서 한 Attribute가 바뀌면
다른 Attribute를 직접 조정하는 패턴.

**Lyra 실제 예시: MaxHealth가 줄면 Health도 클램프**

```cpp
// LyraHealthSet.cpp
void ULyraHealthSet::PostAttributeChange(
    const FGameplayAttribute& Attribute, float OldValue, float NewValue)
{
    if (Attribute == GetMaxHealthAttribute())
    {
        // MaxHealth가 낮아져서 현재 Health가 새 MaxHealth를 초과하면 강제 클램프
        if (GetHealth() > NewValue)
        {
            // ASC를 통해 Health의 BaseValue를 직접 수정
            ULyraAbilitySystemComponent* LyraASC = GetLyraAbilitySystemComponent();
            LyraASC->ApplyModToAttribute(
                GetHealthAttribute(),
                EGameplayModOp::Override,
                NewValue   // Health = NewMaxHealth 로 덮어씀
            );
        }
    }
}
```

```
MaxHealth = 100, Health = 80

MaxHealth가 60으로 감소
  └─ PostAttributeChange 호출
        └─ Health(80) > MaxHealth(60) 감지
              └─ Health를 60으로 강제 Override
```

`PostAttributeChange`는 **CurrentValue** 변경 후 호출되고,
`PostAttributeBaseChange`는 **BaseValue** 변경 후 호출된다.

---

## 방법 3. MMC (ModMagnitudeCalculation) — 복잡한 다중 Attribute 연산

`UGameplayModMagnitudeCalculation`을 상속해 `CalculateBaseMagnitude()`를 구현하면
여러 Attribute를 동시에 참조하는 복잡한 파생 계산을 GE Modifier에 연결할 수 있다.

```cpp
// 예: MaxHealth = BaseHP + Vitality * 10 + Level * 5 구현

UCLASS()
class UMaxHealthMMC : public UGameplayModMagnitudeCalculation
{
    GENERATED_BODY()

    FGameplayEffectAttributeCaptureDefinition VitalityDef;
    FGameplayEffectAttributeCaptureDefinition LevelDef;

public:
    UMaxHealthMMC()
    {
        // 참조할 Attribute들을 캡처 목록에 등록
        VitalityDef = FGameplayEffectAttributeCaptureDefinition(
            UMyStatSet::GetVitalityAttribute(),
            EGameplayEffectAttributeCaptureSource::Target, false);
        LevelDef = FGameplayEffectAttributeCaptureDefinition(
            UMyStatSet::GetLevelAttribute(),
            EGameplayEffectAttributeCaptureSource::Target, false);

        RelevantAttributesToCapture.Add(VitalityDef);
        RelevantAttributesToCapture.Add(LevelDef);
    }

    float CalculateBaseMagnitude(const FGameplayEffectSpec& Spec) const override
    {
        FAggregatorEvaluateParameters Params;

        float Vitality = 0.f;
        GetCapturedAttributeMagnitude(VitalityDef, Spec, Params, Vitality);

        float Level = 0.f;
        GetCapturedAttributeMagnitude(LevelDef, Spec, Params, Level);

        return Vitality * 10.f + Level * 5.f;  // 이 값이 Modifier 크기가 됨
    }
};
```

GE 에디터에서 Modifier Magnitude 타입을 `CustomCalculationClass`로 설정하고
이 클래스를 지정하면 된다.

---

## 세 가지 방법 비교

| | AttributeBased GE | PostAttributeChange | MMC |
|---|---|---|---|
| 자동 갱신 | Duration/Infinite GE에서 O | 수동 호출 | Duration/Infinite GE에서 O |
| 참조 Attribute 수 | 1개 | 제한 없음 (코드) | 여러 개 |
| 설정 위치 | GE 에디터 | AttributeSet 코드 | C++ 클래스 + GE 에디터 |
| 복잡도 | 낮음 | 중간 | 높음 |
| Lyra 사용 여부 | X (직접 사용 없음) | O (`MaxHealth→Health` 클램프) | X (직접 사용 없음) |
