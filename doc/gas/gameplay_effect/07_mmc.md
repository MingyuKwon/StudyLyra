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
