# Cost & Cooldown GE

> **GASDoc**: 4.5.13~15 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-car"></a>
#### 4.5.13 Custom Application Requirement

[`CustomApplicationRequirement`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffectCustomApplication-/index.html)(`CAR`) 클래스는 설계자에게 `GameplayEffect`를 적용할 수 있는지 여부를 제어하는 고급 수단을 제공한다. `GameplayEffect`의 단순한 `GameplayTag` 체크보다 더 정교한 제어가 필요할 때 사용한다. Blueprint에서는 `CanApplyGameplayEffect()`를 오버라이드하여, C++에서는 `CanApplyGameplayEffect_Implementation()`을 오버라이드하여 구현할 수 있다.

`CAR`를 사용하는 예시:
* Target이 특정 수치 이상의 `Attribute`를 보유해야 하는 경우
* Target에 특정 `GameplayEffect`가 특정 스택 수만큼 쌓여 있어야 하는 경우

`CAR`는 더 고급 기능도 수행할 수 있다. 예를 들어, 이 `GameplayEffect`의 인스턴스가 이미 Target에 적용되어 있는지 확인하고, 새 인스턴스를 적용하는 대신 기존 인스턴스의 [지속시간을 변경](#concepts-ge-duration)하는 것이 그 예다(이 경우 `CanApplyGameplayEffect()`에서 false를 반환한다).

<a name="concepts-ge-cost"></a>
#### 4.5.14 Cost Gameplay Effect

[`GameplayAbilities`](#concepts-ga)에는 어빌리티 비용(cost)으로 사용하기 위해 특별히 설계된 `GameplayEffect`를 선택적으로 지정할 수 있다. Cost는 `GameplayAbility`를 발동하기 위해 `ASC`가 보유해야 하는 `Attribute` 수치를 의미한다. `GA`가 `Cost GE`를 충족하지 못하면 발동할 수 없다. 이 `Cost GE`는 `Attribute`에서 값을 차감하는 Modifier를 하나 이상 포함하는 `Instant` `GameplayEffect`여야 한다. 기본적으로 `Cost GEs`는 예측 가능하게 유지하도록 설계되었으며, 그 특성을 유지하는 것이 권장된다 — 즉, `ExecutionCalculations`를 사용하지 말 것. 복잡한 비용 계산에는 `MMC`가 완전히 허용되며 오히려 권장된다.

처음에는 비용이 있는 `GA`마다 고유한 `Cost GE`를 하나씩 만드는 것이 일반적이다. 더 고급 기법은 여러 `GA`에서 하나의 `Cost GE`를 재사용하고, `Cost GE`로부터 생성된 `GameplayEffectSpec`을 `GA`별 데이터(비용 값은 `GA`에 정의됨)로 커스터마이징하는 것이다. **이 방법은 `Instanced` 어빌리티에서만 동작한다.**

`Cost GE`를 재사용하는 두 가지 방법:

1. **`MMC` 사용.** 가장 간단한 방법이다. `GameplayEffectSpec`에서 가져올 수 있는 `GameplayAbility` 인스턴스로부터 비용 값을 읽는 [`MMC`](#concepts-ge-mmc)를 생성한다.

```c++
float UPGMMC_HeroAbilityCost::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec & Spec) const
{
	const UPGGameplayAbility* Ability = Cast<UPGGameplayAbility>(Spec.GetContext().GetAbilityInstance_NotReplicated());

	if (!Ability)
	{
		return 0.0f;
	}

	return Ability->Cost.GetValueAtLevel(Ability->GetAbilityLevel());
}
```

이 예시에서 비용 값은 `GameplayAbility` 서브클래스에 추가한 `FScalableFloat`이다.
```c++
UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cost")
FScalableFloat Cost;
```

![Cost GE With MMC](https://github.com/tranek/GASDocumentation/raw/master/Images/costmmc.png)

2. **`UGameplayAbility::GetCostGameplayEffect()` 오버라이드.** 이 함수를 오버라이드하여 `GameplayAbility`의 비용 값을 읽는 [런타임 `GameplayEffect`](#concepts-ge-dynamic)를 생성한다.

<a name="concepts-ge-cooldown"></a>
#### 4.5.15 Cooldown Gameplay Effect

[`GameplayAbilities`](#concepts-ga)에는 어빌리티 쿨다운으로 사용하기 위해 특별히 설계된 `GameplayEffect`를 선택적으로 지정할 수 있다. 쿨다운은 발동 후 어빌리티를 다시 발동할 수 있을 때까지의 대기 시간을 결정한다. `GA`가 쿨다운 중이면 발동할 수 없다. 이 `Cooldown GE`는 Modifier가 없는 `Duration` `GameplayEffect`여야 하며, `GameplayEffect`의 `GrantedTags`에 `GameplayAbility`마다(또는 어빌리티를 슬롯에 할당하고 슬롯이 쿨다운을 공유하는 게임이라면 어빌리티 슬롯마다) 고유한 `GameplayTag`("`Cooldown Tag`")를 지정해야 한다. `GA`는 실제로 `Cooldown GE`의 존재가 아닌 `Cooldown Tag`의 존재를 확인한다. 기본적으로 `Cooldown GEs`는 예측 가능하게 유지하도록 설계되었으며, 그 특성을 유지하는 것이 권장된다 — 즉, `ExecutionCalculations`를 사용하지 말 것. 복잡한 쿨다운 계산에는 `MMC`가 완전히 허용되며 오히려 권장된다.

처음에는 쿨다운이 있는 `GA`마다 고유한 `Cooldown GE`를 하나씩 만드는 것이 일반적이다. 더 고급 기법은 여러 `GA`에서 하나의 `Cooldown GE`를 재사용하고, `Cooldown GE`로부터 생성된 `GameplayEffectSpec`을 `GA`별 데이터(쿨다운 지속시간과 `Cooldown Tag`는 `GA`에 정의됨)로 커스터마이징하는 것이다. **이 방법은 `Instanced` 어빌리티에서만 동작한다.**

`Cooldown GE`를 재사용하는 두 가지 방법:

1. **[`SetByCaller`](#concepts-ge-spec-setbycaller) 사용.** 가장 간단한 방법이다. 공유 `Cooldown GE`의 지속시간을 `GameplayTag`가 포함된 `SetByCaller`로 설정한다. `GameplayAbility` 서브클래스에는 지속시간을 위한 float / `FScalableFloat`, 고유 `Cooldown Tag`를 위한 `FGameplayTagContainer`, 그리고 `Cooldown Tag`와 `Cooldown GE`의 태그 합집합의 반환 포인터로 사용할 임시 `FGameplayTagContainer`를 정의한다.
```c++
UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FScalableFloat CooldownDuration;

UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FGameplayTagContainer CooldownTags;

// Temp container that we will return the pointer to in GetCooldownTags().
// This will be a union of our CooldownTags and the Cooldown GE's cooldown tags.
UPROPERTY(Transient)
FGameplayTagContainer TempCooldownTags;
```

다음으로 `UGameplayAbility::GetCooldownTags()`를 오버라이드하여 우리의 `Cooldown Tags`와 기존 `Cooldown GE`의 태그 합집합을 반환한다.
```c++
const FGameplayTagContainer * UPGGameplayAbility::GetCooldownTags() const
{
	FGameplayTagContainer* MutableTags = const_cast<FGameplayTagContainer*>(&TempCooldownTags);
	MutableTags->Reset(); // MutableTags writes to the TempCooldownTags on the CDO so clear it in case the ability cooldown tags change (moved to a different slot)
	const FGameplayTagContainer* ParentTags = Super::GetCooldownTags();
	if (ParentTags)
	{
		MutableTags->AppendTags(*ParentTags);
	}
	MutableTags->AppendTags(CooldownTags);
	return MutableTags;
}
```

마지막으로 `UGameplayAbility::ApplyCooldown()`을 오버라이드하여 우리의 `Cooldown Tags`를 주입하고 쿨다운 `GameplayEffectSpec`에 `SetByCaller`를 설정한다.
```c++
void UPGGameplayAbility::ApplyCooldown(const FGameplayAbilitySpecHandle Handle, const FGameplayAbilityActorInfo * ActorInfo, const FGameplayAbilityActivationInfo ActivationInfo) const
{
	UGameplayEffect* CooldownGE = GetCooldownGameplayEffect();
	if (CooldownGE)
	{
		FGameplayEffectSpecHandle SpecHandle = MakeOutgoingGameplayEffectSpec(CooldownGE->GetClass(), GetAbilityLevel());
		SpecHandle.Data.Get()->DynamicGrantedTags.AppendTags(CooldownTags);
		SpecHandle.Data.Get()->SetSetByCallerMagnitude(FGameplayTag::RequestGameplayTag(FName(  OurSetByCallerTag  )), CooldownDuration.GetValueAtLevel(GetAbilityLevel()));
		ApplyGameplayEffectSpecToOwner(Handle, ActorInfo, ActivationInfo, SpecHandle);
	}
}
```

아래 그림에서 쿨다운의 지속시간 `Modifier`는 `Data Tag`로 `Data.Cooldown`을 가진 `SetByCaller`로 설정된다. 코드에서 `Data.Cooldown`이 `OurSetByCallerTag`에 해당한다.

![Cooldown GE with SetByCaller](https://github.com/tranek/GASDocumentation/raw/master/Images/cooldownsbc.png)

2. **[`MMC`](#concepts-ge-mmc) 사용.** 위 방법과 설정이 거의 같지만, `Cooldown GE`에서 `SetByCaller`를 지속시간으로 설정하고 `ApplyCooldown`에서 값을 주입하는 부분이 다르다. 대신 지속시간을 `Custom Calculation Class`로 설정하고, 새로 만들 `MMC`를 가리키도록 한다.
```c++
UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FScalableFloat CooldownDuration;

UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FGameplayTagContainer CooldownTags;

// Temp container that we will return the pointer to in GetCooldownTags().
// This will be a union of our CooldownTags and the Cooldown GE's cooldown tags.
UPROPERTY(Transient)
FGameplayTagContainer TempCooldownTags;
```

다음으로 `UGameplayAbility::GetCooldownTags()`를 오버라이드하여 `Cooldown Tags`와 기존 `Cooldown GE`의 태그 합집합을 반환한다.
```c++
const FGameplayTagContainer * UPGGameplayAbility::GetCooldownTags() const
{
	FGameplayTagContainer* MutableTags = const_cast<FGameplayTagContainer*>(&TempCooldownTags);
	MutableTags->Reset(); // MutableTags writes to the TempCooldownTags on the CDO so clear it in case the ability cooldown tags change (moved to a different slot)
	const FGameplayTagContainer* ParentTags = Super::GetCooldownTags();
	if (ParentTags)
	{
		MutableTags->AppendTags(*ParentTags);
	}
	MutableTags->AppendTags(CooldownTags);
	return MutableTags;
}
```

마지막으로 `UGameplayAbility::ApplyCooldown()`을 오버라이드하여 `Cooldown Tags`를 쿨다운 `GameplayEffectSpec`에 주입한다.
```c++
void UPGGameplayAbility::ApplyCooldown(const FGameplayAbilitySpecHandle Handle, const FGameplayAbilityActorInfo * ActorInfo, const FGameplayAbilityActivationInfo ActivationInfo) const
{
	UGameplayEffect* CooldownGE = GetCooldownGameplayEffect();
	if (CooldownGE)
	{
		FGameplayEffectSpecHandle SpecHandle = MakeOutgoingGameplayEffectSpec(CooldownGE->GetClass(), GetAbilityLevel());
		SpecHandle.Data.Get()->DynamicGrantedTags.AppendTags(CooldownTags);
		ApplyGameplayEffectSpecToOwner(Handle, ActorInfo, ActivationInfo, SpecHandle);
	}
}
```

```c++
float UPGMMC_HeroAbilityCooldown::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec & Spec) const
{
	const UPGGameplayAbility* Ability = Cast<UPGGameplayAbility>(Spec.GetContext().GetAbilityInstance_NotReplicated());

	if (!Ability)
	{
		return 0.0f;
	}

	return Ability->CooldownDuration.GetValueAtLevel(Ability->GetAbilityLevel());
}
```

![Cooldown GE with MMC](https://github.com/tranek/GASDocumentation/raw/master/Images/cooldownmmc.png)

<a name="concepts-ge-cooldown-tr"></a>
##### 4.5.15.1 Cooldown Gameplay Effect의 남은 시간 조회
```c++
bool APGPlayerState::GetCooldownRemainingForTag(FGameplayTagContainer CooldownTags, float & TimeRemaining, float & CooldownDuration)
{
	if (AbilitySystemComponent && CooldownTags.Num() > 0)
	{
		TimeRemaining = 0.f;
		CooldownDuration = 0.f;

		FGameplayEffectQuery const Query = FGameplayEffectQuery::MakeQuery_MatchAnyOwningTags(CooldownTags);
		TArray< TPair<float, float> > DurationAndTimeRemaining = AbilitySystemComponent->GetActiveEffectsTimeRemainingAndDuration(Query);
		if (DurationAndTimeRemaining.Num() > 0)
		{
			int32 BestIdx = 0;
			float LongestTime = DurationAndTimeRemaining[0].Key;
			for (int32 Idx = 1; Idx < DurationAndTimeRemaining.Num(); ++Idx)
			{
				if (DurationAndTimeRemaining[Idx].Key > LongestTime)
				{
					LongestTime = DurationAndTimeRemaining[Idx].Key;
					BestIdx = Idx;
				}
			}

			TimeRemaining = DurationAndTimeRemaining[BestIdx].Key;
			CooldownDuration = DurationAndTimeRemaining[BestIdx].Value;

			return true;
		}
	}

	return false;
}
```

**주의:** 클라이언트에서 쿨다운 남은 시간을 조회하려면 클라이언트가 복제된 `GameplayEffects`를 수신할 수 있어야 한다. 이는 `ASC`의 [복제 모드](#concepts-asc-rm)에 따라 달라진다.

<a name="concepts-ge-cooldown-listen"></a>
##### 4.5.15.2 쿨다운 시작 및 종료 감지

쿨다운이 시작되는 시점을 감지하려면, `Cooldown GE`가 적용될 때 `AbilitySystemComponent->OnActiveGameplayEffectAddedDelegateToSelf`에 바인딩하거나, `Cooldown Tag`가 추가될 때 `AbilitySystemComponent->RegisterGameplayTagEvent(CooldownTag, EGameplayTagEventType::NewOrRemoved)`에 바인딩할 수 있다. `Cooldown GE`가 추가되는 시점을 감지하는 것을 권장하는데, 이렇게 하면 적용한 `GameplayEffectSpec`에도 접근할 수 있어 로컬에서 예측한 `Cooldown GE`인지 서버에서 보정된 것인지 구분할 수 있기 때문이다.

쿨다운이 종료되는 시점을 감지하려면, `Cooldown GE`가 제거될 때 `AbilitySystemComponent->OnAnyGameplayEffectRemovedDelegate()`에 바인딩하거나, `Cooldown Tag`가 제거될 때 `AbilitySystemComponent->RegisterGameplayTagEvent(CooldownTag, EGameplayTagEventType::NewOrRemoved)`에 바인딩할 수 있다. `Cooldown Tag`가 제거되는 시점을 감지하는 것을 권장한다. 서버의 보정된 `Cooldown GE`가 들어오면 로컬에서 예측한 것이 제거되면서 `OnAnyGameplayEffectRemovedDelegate()`가 발동되는데, 이때는 아직 쿨다운 중이다. 그러나 예측된 `Cooldown GE`가 제거되고 서버의 보정된 `Cooldown GE`가 적용되는 과정에서 `Cooldown Tag`는 변경되지 않는다.

**주의:** 클라이언트에서 `GameplayEffect`의 추가 또는 제거를 감지하려면 클라이언트가 복제된 `GameplayEffects`를 수신할 수 있어야 한다. 이는 `ASC`의 [복제 모드](#concepts-asc-rm)에 따라 달라진다.

샘플 프로젝트에는 쿨다운 시작과 종료를 감지하는 커스텀 Blueprint 노드가 포함되어 있다. HUD UMG 위젯은 이를 사용해 Meteor의 쿨다운 남은 시간을 업데이트한다. 이 `AsyncTask`는 UMG 위젯의 `Destruct` 이벤트에서 `EndTask()`를 수동으로 호출할 때까지 유지된다. [`AsyncTaskCooldownChanged.h/cpp`](Source/GASDocumentation/Private/Characters/Abilities/AsyncTaskCooldownChanged.cpp)를 참고하라.

![Listen for Cooldown Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/cooldownchange.png)

<a name="concepts-ge-cooldown-prediction"></a>
##### 4.5.15.3 쿨다운 예측

현재 쿨다운은 진정한 의미에서 예측할 수 없다. 로컬에서 예측된 `Cooldown GE`가 적용될 때 UI 쿨다운 타이머를 시작할 수 있지만, `GameplayAbility`의 실제 쿨다운은 서버의 쿨다운 남은 시간에 종속된다. 플레이어의 레이턴시에 따라 로컬에서 예측된 쿨다운이 만료되었더라도 `GameplayAbility`는 서버에서 여전히 쿨다운 중일 수 있으며, 이 경우 서버의 쿨다운이 만료될 때까지 `GameplayAbility`를 즉시 재발동할 수 없다.

샘플 프로젝트는 로컬에서 예측된 쿨다운이 시작될 때 Meteor 어빌리티의 UI 아이콘을 회색으로 처리하고, 서버의 보정된 `Cooldown GE`가 들어온 후에 쿨다운 타이머를 시작하는 방식으로 이 문제를 처리한다.

이러한 게임플레이 상의 결과로, 레이턴시가 높은 플레이어는 쿨다운이 짧은 어빌리티에서 레이턴시가 낮은 플레이어보다 발사 속도가 느려져 불리해진다. Fortnite는 이 문제를 피하기 위해 Cooldown `GameplayEffects`를 사용하지 않는 자체 북키핑(bookkeeping) 방식을 무기에 적용했다.

진정한 쿨다운 예측(로컬 쿨다운이 만료되면 서버가 아직 쿨다운 중이더라도 `GameplayAbility`를 발동할 수 있게 하는 것)은 Epic이 [GAS의 향후 개선](#concepts-p-future)에서 언젠가 구현하고 싶다고 밝힌 사항이다.

---

## 내 분석
