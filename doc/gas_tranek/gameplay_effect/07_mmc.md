# Modifier Magnitude Calculation

> **GASDoc**: 4.5.11 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-mmc"></a>
#### MMC(ModifierMagnitudeCalculation)란 무엇이며, ExecCalc와 비교해 어떤 장단점이 있는가?

MMC는 GE Modifier의 크기(float)를 동적으로 계산하는 클래스다. `CalculateBaseMagnitude_Implementation()`을 오버라이드해 float 하나를 반환하는 것이 유일한 목적이다. ExecCalc와 달리 **예측이 가능**하다는 것이 핵심 장점이다.

| | MMC | ExecCalc |
|---|---|---|
| 반환 | float 하나 (Modifier 하나) | 여러 Modifier 출력 가능 |
| 예측 | 가능 — 클라/서버 둘 다 실행 | 불가 — 서버만 실행 |
| Target ASC 직접 접근 | X | O |
| 서버 전용 시스템 호출 | 위험 (클라에서 null 가능) | 안전 |
| Duration/Infinite GE | 사용 가능 | 사용 불가 (Instant/Periodic만) |

MMC에서 Attribute를 캡처할 때 주의: 캡처는 ASC에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산하지만, `PreAttributeChange()`는 실행되지 않으므로 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

| Snapshot 여부 | Source/Target | 캡처 시점 | Attribute 변경 시 자동 업데이트 |
| --- | --- | --- | --- |
| Yes | Source | Spec 생성 시 | No |
| Yes | Target | Spec 적용 시 | No |
| No | Source | Spec 적용 시 | Yes |
| No | Target | Spec 적용 시 | Yes |

**MMC 구현 예시** — Target의 마나 비율과 태그에 따라 독 감소량을 계산:

```c++
UPAMMC_PoisonMana::UPAMMC_PoisonMana()
{
    ManaDef.AttributeToCapture = UPAAttributeSetBase::GetManaAttribute();
    ManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
    ManaDef.bSnapshot = false;

    MaxManaDef.AttributeToCapture = UPAAttributeSetBase::GetMaxManaAttribute();
    MaxManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
    MaxManaDef.bSnapshot = false;

    RelevantAttributesToCapture.Add(ManaDef);
    RelevantAttributesToCapture.Add(MaxManaDef);
}

float UPAMMC_PoisonMana::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec& Spec) const
{
    const FGameplayTagContainer* SourceTags = Spec.CapturedSourceTags.GetAggregatedTags();
    const FGameplayTagContainer* TargetTags = Spec.CapturedTargetTags.GetAggregatedTags();

    FAggregatorEvaluateParameters EvaluationParameters;
    EvaluationParameters.SourceTags = SourceTags;
    EvaluationParameters.TargetTags = TargetTags;

    float Mana = 0.f;
    GetCapturedAttributeMagnitude(ManaDef, Spec, EvaluationParameters, Mana);
    Mana = FMath::Max<float>(Mana, 0.0f);

    float MaxMana = 0.f;
    GetCapturedAttributeMagnitude(MaxManaDef, Spec, EvaluationParameters, MaxMana);
    MaxMana = FMath::Max<float>(MaxMana, 1.0f);

    float Reduction = -20.0f;
    if (Mana / MaxMana > 0.5f)
        Reduction *= 2;
    if (TargetTags->HasTagExact(FGameplayTag::RequestGameplayTag(FName("Status.WeakToPoisonMana"))))
        Reduction *= 2;

    return Reduction;
}
```

> 생성자에서 `RelevantAttributesToCapture`에 추가하지 않으면 캡처 시 Spec 누락 오류가 발생한다.

---

### Lyra가 데미지/힐링 계산에 MMC 대신 ExecCalc를 선택한 세 가지 이유는 무엇인가?

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

Lyra C++ 코드베이스에 `UGameplayModMagnitudeCalculation` 서브클래스가 없다. 데미지와 힐링 모두 ExecCalc로 구현됐다.

1. **Target ASC가 필요하다** — MMC는 `const FGameplayEffectSpec&`만 받는다. Target ASC는 Spec에 없다. ExecCalc는 `ExecutionParams.GetTargetAbilitySystemComponent()`로 직접 받는다.

2. **서버 전용 코드** — MMC는 클라이언트에서도 실행된다. `ULyraTeamSubsystem`처럼 서버에만 존재하는 시스템을 MMC에서 호출하면 클라이언트에서 null이 된다. ExecCalc는 서버만 실행하므로 안전하다.

3. **예측이 불필요하다** — 데미지는 서버 권한으로만 처리한다. MMC의 예측 가능 특성이 오히려 불필요한 클라이언트 실행을 유발한다.

---

### MMC/ExecCalc에서 Attribute 캡처 정의를 static 싱글톤으로 만드는 이유는 무엇인가?

> 소스: `LyraDamageExecution.cpp:14`, `LyraHealExecution.cpp:11`

```cpp
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            true  // bSnapshot: Spec 생성 시점(발사 시점) 고정
        );
    }
};

static FDamageStatics& DamageStatics()
{
    static FDamageStatics Statics;  // 프로세스 전체에서 단 한 번만 생성
    return Statics;
}
```

`FGameplayEffectAttributeCaptureDefinition`은 생성 비용이 있는데 모든 데미지 적용마다 새로 만드는 건 낭비다. static 지역변수로 한 번만 만들고 계속 재사용한다. 생성자에서 `RelevantAttributesToCapture`에 등록하는 것도 필수다.

---

### MMC와 ExecCalc는 "Modifier를 채우는가" vs "만드는가" 관점에서 어떻게 다르며, 각각 언제 써야 하는가?

**MMC**: GE Blueprint에 이미 선언된 Modifier 항목의 크기(얼마나)만 결정한다. 누구에게·어떤 연산으로는 GE가 고정한다.

**ExecCalc**: Modifier 항목 자체를 코드에서 생성한다. 누구에게·어떤 연산으로·얼마나 전부 자유롭게 결정하고, `AddOutputModifier`를 여러 번 호출해 여러 Attribute를 동시에 수정할 수 있다.

**MMC가 적합한 경우**: 예측이 필요한 버프/디버프, 단일 Attribute를 다른 Attribute 값으로 동적 계산 (예: "MaxHealth의 10%만큼 방어막"), 클라이언트에서도 안전하게 실행 가능한 계산.

**ExecCalc가 적합한 경우**: 서버 권한 계산(데미지, 힐링), 여러 Attribute 동시 수정, Target ASC 직접 접근이 필요한 경우, 서버 전용 시스템(팀 판별 등) 호출이 필요한 경우.
