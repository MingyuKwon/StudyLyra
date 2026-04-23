# GA 부여 & 활성화

> **GASDoc**: 4.6.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-granting"></a>
#### 4.6.3 Granting Abilities
Granting a `GameplayAbility` to an `ASC` adds it to the `ASC's` list of `ActivatableAbilities` allowing it to activate the `GameplayAbility` at will if it meets the [`GameplayTag` requirements](#concepts-ga-tags).

We grant `GameplayAbilities` on the server which then automatically replicates the [`GameplayAbilitySpec`](#concepts-ga-spec) to the owning client. Other clients / simulated proxies do not receive the `GameplayAbilitySpec`.

The Sample Project stores a `TArray<TSubclassOf<UGDGameplayAbility>>` on the `Character` class that it reads from and grants when the game starts:
```c++
void AGDCharacterBase::AddCharacterAbilities()
{
	// Grant abilities, but only on the server	
	if (Role != ROLE_Authority || !AbilitySystemComponent.IsValid() || AbilitySystemComponent->bCharacterAbilitiesGiven)
	{
		return;
	}

	for (TSubclassOf<UGDGameplayAbility>& StartupAbility : CharacterAbilities)
	{
		AbilitySystemComponent->GiveAbility(
			FGameplayAbilitySpec(StartupAbility, GetAbilityLevel(StartupAbility.GetDefaultObject()->AbilityID), static_cast<int32>(StartupAbility.GetDefaultObject()->AbilityInputID), this));
	}

	AbilitySystemComponent->bCharacterAbilitiesGiven = true;
}
```

When granting these `GameplayAbilities`, we're creating `GameplayAbilitySpecs` with the `UGameplayAbility` class, the ability level, the input that it is bound to, and the `SourceObject` or who gave this `GameplayAbility` to this `ASC`.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-activating"></a>
#### 4.6.4 Activating Abilities
If a `GameplayAbility` is assigned an input action, it will be automatically activated if the input is pressed and it meets its `GameplayTag` requirements. This may not always be the desirable way to activate a `GameplayAbility`. The `ASC` provides four other methods of activating `GameplayAbilities`: by `GameplayTag`, `GameplayAbility` class, `GameplayAbilitySpec` handle, and by an event. Activating a `GameplayAbility` by event allows you to [pass in a payload of data with the event](#concepts-ga-data).

```c++
UFUNCTION(BlueprintCallable, Category = "Abilities")
bool TryActivateAbilitiesByTag(const FGameplayTagContainer& GameplayTagContainer, bool bAllowRemoteActivation = true);

UFUNCTION(BlueprintCallable, Category = "Abilities")
bool TryActivateAbilityByClass(TSubclassOf<UGameplayAbility> InAbilityToActivate, bool bAllowRemoteActivation = true);

bool TryActivateAbility(FGameplayAbilitySpecHandle AbilityToActivate, bool bAllowRemoteActivation = true);

bool TriggerAbilityFromGameplayEvent(FGameplayAbilitySpecHandle AbilityToTrigger, FGameplayAbilityActorInfo* ActorInfo, FGameplayTag Tag, const FGameplayEventData* Payload, UAbilitySystemComponent& Component);

FGameplayAbilitySpecHandle GiveAbilityAndActivateOnce(const FGameplayAbilitySpec& AbilitySpec, const FGameplayEventData* GameplayEventData);
```
To activate a `GameplayAbility` by event, the `GameplayAbility` must have its `Triggers` set up in the `GameplayAbility`. Assign a `GameplayTag` and pick an option for `GameplayEvent`. To send the event, use the function `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor(AActor* Actor, FGameplayTag EventTag, FGameplayEventData Payload)`. Activating a `GameplayAbility` by event allows you to pass in a payload with data.

`GameplayAbility` `Triggers` also allow you to activate the `GameplayAbility` when a `GameplayTag` is added or removed.

**Note:** When activating a `GameplayAbility` from event in Blueprint, you must use the `ActivateAbilityFromEvent` node.

**Note:** Don't forget to call `EndAbility()` when the `GameplayAbility` should terminate unless you have a `GameplayAbility` that will always run like a passive ability.

Activation sequence for **locally predicted** `GameplayAbilities`:
1. **Owning client** calls `TryActivateAbility()`
1. Calls `InternalTryActivateAbility()`
1. Calls `CanActivateAbility()` and returns whether `GameplayTag` requirements are met, if the `ASC` can afford the cost, if the `GameplayAbility` is not on cooldown, and if no other instances are currently active
1. Calls `CallServerTryActivateAbility()` and passes it the `Prediction Key` that it generates
1. Calls `CallActivateAbility()`
1. Calls `PreActivate()` Epic refers to this as "boilerplate init stuff"
1. Calls `ActivateAbility()` finally activating the ability

**Server** receives `CallServerTryActivateAbility()`
1. Calls `ServerTryActivateAbility()`
1. Calls `InternalServerTryActivateAbility()` 
1. Calls `InternalTryActivateAbility()`
1. Calls `CanActivateAbility()` and returns whether `GameplayTag` requirements are met, if the `ASC` can afford the cost, if the `GameplayAbility` is not on cooldown, and if no other instances are currently active
1. Calls `ClientActivateAbilitySucceed()` if successful telling it to update its `ActivationInfo` that its activation was confirmed by the server and broadcasting the `OnConfirmDelegate` delegate. This is not the same as input confirmation.
1. Calls `CallActivateAbility()`
1. Calls `PreActivate()` Epic refers to this as "boilerplate init stuff"
1. Calls `ActivateAbility()` finally activating the ability

If at any time the server fails to activate, it will call `ClientActivateAbilityFailed()`, immediately terminating the client's `GameplayAbility` and undoing any predicted changes.

<a name="concepts-ga-activating-passive"></a>
##### 4.6.4.1 Passive Abilities
To implement passive `GameplayAbilities` that automatically activate and run continuously, override `UGameplayAbility::OnAvatarSet()` which is automatically called when a `GameplayAbility` is granted and the `AvatarActor` is set and call `TryActivateAbility()`.

I recommend adding a `bool` to your custom `UGameplayAbility` class specifying if the `GameplayAbility` should be activated when granted. The Sample Project does this for its passive armor stacking ability.

Passive `GameplayAbilities` will typically have a [`Net Execution Policy`](#concepts-ga-net) of `Server Only`.

```c++
void UGDGameplayAbility::OnAvatarSet(const FGameplayAbilityActorInfo * ActorInfo, const FGameplayAbilitySpec & Spec)
{
	Super::OnAvatarSet(ActorInfo, Spec);

	if (bActivateAbilityOnGranted)
	{
		ActorInfo->AbilitySystemComponent->TryActivateAbility(Spec.Handle, false);
	}
}
```

Epic describes this function as the correct place to initiate passive abilities and to do `BeginPlay` type things.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-activating-failedtags"></a>
##### 4.6.4.2 Activation Failed Tags

Abilities have default logic to tell you why an ability activation failed. To enable this, you must set up the GameplayTags that correspond to the default failure cases.

Add these tags (or your own naming convention) to your project:
```
+GameplayTagList=(Tag="Activation.Fail.BlockedByTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.CantAffordCost",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.IsDead",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.MissingTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.Networking",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.OnCooldown",DevComment="")
```

Then add them to the [`GASDocumentation\Config\DefaultGame.ini`](https://github.com/tranek/GASDocumentation/blob/master/Config/DefaultGame.ini#L8-L13):
```
[/Script/GameplayAbilities.AbilitySystemGlobals]
ActivateFailIsDeadName=Activation.Fail.IsDead
ActivateFailCooldownName=Activation.Fail.OnCooldown
ActivateFailCostName=Activation.Fail.CantAffordCost
ActivateFailTagsBlockedName=Activation.Fail.BlockedByTags
ActivateFailTagsMissingName=Activation.Fail.MissingTags
ActivateFailNetworkingName=Activation.Fail.Networking
```

Now whenever an ability activation fails, this corresponding GameplayTag will be included in output log messages or visible on the `showdebug AbilitySystem` hud.
```
LogAbilitySystem: Display: InternalServerTryActivateAbility. Rejecting ClientActivation of Default__GA_FireGun_C. InternalTryActivateAbility failed: Activation.Fail.BlockedByTags
LogAbilitySystem: Display: ClientActivateAbilityFailed_Implementation. PredictionKey :109 Ability: Default__GA_FireGun_C
```

![Activation Failed Tags Displayed in showdebug AbilitySystem](https://github.com/tranek/GASDocumentation/raw/master/Images/activationfailedtags.png)

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
