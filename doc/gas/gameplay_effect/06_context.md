# Gameplay Effect Context

> **GASDoc**: 4.5.10 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-context"></a>
#### 4.5.10 Gameplay Effect Context
The [`GameplayEffectContext`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayEffectContext/index.html) structure holds information about a `GameplayEffectSpec's` instigator and [`TargetData`](#concepts-targeting-data). This is also a good structure to subclass to pass arbitrary data around between places like [`ModifierMagnitudeCalculations`](#concepts-ge-mmc) / [`GameplayEffectExecutionCalculations`](#concepts-ge-ec), [`AttributeSets`](#concepts-as), and [`GameplayCues`](#concepts-gc).

To subclass the `GameplayEffectContext`:

1. Subclass `FGameplayEffectContext`
1. Override `FGameplayEffectContext::GetScriptStruct()`
1. Override `FGameplayEffectContext::Duplicate()`
1. Override `FGameplayEffectContext::NetSerialize()` if your new data needs to be replicated
1. Implement `TStructOpsTypeTraits` for your subclass, like the parent struct `FGameplayEffectContext` has
1. Override `AllocGameplayEffectContext()` in your [`AbilitySystemGlobals`](#concepts-asg) class to return a new object of your subclass

[GASShooter](https://github.com/tranek/GASShooter) uses a subclassed `GameplayEffectContext` to add `TargetData` which can be accessed in `GameplayCues`, specifically for the shotgun since it can hit more than one enemy.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
