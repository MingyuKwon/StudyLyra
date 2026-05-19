# 고급 GE 기능

> **GASDoc**: 4.5.16~18 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-duration"></a>
#### 4.5.16 활성 Gameplay Effect의 지속시간 변경

`Cooldown GE` 또는 `Duration` `GameplayEffect`의 남은 시간을 변경하려면 `GameplayEffectSpec`의 `Duration`을 변경하고, `StartServerWorldTime`, `CachedStartServerWorldTime`, `StartWorldTime`을 업데이트한 뒤, `CheckDuration()`으로 지속시간 검사를 다시 실행해야 한다. 서버에서 이를 수행하고 `FActiveGameplayEffect`를 dirty로 마킹하면 클라이언트에도 변경 사항이 복제된다.

**주의:** 이 방법은 `const_cast`를 포함하며 Epic이 의도한 지속시간 변경 방법이 아닐 수 있지만, 현재까지는 잘 동작하는 것으로 보인다.

```c++
bool UPAAbilitySystemComponent::SetGameplayEffectDurationHandle(FActiveGameplayEffectHandle Handle, float NewDuration)
{
	if (!Handle.IsValid())
	{
		return false;
	}

	const FActiveGameplayEffect* ActiveGameplayEffect = GetActiveGameplayEffect(Handle);
	if (!ActiveGameplayEffect)
	{
		return false;
	}

	FActiveGameplayEffect* AGE = const_cast<FActiveGameplayEffect*>(ActiveGameplayEffect);
	if (NewDuration > 0)
	{
		AGE->Spec.Duration = NewDuration;
	}
	else
	{
		AGE->Spec.Duration = 0.01f;
	}

	AGE->StartServerWorldTime = ActiveGameplayEffects.GetServerWorldTime();
	AGE->CachedStartServerWorldTime = AGE->StartServerWorldTime;
	AGE->StartWorldTime = ActiveGameplayEffects.GetWorldTime();
	ActiveGameplayEffects.MarkItemDirty(*AGE);
	ActiveGameplayEffects.CheckDuration(Handle);

	AGE->EventSet.OnTimeChanged.Broadcast(AGE->Handle, AGE->StartWorldTime, AGE->GetDuration());
	OnGameplayEffectDurationChange(*AGE);

	return true;
}
```

<a name="concepts-ge-dynamic"></a>
#### 4.5.17 런타임에 동적 Gameplay Effect 생성

런타임에 `GameplayEffects`를 동적으로 생성하는 것은 고급 주제다. 이 작업을 자주 할 필요는 없다.

C++에서 런타임에 처음부터 생성할 수 있는 것은 `Instant` `GameplayEffects`뿐이다. `Duration`과 `Infinite` `GameplayEffects`는 복제될 때 존재하지 않는 `GameplayEffect` 클래스 정의를 찾기 때문에 런타임에 동적으로 생성할 수 없다. 이 기능을 구현하려면 에디터에서 일반적으로 하듯이 원형(archetype) `GameplayEffect` 클래스를 만들고, 런타임에 필요한 내용으로 `GameplayEffectSpec` 인스턴스를 커스터마이징하는 방식을 사용해야 한다.

런타임에 생성된 `Instant` `GameplayEffects`는 로컬 예측(local predicted) `GameplayAbility` 내부에서도 호출할 수 있다. 하지만 동적 생성이 사이드 이펙트를 유발할 수 있는지 여부는 아직 알려져 있지 않다.

##### 예시

샘플 프로젝트는 캐릭터가 최후의 일격(killing blow)을 받을 때 `AttributeSet` 내에서 킬러에게 골드와 경험치를 전달하기 위해 동적 GE를 하나 생성한다.

```c++
// Create a dynamic instant Gameplay Effect to give the bounties
UGameplayEffect* GEBounty = NewObject<UGameplayEffect>(GetTransientPackage(), FName(TEXT("Bounty")));
GEBounty->DurationPolicy = EGameplayEffectDurationType::Instant;

int32 Idx = GEBounty->Modifiers.Num();
GEBounty->Modifiers.SetNum(Idx + 2);

FGameplayModifierInfo& InfoXP = GEBounty->Modifiers[Idx];
InfoXP.ModifierMagnitude = FScalableFloat(GetXPBounty());
InfoXP.ModifierOp = EGameplayModOp::Additive;
InfoXP.Attribute = UGDAttributeSetBase::GetXPAttribute();

FGameplayModifierInfo& InfoGold = GEBounty->Modifiers[Idx + 1];
InfoGold.ModifierMagnitude = FScalableFloat(GetGoldBounty());
InfoGold.ModifierOp = EGameplayModOp::Additive;
InfoGold.Attribute = UGDAttributeSetBase::GetGoldAttribute();

Source->ApplyGameplayEffectToSelf(GEBounty, 1.0f, Source->MakeEffectContext());
```

두 번째 예시는 로컬 예측 `GameplayAbility` 내부에서 런타임 GE를 생성하는 방법이다. 사이드 이펙트가 발생할 수 있으니 사용에 주의할 것(코드 주석 참고)!

```c++
UGameplayAbilityRuntimeGE::UGameplayAbilityRuntimeGE()
{
	NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::LocalPredicted;
}

void UGameplayAbilityRuntimeGE::ActivateAbility(const FGameplayAbilitySpecHandle Handle, const FGameplayAbilityActorInfo* ActorInfo, const FGameplayAbilityActivationInfo ActivationInfo, const FGameplayEventData* TriggerEventData)
{
	if (HasAuthorityOrPredictionKey(ActorInfo, &ActivationInfo))
	{
		if (!CommitAbility(Handle, ActorInfo, ActivationInfo))
		{
			EndAbility(Handle, ActorInfo, ActivationInfo, true, true);
		}

		// Create the GE at runtime.
		UGameplayEffect* GameplayEffect = NewObject<UGameplayEffect>(GetTransientPackage(), TEXT("RuntimeInstantGE"));
		GameplayEffect->DurationPolicy = EGameplayEffectDurationType::Instant; // Only instant works with runtime GE.

		// Add a simple scalable float modifier, which overrides MyAttribute with 42.
		// In real world applications, consume information passed via TriggerEventData.
		const int32 Idx = GameplayEffect->Modifiers.Num();
		GameplayEffect->Modifiers.SetNum(Idx + 1);
		FGameplayModifierInfo& ModifierInfo = GameplayEffect->Modifiers[Idx];
		ModifierInfo.Attribute.SetUProperty(UMyAttributeSet::GetMyModifiedAttribute());
		ModifierInfo.ModifierMagnitude = FScalableFloat(42.f);
		ModifierInfo.ModifierOp = EGameplayModOp::Override;

		// Apply the GE.

		// Create the GESpec here to avoid the behavior of ASC to create GESpecs from the GE class default object.
		// Since we have a dynamic GE here, this would create a GESpec with the base GameplayEffect class, so we
		// would lose our modifiers. Attention: It is unknown, if this "hack" done here can have drawbacks!
		// The spec prevents the GE object being collected by the GarbageCollector, since the GE is a UPROPERTY on the spec.
		FGameplayEffectSpec* GESpec = new FGameplayEffectSpec(GameplayEffect, {}, 0.f); // "new", since lifetime is managed by a shared ptr within the handle
		ApplyGameplayEffectSpecToOwner(Handle, ActorInfo, ActivationInfo, FGameplayEffectSpecHandle(GESpec));
	}
	EndAbility(Handle, ActorInfo, ActivationInfo, false, false);
}
```

<a name="concepts-ge-containers"></a>
#### 4.5.18 Gameplay Effect Containers

Epic의 [Action RPG Sample Project](https://www.unrealengine.com/marketplace/en-US/product/action-rpg)는 `FGameplayEffectContainer`라는 구조체를 구현한다. 이 구조체는 기본 GAS에 포함되어 있지 않지만, `GameplayEffects`와 `TargetData`를 함께 담는 데 매우 유용하다. `GameplayEffects`로부터 `GameplayEffectSpecs`를 생성하고 `GameplayEffectContext`에 기본값을 설정하는 등의 작업을 자동화해준다. `GameplayAbility`에서 `GameplayEffectContainer`를 만들어 발사체(projectile)에 전달하는 것은 매우 쉽고 직관적이다. 필자는 포함된 샘플 프로젝트에 `GameplayEffectContainers`를 구현하지 않았는데, 이는 기본 GAS만으로 어떻게 작업하는지를 보여주기 위해서였다. 하지만 이 구조체를 자세히 살펴보고 자신의 프로젝트에 추가하는 것을 강력히 권장한다.

`GameplayEffectContainers` 내부의 `GESpecs`에 접근하여 `SetByCallers` 추가 등의 작업을 하려면, `FGameplayEffectContainer`를 분해(break)하고 `GESpec` 배열에서 인덱스로 `GESpec` 참조에 접근한다. 이 경우 접근하려는 `GESpec`의 인덱스를 미리 알고 있어야 한다.

![SetByCaller with a GameplayEffectContainer](https://github.com/tranek/GASDocumentation/raw/master/Images/gecontainersetbycaller.png)

`GameplayEffectContainers`에는 선택적으로 효율적인 타게팅 수단도 포함되어 있다.

---

