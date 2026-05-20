# Lifesteal & 치명타 구현

> **GASDoc**: 5.4 / 5.6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-ls"></a>
### Lifesteal을 ExecutionCalculation 내에서 어떻게 구현하는가?

데미지 ExecutionCalculation 내부에서 처리한다. GE에 `Effect.CanLifesteal` 같은 GameplayTag를 부여하고, ExecCalc에서 해당 태그가 있는지 확인한 뒤 있으면 동적 Instant GE를 생성해 Source ASC에 적용한다:

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
### 치명타 판정은 ExecCalc 내에서 어떻게 구현하며 클라-서버 난수 동기화가 필요 없는 이유는?

데미지 ExecutionCalculation 내부에서 처리한다. GE에 `Effect.CanCrit` 태그를 부여하고, ExecCalc에서 Source의 치명타 확률 Attribute를 캡처해 난수와 비교한다. 성공하면 치명타 데미지 Attribute를 추가 적용한다.

클라이언트-서버 난수 동기화가 필요 없는 이유: **ExecutionCalculation은 서버에서만 실행되기 때문이다.** 데미지를 예측(predict)하지 않으므로 양측 난수 생성기를 동기화할 필요가 없다.

> MMC를 사용해 예측 방식으로 데미지를 계산하고 싶다면, `GameplayEffectSpec->GameplayEffectContext->GameplayAbilityInstance`에서 random seed를 가져와야 한다.

GASShooter의 헤드샷 구현도 같은 개념이지만, 난수 확률 대신 `FHitResult`의 bone name을 검사하는 방식을 사용한다.

---
