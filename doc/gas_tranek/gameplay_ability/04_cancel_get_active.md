# GA 취소 & 활성 GA 조회

> **GASDoc**: 4.6.5~6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-cancelabilities"></a>
#### GA를 내부/외부에서 취소하는 방법과 Non-Instanced GA에서 CancelAllAbilities가 불안정한 이유는?

GA 내부에서 취소하려면 `CancelAbility()`를 호출한다. 이 함수는 `EndAbility()`를 호출하면서 `WasCancelled` 파라미터를 true로 설정한다.

외부에서 GA를 취소하려면 ASC의 다음 함수들을 사용한다:

```c++
void CancelAbility(UGameplayAbility* Ability);
void CancelAbilityHandle(const FGameplayAbilitySpecHandle& AbilityHandle);
void CancelAbilities(const FGameplayTagContainer* WithTags=nullptr, const FGameplayTagContainer* WithoutTags=nullptr, UGameplayAbility* Ignore=nullptr);
void CancelAllAbilities(UGameplayAbility* Ignore=nullptr);
virtual void DestroyActiveState();
```

`CancelAllAbilities()`는 Non-Instanced GA를 만나면 처리를 포기하는 것으로 확인된다. Non-Instanced GA가 포함된 경우 `CancelAbilities()`가 더 안정적이며, 샘플 프로젝트도 이 함수를 사용한다(Jump는 Non-Instanced GA다).

<a name="concepts-ga-definition-activeability"></a>
#### 현재 활성화된 GA를 어떻게 찾고, 단일한 "활성 GA" 개념이 없는 이유는 무엇인가?

동시에 여러 GA가 활성화될 수 있으므로 단일한 "활성 GA"라는 개념은 존재하지 않는다. 대신 ASC의 `ActivatableAbilities` 목록을 순회하면서 찾고자 하는 Asset 또는 Granted GameplayTag와 일치하는 항목을 탐색해야 한다.

`UAbilitySystemComponent::GetActivatableAbilities()`는 순회할 수 있는 `TArray<FGameplayAbilitySpec>`을 반환한다.

태그를 기준으로 검색할 때는 헬퍼 함수를 사용한다:

```c++
UAbilitySystemComponent::GetActivatableGameplayAbilitySpecsByAllMatchingTags(const FGameplayTagContainer& GameplayTagContainer, TArray<struct FGameplayAbilitySpec*>& MatchingGameplayAbilities, bool bOnlyAbilitiesThatSatisfyTagRequirements = true)
```

`bOnlyAbilitiesThatSatisfyTagRequirements`를 true로 설정하면 GameplayTag 요건을 충족하여 지금 당장 활성화 가능한 스펙만 반환한다. 무기 장착 여부에 따라 달라지는 두 가지 기본 공격 GA 중 올바른 것을 선택할 때 유용하다.

원하는 `FGameplayAbilitySpec`을 찾은 뒤 `IsActive()`를 호출해 현재 활성 상태인지 확인한다.

---
