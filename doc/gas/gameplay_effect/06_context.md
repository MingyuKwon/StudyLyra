# Gameplay Effect Context

> **GASDoc**: 4.5.10 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-context"></a>
#### 4.5.10 Gameplay Effect Context

[`GameplayEffectContext`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayEffectContext/index.html) 구조체는 `GameplayEffectSpec`의 인스티게이터(instigator)와 [`TargetData`](#concepts-targeting-data) 정보를 보유한다. 또한 [`ModifierMagnitudeCalculations`](#concepts-ge-mmc) / [`GameplayEffectExecutionCalculations`](#concepts-ge-ec), [`AttributeSets`](#concepts-as), [`GameplayCues`](#concepts-gc) 등 여러 곳에 임의의 데이터를 전달할 때 서브클래싱하기 좋은 구조체이기도 하다.

`GameplayEffectContext`를 서브클래싱하는 방법:

1. `FGameplayEffectContext`를 서브클래스로 만든다
1. `FGameplayEffectContext::GetScriptStruct()`를 오버라이드한다
1. `FGameplayEffectContext::Duplicate()`를 오버라이드한다
1. 새로 추가한 데이터를 복제해야 한다면 `FGameplayEffectContext::NetSerialize()`를 오버라이드한다
1. 부모 구조체 `FGameplayEffectContext`와 마찬가지로 서브클래스에 대해 `TStructOpsTypeTraits`를 구현한다
1. [`AbilitySystemGlobals`](#concepts-asg) 클래스에서 `AllocGameplayEffectContext()`를 오버라이드하여 서브클래스 객체를 반환하도록 한다

[GASShooter](https://github.com/tranek/GASShooter)는 서브클래싱된 `GameplayEffectContext`를 사용해 `TargetData`를 추가한다. 이 `TargetData`는 `GameplayCues`에서 접근할 수 있으며, 특히 여러 적을 동시에 맞힐 수 있는 샷건에서 활용된다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
