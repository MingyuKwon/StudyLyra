# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-definition"></a>
#### 4.3.1 Attribute Definition
`Attributes` are float values defined by the struct [`FGameplayAttributeData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayAttributeData/index.html). These can represent anything from the amount of health a character has to the character's level to the number of charges that a potion has. If it is a gameplay-related numerical value belonging to an `Actor`, you should consider using an `Attribute` for it. `Attributes` should generally only be modified by [`GameplayEffects`](#concepts-ge) so that the ASC can [predict](#concepts-p) the changes.

`Attributes` are defined by and live in an [`AttributeSet`](#concepts-as). The `AttributeSet` is responsible for replicating `Attributes` that are marked for replication. See the section on [`AttributeSets`](#concepts-as) for how to define `Attributes`.

**Tip:** If you don't want an `Attribute` to show up in the Editor's list of `Attributes`, you can use the `Meta = (HideInDetailsView)` `property specifier`.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
