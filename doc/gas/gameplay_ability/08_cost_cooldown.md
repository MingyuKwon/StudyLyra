# Cost & Cooldown

> **GASDoc**: 4.6.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-commit"></a>
#### 4.6.12 Ability Cost and Cooldown
`GameplayAbilities` come with functionality for optional costs and cooldowns. Costs are predefined amounts of `Attributes` that the `ASC` must have in order to activate the `GameplayAbility` implemented with an `Instant` `GameplayEffect` ([`Cost GE`](#concepts-ge-cost)). Cooldowns are timers that prevent the reactivation of a `GameplayAbility` until it expires and is implemented with a `Duration` `GameplayEffect` ([`Cooldown GE`](#concepts-ge-cooldown)).

Before a `GameplayAbility` calls `UGameplayAbility::Activate()`, it calls `UGameplayAbility::CanActivateAbility()`. This function checks if the owning `ASC` can afford the cost (`UGameplayAbility::CheckCost()`) and ensures that the `GameplayAbility` is not on cooldown (`UGameplayAbility::CheckCooldown()`).

After a `GameplayAbility` calls `Activate()`, it can optionally commit the cost and cooldown at any time using `UGameplayAbility::CommitAbility()` which calls `UGameplayAbility::CommitCost()` and `UGameplayAbility::CommitCooldown()`. The designer may choose to call `CommitCost()` or `CommitCooldown()` separately if they shouldn't be committed at the same time. Committing cost and cooldown calls `CheckCost()` and `CheckCooldown()` one more time and is the last chance for the `GameplayAbility` to fail related to them. The owning `ASC's` `Attributes` could potentially change after a `GameplayAbility` is activated, failing to meet the cost at time of commit. Committing the cost and cooldown can be [locally predicted](#concepts-p) if the [prediction key](#concepts-p-key) is valid at the time of commit.

See [`CostGE`](#concepts-ge-cost) and [`CooldownGE`](#concepts-ge-cooldown) for implementation details.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
