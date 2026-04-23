# GA 취소 & 활성 GA 조회

> **GASDoc**: 4.6.5~6 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-cancelabilities"></a>
#### 4.6.5 Canceling Abilities
To cancel a `GameplayAbility` from within, you call `CancelAbility()`. This will call `EndAbility()` and set its `WasCancelled` parameter to true.

To cancel a `GameplayAbility` externally, the `ASC` provides a few functions:

```c++
/** Cancels the specified ability CDO. */
void CancelAbility(UGameplayAbility* Ability);	

/** Cancels the ability indicated by passed in spec handle. If handle is not found among reactivated abilities nothing happens. */
void CancelAbilityHandle(const FGameplayAbilitySpecHandle& AbilityHandle);

/** Cancel all abilities with the specified tags. Will not cancel the Ignore instance */
void CancelAbilities(const FGameplayTagContainer* WithTags=nullptr, const FGameplayTagContainer* WithoutTags=nullptr, UGameplayAbility* Ignore=nullptr);

/** Cancels all abilities regardless of tags. Will not cancel the ignore instance */
void CancelAllAbilities(UGameplayAbility* Ignore=nullptr);

/** Cancels all abilities and kills any remaining instanced abilities */
virtual void DestroyActiveState();
```

**Note:** I have found that `CancelAllAbilities` doesn't seem to work right if you have a `Non-Instanced` `GameplayAbilities`. It seems to hit the `Non-Instanced` `GameplayAbility` and give up. `CancelAbilities` can handle `Non-Instanced` `GameplayAbilities` better and that is what the Sample Project uses (Jump is a non-instanced `GameplayAbility`). Your mileage may vary.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-definition-activeability"></a>
#### 4.6.6 Getting Active Abilities
Beginners often ask "How can I get the active ability?" perhaps to set variables on it or to cancel it. More than one `GameplayAbility` can be active at a time so there is no one "active ability". Instead, you must search through an `ASC's` list of `ActivatableAbilities` (granted `GameplayAbilities` that the `ASC` owns) and find the one matching the [`Asset` or `Granted` `GameplayTag`](#concepts-ga-tags) that you are looking for.

`UAbilitySystemComponent::GetActivatableAbilities()` returns a `TArray<FGameplayAbilitySpec>` for you to iterate over.

The `ASC` also has another helper function that takes in a `GameplayTagContainer` as a parameter to assist in searching instead of manually iterating over the list of `GameplayAbilitySpecs`. The `bOnlyAbilitiesThatSatisfyTagRequirements` parameter will only return `GameplayAbilitySpecs` that satisfy their `GameplayTag` requirements and could be activated right now. For example, you could have two basic attack `GameplayAbilities`, one with a weapon and one with bare fists, and the correct one activates depending on if a weapon is equipped setting the `GameplayTag` requirement. See Epic's comment on the function for more information.
```c++
UAbilitySystemComponent::GetActivatableGameplayAbilitySpecsByAllMatchingTags(const FGameplayTagContainer& GameplayTagContainer, TArray < struct FGameplayAbilitySpec* >& MatchingGameplayAbilities, bool bOnlyAbilitiesThatSatisfyTagRequirements = true)
```

Once you get the `FGameplayAbilitySpec` that you are looking for, you can call `IsActive()` on it.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
