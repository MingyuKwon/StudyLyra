# Cost & Cooldown GE

> **GASDoc**: 4.5.13~15 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-car"></a>
#### 4.5.13 Custom Application Requirement

[`CustomApplicationRequirement`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffectCustomApplication-/index.html)(`CAR`) 클래스는 설계자에게 `GameplayEffect`를 적용할 수 있는지 여부를 제어하는 고급 수단을 제공한다. `GameplayEffect`의 단순한 `GameplayTag` 체크보다 더 정교한 제어가 필요할 때 사용한다. Blueprint에서는 `CanApplyGameplayEffect()`를 오버라이드하여, C++에서는 `CanApplyGameplayEffect_Implementation()`을 오버라이드하여 구현할 수 있다.

`CAR`를 사용하는 예시:
* Target이 특정 수치 이상의 `Attribute`를 보유해야 하는 경우
* Target에 특정 `GameplayEffect`가 특정 스택 수만큼 쌓여 있어야 하는 경우

`CAR`는 더 고급 기능도 수행할 수 있다. 예를 들어, 이 `GameplayEffect`의 인스턴스가 이미 Target에 적용되어 있는지 확인하고, 새 인스턴스를 적용하는 대신 기존 인스턴스의 지속시간을 변경하는 것이 그 예다(이 경우 `CanApplyGameplayEffect()`에서 false를 반환한다).

<a name="concepts-ge-cost"></a>
#### 4.5.14 Cost Gameplay Effect

`GameplayAbilities`에는 어빌리티 비용(cost)으로 사용하기 위해 특별히 설계된 `GameplayEffect`를 선택적으로 지정할 수 있다. Cost는 `GameplayAbility`를 발동하기 위해 `ASC`가 보유해야 하는 `Attribute` 수치를 의미한다. `GA`가 `Cost GE`를 충족하지 못하면 발동할 수 없다. 이 `Cost GE`는 `Attribute`에서 값을 차감하는 Modifier를 하나 이상 포함하는 `Instant` `GameplayEffect`여야 한다. 기본적으로 `Cost GEs`는 예측 가능하게 유지하도록 설계되었으며, 그 특성을 유지하는 것이 권장된다 — 즉, `ExecutionCalculations`를 사용하지 말 것. 복잡한 비용 계산에는 `MMC`가 완전히 허용되며 오히려 권장된다.

처음에는 비용이 있는 `GA`마다 고유한 `Cost GE`를 하나씩 만드는 것이 일반적이다. 더 고급 기법은 여러 `GA`에서 하나의 `Cost GE`를 재사용하고, `Cost GE`로부터 생성된 `GameplayEffectSpec`을 `GA`별 데이터(비용 값은 `GA`에 정의됨)로 커스터마이징하는 것이다. **이 방법은 `Instanced` 어빌리티에서만 동작한다.**

`Cost GE`를 재사용하는 두 가지 방법:

1. **`MMC` 사용.** 가장 간단한 방법이다. `GameplayEffectSpec`에서 가져올 수 있는 `GameplayAbility` 인스턴스로부터 비용 값을 읽는 `MMC`를 생성한다.

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

2. **`UGameplayAbility::GetCostGameplayEffect()` 오버라이드.** 이 함수를 오버라이드하여 `GameplayAbility`의 비용 값을 읽는 런타임 `GameplayEffect`를 생성한다.

<a name="concepts-ge-cooldown"></a>
#### 4.5.15 Cooldown Gameplay Effect

`GameplayAbilities`에는 어빌리티 쿨다운으로 사용하기 위해 특별히 설계된 `GameplayEffect`를 선택적으로 지정할 수 있다. 쿨다운은 발동 후 어빌리티를 다시 발동할 수 있을 때까지의 대기 시간을 결정한다. `GA`가 쿨다운 중이면 발동할 수 없다. 이 `Cooldown GE`는 Modifier가 없는 `Duration` `GameplayEffect`여야 하며, `GameplayEffect`의 `GrantedTags`에 `GameplayAbility`마다(또는 어빌리티를 슬롯에 할당하고 슬롯이 쿨다운을 공유하는 게임이라면 어빌리티 슬롯마다) 고유한 `GameplayTag`("`Cooldown Tag`")를 지정해야 한다. `GA`는 실제로 `Cooldown GE`의 존재가 아닌 `Cooldown Tag`의 존재를 확인한다. 기본적으로 `Cooldown GEs`는 예측 가능하게 유지하도록 설계되었으며, 그 특성을 유지하는 것이 권장된다 — 즉, `ExecutionCalculations`를 사용하지 말 것. 복잡한 쿨다운 계산에는 `MMC`가 완전히 허용되며 오히려 권장된다.

처음에는 쿨다운이 있는 `GA`마다 고유한 `Cooldown GE`를 하나씩 만드는 것이 일반적이다. 더 고급 기법은 여러 `GA`에서 하나의 `Cooldown GE`를 재사용하고, `Cooldown GE`로부터 생성된 `GameplayEffectSpec`을 `GA`별 데이터(쿨다운 지속시간과 `Cooldown Tag`는 `GA`에 정의됨)로 커스터마이징하는 것이다. **이 방법은 `Instanced` 어빌리티에서만 동작한다.**

`Cooldown GE`를 재사용하는 두 가지 방법:

1. **`SetByCaller` 사용.** 가장 간단한 방법이다. 공유 `Cooldown GE`의 지속시간을 `GameplayTag`가 포함된 `SetByCaller`로 설정한다. `GameplayAbility` 서브클래스에는 지속시간을 위한 float / `FScalableFloat`, 고유 `Cooldown Tag`를 위한 `FGameplayTagContainer`, 그리고 `Cooldown Tag`와 `Cooldown GE`의 태그 합집합의 반환 포인터로 사용할 임시 `FGameplayTagContainer`를 정의한다.
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

2. **`MMC` 사용.** 위 방법과 설정이 거의 같지만, `Cooldown GE`에서 `SetByCaller`를 지속시간으로 설정하고 `ApplyCooldown`에서 값을 주입하는 부분이 다르다. 대신 지속시간을 `Custom Calculation Class`로 설정하고, 새로 만들 `MMC`를 가리키도록 한다.
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

**주의:** 클라이언트에서 쿨다운 남은 시간을 조회하려면 클라이언트가 복제된 `GameplayEffects`를 수신할 수 있어야 한다. 이는 `ASC`의 복제 모드에 따라 달라진다.

<a name="concepts-ge-cooldown-listen"></a>
##### 4.5.15.2 쿨다운 시작 및 종료 감지

쿨다운이 시작되는 시점을 감지하려면, `Cooldown GE`가 적용될 때 `AbilitySystemComponent->OnActiveGameplayEffectAddedDelegateToSelf`에 바인딩하거나, `Cooldown Tag`가 추가될 때 `AbilitySystemComponent->RegisterGameplayTagEvent(CooldownTag, EGameplayTagEventType::NewOrRemoved)`에 바인딩할 수 있다. `Cooldown GE`가 추가되는 시점을 감지하는 것을 권장하는데, 이렇게 하면 적용한 `GameplayEffectSpec`에도 접근할 수 있어 로컬에서 예측한 `Cooldown GE`인지 서버에서 보정된 것인지 구분할 수 있기 때문이다.

쿨다운이 종료되는 시점을 감지하려면, `Cooldown GE`가 제거될 때 `AbilitySystemComponent->OnAnyGameplayEffectRemovedDelegate()`에 바인딩하거나, `Cooldown Tag`가 제거될 때 `AbilitySystemComponent->RegisterGameplayTagEvent(CooldownTag, EGameplayTagEventType::NewOrRemoved)`에 바인딩할 수 있다. `Cooldown Tag`가 제거되는 시점을 감지하는 것을 권장한다. 서버의 보정된 `Cooldown GE`가 들어오면 로컬에서 예측한 것이 제거되면서 `OnAnyGameplayEffectRemovedDelegate()`가 발동되는데, 이때는 아직 쿨다운 중이다. 그러나 예측된 `Cooldown GE`가 제거되고 서버의 보정된 `Cooldown GE`가 적용되는 과정에서 `Cooldown Tag`는 변경되지 않는다.

**주의:** 클라이언트에서 `GameplayEffect`의 추가 또는 제거를 감지하려면 클라이언트가 복제된 `GameplayEffects`를 수신할 수 있어야 한다. 이는 `ASC`의 복제 모드에 따라 달라진다.

샘플 프로젝트에는 쿨다운 시작과 종료를 감지하는 커스텀 Blueprint 노드가 포함되어 있다. HUD UMG 위젯은 이를 사용해 Meteor의 쿨다운 남은 시간을 업데이트한다. 이 `AsyncTask`는 UMG 위젯의 `Destruct` 이벤트에서 `EndTask()`를 수동으로 호출할 때까지 유지된다. [`AsyncTaskCooldownChanged.h/cpp`](Source/GASDocumentation/Private/Characters/Abilities/AsyncTaskCooldownChanged.cpp)를 참고하라.

![Listen for Cooldown Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/cooldownchange.png)

<a name="concepts-ge-cooldown-prediction"></a>
##### 4.5.15.3 쿨다운 예측

현재 쿨다운은 진정한 의미에서 예측할 수 없다. 로컬에서 예측된 `Cooldown GE`가 적용될 때 UI 쿨다운 타이머를 시작할 수 있지만, `GameplayAbility`의 실제 쿨다운은 서버의 쿨다운 남은 시간에 종속된다. 플레이어의 레이턴시에 따라 로컬에서 예측된 쿨다운이 만료되었더라도 `GameplayAbility`는 서버에서 여전히 쿨다운 중일 수 있으며, 이 경우 서버의 쿨다운이 만료될 때까지 `GameplayAbility`를 즉시 재발동할 수 없다.

샘플 프로젝트는 로컬에서 예측된 쿨다운이 시작될 때 Meteor 어빌리티의 UI 아이콘을 회색으로 처리하고, 서버의 보정된 `Cooldown GE`가 들어온 후에 쿨다운 타이머를 시작하는 방식으로 이 문제를 처리한다.

이러한 게임플레이 상의 결과로, 레이턴시가 높은 플레이어는 쿨다운이 짧은 어빌리티에서 레이턴시가 낮은 플레이어보다 발사 속도가 느려져 불리해진다. Fortnite는 이 문제를 피하기 위해 Cooldown `GameplayEffects`를 사용하지 않는 자체 북키핑(bookkeeping) 방식을 무기에 적용했다.

진정한 쿨다운 예측(로컬 쿨다운이 만료되면 서버가 아직 쿨다운 중이더라도 `GameplayAbility`를 발동할 수 있게 하는 것)은 Epic이 GAS의 향후 개선에서 언젠가 구현하고 싶다고 밝힌 사항이다.

---

### Cost/Cooldown GE 재사용 패턴이 Instanced 어빌리티를 요구하는 이유

> 소스: `GameplayAbility.cpp:1995`, `GameplayEffectTypes.cpp:226`, `GameplayEffectTypes.cpp:269`

개념 요약에서 "이 방법은 Instanced 어빌리티에서만 동작한다"고 두 번 언급한다. 이유는 두 가지다.

핵심 전제: **Non-Instanced 어빌리티는 CDO 위에서 실행된다.**

```cpp
// GameplayAbility.cpp:1995
bool UGameplayAbility::IsInstantiated() const
{
    return !HasAllFlags(RF_ClassDefaultObject);  // CDO면 false
}
```

Non-Instanced 어빌리티에서 `this`는 CDO다. CDO는 같은 어빌리티 클래스를 사용하는 모든 액터가 공유하는 싱글톤이다.

---

#### 이유 1 — TempCooldownTags가 CDO에 쓰인다 (공유 상태 오염)

`GetCooldownTags()`는 런타임에 `TempCooldownTags` 필드를 수정한다.

```cpp
const FGameplayTagContainer* UPGGameplayAbility::GetCooldownTags() const
{
    FGameplayTagContainer* MutableTags = const_cast<FGameplayTagContainer*>(&TempCooldownTags);
    MutableTags->Reset(); // "writes to the TempCooldownTags on the CDO"
    MutableTags->AppendTags(CooldownTags);
    return MutableTags;
}
```

코드 주석이 직접 말한다. Non-Instanced이면 `this` = CDO이므로, 여러 액터가 동시에 같은 어빌리티를 활성화하면 전부 같은 CDO의 `TempCooldownTags`를 동시에 쓴다 — 경쟁 조건이다.

Instanced이면 액터마다 독립적인 `UGameplayAbility` 인스턴스가 있으므로 `TempCooldownTags`가 격리된다.

---

#### 이유 2 — GetAbilityInstance_NotReplicated()가 복제되지 않는다

MMC에서 어빌리티 데이터를 꺼내는 방식:

```cpp
const UPGGameplayAbility* Ability = Cast<UPGGameplayAbility>(
    Spec.GetContext().GetAbilityInstance_NotReplicated());
```

`FGameplayEffectContext::NetSerialize`를 보면 `AbilityCDO`는 복제되지만 `AbilityInstanceNotReplicated`는 복제되지 않는다.

```cpp
// GameplayEffectTypes.cpp:286 — NetSerialize
if (AbilityCDO.IsValid())      RepBits |= 1 << 2;  // 복제됨
// AbilityInstanceNotReplicated → 7비트 어디에도 없음 → 복제 안 됨

// GameplayEffectTypes.cpp:226 — SetAbilityInstance
AbilityInstanceNotReplicated = MakeWeakObjectPtr(InGameplayAbility); // 로컬 전용
AbilityCDO = InGameplayAbility->GetClass()->GetDefaultObject<UGameplayAbility>();
```

서버가 Cost GE Spec을 생성할 때 `AbilityInstanceNotReplicated`에 `this`(능력 인스턴스)를 저장한다. 이 Spec이 클라이언트에 복제되면 해당 필드는 null이 된다. 클라이언트가 replicated GE를 재평가할 때 `GetAbilityInstance_NotReplicated()` = null → Cast 실패 → MMC 반환값 0.

Non-Instanced이면 `this`가 CDO이고, CDO 포인터는 네트워크로 의미 있게 전달되지 않는다. Instanced이면 Spec에 자기 인스턴스 포인터가 들어가고 클라이언트에서 로컬 예측 경로로도 올바르게 평가된다.

---

#### UE 5.5에서 NonInstanced 정책 자체가 제거됐다

```cpp
// GameplayAbility.cpp:31
// "Whether to allow the deprecated EGameplayAbilityInstancingPolicy::NonInstanced
//  type (removed in UE5.5)"
FAutoConsoleVariableRef CVarAllowNonInstancedGAs(..., CVarAllowNonInstancedGAsValue, ...);
```

UE 5.5부터 `EGameplayAbilityInstancingPolicy::NonInstanced`는 deprecated → removed됐다. 결국 "Instanced에서만 동작한다"는 조건은 현재 버전에서 항상 충족된다.

---

### Lyra의 Cost — GE를 쓰지 않는다

> 소스: `LyraAbilityCost.h`, `LyraAbilityCost_ItemTagStack.cpp`, `LyraAbilityCost_PlayerTagStack.cpp`, `LyraAbilityCost_InventoryItem.h`, `LyraGameplayAbility.cpp:202`

개념 요약(4.5.14)은 Cost를 Instant GE로 구현하는 패턴을 설명한다. Lyra는 이 방식을 쓰지 않는다. Cost GE 필드는 비어있고, 대신 `ULyraAbilityCost`라는 별도 추상 클래스를 도입했다.

```cpp
// LyraGameplayAbility.h:202
UPROPERTY(EditDefaultsOnly, Instanced, Category = Costs)
TArray<TObjectPtr<ULyraAbilityCost>> AdditionalCosts;
```

`CheckCost` / `ApplyCost`를 오버라이드해서 배열을 순회한다.

```cpp
// LyraGameplayAbility.cpp:202
bool ULyraGameplayAbility::CheckCost(...) const
{
    if (!Super::CheckCost(...)) return false;  // GE 기반 Cost는 여기서 처리 (비어있으면 pass)

    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
        if (!AdditionalCost->CheckCost(this, ...)) return false;

    return true;
}

void ULyraGameplayAbility::ApplyCost(...) const
{
    Super::ApplyCost(...);  // GE 기반 Cost 처리

    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
    {
        if (AdditionalCost->ShouldOnlyApplyCostOnHit())
        {
            // TargetData에 HitResult가 있을 때만 차감
            if (!DetermineIfAbilityHitTarget()) continue;
        }
        AdditionalCost->ApplyCost(this, ...);
    }
}
```

Lyra가 제공하는 `ULyraAbilityCost` 구현체 세 가지:

| 클래스 | 차감 대상 | 주요 로직 |
|---|---|---|
| `LyraAbilityCost_ItemTagStack` | 장착 아이템의 TagStack (탄약 등) | `ItemInstance->RemoveStatTagStack(Tag, NumStacks)` |
| `LyraAbilityCost_PlayerTagStack` | PlayerState의 TagStack | `PS->RemoveStatTagStack(Tag, NumStacks)` |
| `LyraAbilityCost_InventoryItem` | 인벤토리 아이템 수량 | `InventoryManager->ConsumeItemsByDefinition(...)` |

세 구현체 모두 `ApplyCost`에서 `IsNetAuthority()` 체크를 먼저 한다 — **클라이언트에서는 실제 차감을 하지 않는다.** 즉, 이 Cost는 예측되지 않는다.

**GE를 버린 이유**: Lyra의 Cost는 Attribute 수치가 아니라 인벤토리 아이템과 TagStack이다. GE의 Modifier는 `FGameplayAttributeData` 위에서만 동작하므로 인벤토리를 건드릴 수 없다. `ULyraAbilityCost`로 추상화하면 GE Modifier 규칙에 묶이지 않고 임의의 게임 로직을 Cost로 표현할 수 있다.

**`bOnlyApplyCostOnHit`**: 히트가 확인된 경우에만 비용을 차감한다. 탄약이 이 플래그를 쓰면 "발사했지만 히트 미스"인 경우 탄약이 소모되지 않는다. 서버에서 TargetData의 HitResult 유무로 판단한다.

---

#### Cost는 예측되지 않는다 — 의도적 타협

> 소스: `GameplayAbility.cpp:631`, `LyraAbilityCost_ItemTagStack.cpp:43`

`CommitAbilityCost`의 흐름:

```cpp
// GameplayAbility.cpp:631
bool UGameplayAbility::CommitAbilityCost(...)
{
    if (!CheckCost(...)) return false;  // 클라이언트에서도 실행
    ApplyCost(...);                     // 클라이언트에서도 실행 — 그러나 아무것도 안 함
    return true;
}

// LyraAbilityCost_ItemTagStack.cpp:43
void ULyraAbilityCost_ItemTagStack::ApplyCost(...)
{
    if (ActorInfo->IsNetAuthority())  // 서버에서만 진입
    {
        ItemInstance->RemoveStatTagStack(Tag, NumStacks);
    }
    // 클라이언트는 여기서 그냥 리턴
}
```

클라이언트에서 `CheckCost`는 **복제된 TagStack 값**을 읽어 통과 여부를 판단한다. 통과하면 능력을 로컬에서 발동한다. 하지만 `ApplyCost`는 공백이라 클라이언트의 탄약 카운터는 그대로다.

결과적으로 RTT 동안 클라이언트의 탄약은 차감되지 않고, 능력만 발동된다.

```
[RTT 100ms, 탄약 2발 상황]

t=  0ms  클라 탄약=2(복제값), 발사① CheckCost 통과, ApplyCost 공백 → 클라 탄약 여전히 2
t= 10ms  클라 발사② CheckCost 통과(아직 2), ApplyCost 공백 → 클라 탄약 여전히 2
t= 20ms  클라 발사③ CheckCost 통과(아직 2)...

t= 50ms  서버 발사① 수신 → 탄약 1로 차감, 복제
t= 60ms  서버 발사② 수신 → 탄약 0으로 차감, 복제
t= 70ms  서버 발사③ 수신 → CheckCost 실패 → 거부, 롤백
t=100ms  클라 탄약=0 수신 (복제)
```

RTT 사이에 탄약보다 더 많이 발사할 수 있고, 서버가 거부하면 롤백된다. **이것은 진정한 예측이 아니다.**

**Lyra가 이 타협을 선택한 이유**: 능력 실행(애니메이션, VFX)의 예측과 Cost 상태(탄약 수)의 예측을 분리했다.

| | 예측함 | 예측 안 함 |
|---|---|---|
| 능력 발동 | 애니메이션, VFX, 히트 판정 | — |
| Cost 상태 | — | 탄약/TagStack 차감, 인벤토리 |

인벤토리 상태를 진짜로 예측하려면 클라이언트가 "아직 서버 미확인 차감량"을 별도로 추적하고, 서버가 거부하면 롤백해야 한다. `FFastArraySerializer` 기반 TagStack에 그 레이어를 얹으면 복잡도가 크게 올라간다.

Lyra의 판단: 총구 화염이 입력 즉시 나오지 않으면 조작감이 망가지지만, 탄약 카운터 숫자가 0.1초 늦게 줄어드는 건 플레이어가 크게 인식하지 못한다. Cost 상태는 서버 권한으로 두고 능력 실행만 예측하는 것으로 충분하다.

---

### Lyra의 Cooldown — 표준 GE 방식 그대로

> 소스: `GA_Hero_Dash.uasset`, `GA_Grenade.uasset`, `LyraGameplayAbility.cpp:36`

Cost와 달리 Cooldown은 개념 요약(4.5.15)의 표준 방식을 그대로 사용한다. `ULyraGameplayAbility`에 쿨다운 관련 커스텀 로직이 없고, `ApplyCooldown` / `GetCooldownTags`를 오버라이드하지 않는다. Duration GE를 `CooldownGameplayEffect` 필드에 블루프린트에서 할당하는 방식이다.

```cpp
// LyraGameplayAbility.cpp:36 — 생성자 기본값
InstancingPolicy = EGameplayAbilityInstancingPolicy::InstancedPerActor;
```

어빌리티별 고유 Cooldown GE를 쓰는 "처음에는 이렇게" 방식이다. Dash와 Grenade 각각 별도의 Cooldown GE를 갖는다. 개념 요약에서 말하는 SetByCaller나 MMC로 공유 GE를 재사용하는 고급 패턴은 Lyra에 없다.

**Cooldown이 GE로 남은 이유**: 쿨다운은 "일정 시간 동안 태그를 보유한다"는 Duration GE의 본질적 기능이다. 인벤토리 조작이 필요 없고, Attribute 조작도 없으며, 태그 부여와 시간 경과만 있다. GE가 가장 직접적인 도구이므로 굳이 바꿀 이유가 없다.

