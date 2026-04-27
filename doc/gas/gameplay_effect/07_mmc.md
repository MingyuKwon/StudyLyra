# Modifier Magnitude Calculation

> **GASDoc**: 4.5.11 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-mmc"></a>
#### 4.5.11 Modifier Magnitude Calculation

[`ModifierMagnitudeCalculations`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayModMagnitudeCalculation/index.html)(`ModMagCalc` 또는 `MMC`)는 `GameplayEffects`에서 [`Modifiers`](#concepts-ge-mods)로 사용되는 강력한 클래스다. [`GameplayEffectExecutionCalculations`](#concepts-ge-ec)와 비슷하게 동작하지만 그보다 기능이 제한적이며, 무엇보다 중요한 장점은 [예측(predicted)](#concepts-p)이 가능하다는 것이다. MMC의 유일한 목적은 `CalculateBaseMagnitude_Implementation()`에서 float 값을 반환하는 것이다. Blueprint와 C++ 모두에서 서브클래스로 만들어 이 함수를 오버라이드할 수 있다.

`MMC`는 `Instant`, `Duration`, `Infinite`, `Periodic` 등 모든 지속 시간 유형의 `GameplayEffects`에서 사용할 수 있다.

`MMC`의 강점은 `GameplayEffect`의 Source 또는 Target에 있는 Attribute 값을 얼마든지 캡처할 수 있으며, `GameplayEffectSpec`에 완전히 접근하여 `GameplayTags`와 `SetByCallers`를 읽을 수 있다는 데 있다. `Attributes`는 스냅샷(snapshotted)으로 캡처하거나 그렇지 않게 캡처할 수 있다. 스냅샷된 `Attributes`는 `GameplayEffectSpec`이 생성될 때 캡처되는 반면, 스냅샷되지 않은 `Attributes`는 `GameplayEffectSpec`이 적용될 때 캡처되며, `Infinite`와 `Duration` `GameplayEffects`에서 `Attribute`가 변경될 때 자동으로 업데이트된다. `Attributes`를 캡처하면 `ASC`에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산한다. 이 재계산은 `AbilitySet`의 [`PreAttributeChange()`](#concepts-as-preattributechange)를 **실행하지 않으므로**, 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

| Snapshot 여부 | Source/Target | `GameplayEffectSpec` 캡처 시점 | `Infinite`/`Duration` GE에서 Attribute 변경 시 자동 업데이트 |
| ------------- | ------------- | ------------------------------ | ------------------------------------------------------------- |
| Yes           | Source        | 생성 시                        | No                                                            |
| Yes           | Target        | 적용 시                        | No                                                            |
| No            | Source        | 적용 시                        | Yes                                                           |
| No            | Target        | 적용 시                        | Yes                                                           |

`MMC`에서 반환된 float 값은 `GameplayEffect`의 `Modifier`에서 계수(coefficient)와 사전/사후 계수 가산값(pre and post coefficient addition)으로 추가 보정할 수 있다.

Target의 마나 `Attribute`를 캡처하여 독(Poison) 효과로 감소시키는 `MMC` 예시 — Target이 보유한 마나 양과 특정 태그 여부에 따라 감소량이 달라진다:
```c++
UPAMMC_PoisonMana::UPAMMC_PoisonMana()
{

	//ManaDef defined in header FGameplayEffectAttributeCaptureDefinition ManaDef;
	ManaDef.AttributeToCapture = UPAAttributeSetBase::GetManaAttribute();
	ManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
	ManaDef.bSnapshot = false;

	//MaxManaDef defined in header FGameplayEffectAttributeCaptureDefinition MaxManaDef;
	MaxManaDef.AttributeToCapture = UPAAttributeSetBase::GetMaxManaAttribute();
	MaxManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
	MaxManaDef.bSnapshot = false;

	RelevantAttributesToCapture.Add(ManaDef);
	RelevantAttributesToCapture.Add(MaxManaDef);
}

float UPAMMC_PoisonMana::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec & Spec) const
{
	// Gather the tags from the source and target as that can affect which buffs should be used
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
	MaxMana = FMath::Max<float>(MaxMana, 1.0f); // Avoid divide by zero

	float Reduction = -20.0f;
	if (Mana / MaxMana > 0.5f)
	{
		// Double the effect if the target has more than half their mana
		Reduction *= 2;
	}
	
	if (TargetTags->HasTagExact(FGameplayTag::RequestGameplayTag(FName("Status.WeakToPoisonMana"))))
	{
		// Double the effect if the target is weak to PoisonMana
		Reduction *= 2;
	}
	
	return Reduction;
}
```

`MMC` 생성자에서 `FGameplayEffectAttributeCaptureDefinition`을 `RelevantAttributesToCapture`에 추가하지 않은 채로 `Attributes`를 캡처하려 하면, 캡처 시 Spec 누락 오류가 발생한다. `Attributes`를 캡처할 필요가 없다면 `RelevantAttributesToCapture`에 아무것도 추가하지 않아도 된다.

---

## 내 분석

### Lyra는 MMC를 쓰지 않는다 — ExecCalc를 선택한 이유

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

Lyra C++ 코드베이스에 `UGameplayModMagnitudeCalculation` 서브클래스가 없다. 데미지와 힐링 계산 모두 `UGameplayEffectExecutionCalculation`(ExecCalc)으로 구현됐다. 이 선택이 MMC와 ExecCalc의 차이를 이해하는 핵심이다.

**MMC의 역할**: GE의 Modifier 하나에 대해 float 값 하나를 반환한다. 단일 Attribute 하나를 조작하는 계산에 적합하다.

**ExecCalc의 역할**: 여러 Attribute를 한 번에 조작하고, 출력도 여러 개(`OutExecutionOutput.AddOutputModifier`)를 낼 수 있다.

Lyra의 데미지 계산이 ExecCalc여야 하는 이유:

```cpp
// LyraDamageExecution.cpp:131
const float DamageDone = FMath::Max(
    BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier, 0.0f);

OutExecutionOutput.AddOutputModifier(
    FGameplayModifierEvaluatedData(ULyraHealthSet::GetDamageAttribute(), EGameplayModOp::Additive, DamageDone));
```

1. **Context 접근이 필요하다** — 거리, HitResult, 물리 재질, 팀 판별 등을 `FLyraGameplayEffectContext`에서 꺼낸다. MMC는 Spec에만 접근할 수 있고 ExecutionParams를 받지 않는다.
2. **서버 전용 코드** — `#if WITH_SERVER_CODE`로 감싸져 있다. 데미지 계산은 예측이 필요 없고 서버 권한으로만 돌린다. MMC는 예측 가능하지만 그 장점이 여기선 불필요하다.
3. **팀 판별** — `ULyraTeamSubsystem::CanCauseDamage()`를 호출해서 아군 피해를 차단한다. 이런 외부 시스템 접근은 ExecCalc에서만 가능하다.

---

### Attribute 캡처 패턴 — static 싱글톤으로 정의

> 소스: `LyraDamageExecution.cpp:14`, `LyraHealExecution.cpp:11`

MMC든 ExecCalc든 Attribute 캡처 정의 방식은 동일하다. Lyra의 패턴:

```cpp
// LyraDamageExecution.cpp:14
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        // Source의 BaseDamage를, Snapshot=true로 캡처
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

`static` 지역변수로 만든 이유: `FGameplayEffectAttributeCaptureDefinition`은 생성 비용이 있는데, 모든 데미지 적용마다 새로 만드는 건 낭비다. 한 번만 만들고 계속 재사용한다. MMC 예시 코드에서도 동일한 패턴을 권장한다.

생성자에서 `RelevantAttributesToCapture`에 등록하는 것도 필수다:

```cpp
// LyraDamageExecution.cpp:31
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

이 등록이 없으면 `AttemptCalculateCapturedAttributeMagnitude` 호출 시 "Spec에 캡처 정의가 없다"는 오류가 난다. MMC에서 `GetCapturedAttributeMagnitude`를 쓸 때도 동일하다.

---

### MMC vs ExecCalc — 언제 무엇을 쓰나

> 소스: `GameplayEffect.h`, `GameplayEffectExecutionCalculation.h`

두 클래스의 핵심 차이:

| | MMC | ExecCalc |
|---|---|---|
| 반환 | float 하나 (Modifier 하나) | 여러 Modifier 출력 가능 |
| 예측 | 가능 | 불가능 |
| Context 접근 | Spec 통해 간접 접근 | `ExecutionParams`로 직접 접근 |
| 외부 시스템 접근 | 제한적 | 자유로움 |
| 용도 | "이 Modifier의 크기를 동적으로 계산" | "이 GE가 발생시키는 모든 결과를 계산" |

**MMC가 적합한 경우**: 예측이 필요한 클라이언트 사이드 효과, 단일 Attribute를 조작하는 버프/디버프, 다른 Attribute에서 값을 읽어 Modifier를 결정하는 경우 (예: "MaxHealth의 10%만큼 방어막 부여").

**ExecCalc가 적합한 경우**: 서버 권한 계산(데미지, 힐링), 여러 Attribute를 동시에 수정, Context의 HitResult·거리·팀 정보 등 외부 데이터가 필요한 계산.

Lyra의 데미지 파이프라인은 예측 없이 서버 권한으로 처리하고 복잡한 외부 정보가 필요하기 때문에 ExecCalc가 올바른 선택이다.
