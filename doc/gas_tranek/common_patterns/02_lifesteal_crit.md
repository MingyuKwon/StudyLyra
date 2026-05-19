# Lifesteal & 치명타 구현

> **GASDoc**: 5.4 / 5.6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-ls"></a>
### 5.4 Lifesteal

Lifesteal은 데미지 ExecutionCalculation 내부에서 처리한다. GameplayEffect에는 `Effect.CanLifesteal`과 같은 GameplayTag가 부여된다. ExecutionCalculation은 GameplayEffectSpec에 해당 GameplayTag가 있는지 확인하고, 존재할 경우 회복할 체력량을 Modifier로 갖는 동적 Instant GameplayEffect를 생성하여 Source의 ASC에 적용한다.

```c++
if (SpecAssetTags.HasTag(FGameplayTag::RequestGameplayTag(FName("Effect.Damage.CanLifesteal"))))
{
	float Lifesteal = Damage * LifestealPercent;

	UGameplayEffect* GELifesteal = NewObject<UGameplayEffect>(GetTransientPackage(), FName(TEXT("Lifesteal")));
	GELifesteal->DurationPolicy = EGameplayEffectDurationType::Instant;

	int32 Idx = GELifesteal->Modifiers.Num();
	GELifesteal->Modifiers.SetNum(Idx + 1);
	FGameplayModifierInfo& Info = GELifesteal->Modifiers[Idx];
	Info.ModifierMagnitude = FScalableFloat(Lifesteal);
	Info.ModifierOp = EGameplayModOp::Additive;
	Info.Attribute = UPAAttributeSetBase::GetHealthAttribute();

	SourceAbilitySystemComponent->ApplyGameplayEffectToSelf(GELifesteal, 1.0f, SourceAbilitySystemComponent->MakeEffectContext());
}
```

<a name="cae-crit"></a>
### 5.6 Critical Hits (치명타)

치명타는 데미지 ExecutionCalculation 내부에서 처리한다. GameplayEffect에는 `Effect.CanCrit`과 같은 GameplayTag가 부여된다. ExecutionCalculation은 GameplayEffectSpec에 해당 GameplayTag가 있는지 확인하고, 존재할 경우 Source로부터 치명타 확률 Attribute를 캡처하여 난수와 비교해 치명타 성공 여부를 판정한다. 치명타가 성공하면 역시 Source에서 캡처한 치명타 데미지 Attribute를 추가로 적용한다. 데미지를 예측(predict)하지 않으므로 클라이언트와 서버 사이의 난수 생성기 동기화를 걱정할 필요가 없다. ExecutionCalculation은 서버에서만 실행되기 때문이다. 만약 MMC를 사용해 예측 방식으로 데미지를 계산하고자 한다면, `GameplayEffectSpec->GameplayEffectContext->GameplayAbilityInstance`에서 random seed를 가져와야 한다.

GASShooter의 헤드샷 구현도 동일한 개념을 따르지만, 난수로 확률을 판정하는 대신 `FHitResult`의 bone name을 검사하는 방식을 사용한다.

---

