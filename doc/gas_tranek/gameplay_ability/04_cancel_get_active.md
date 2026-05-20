# GA 취소 & 활성 GA 조회

> **GASDoc**: 4.6.5~6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-cancelabilities"></a>
#### GA를 내부/외부에서 취소하는 방법과 Non-Instanced GA에서 CancelAllAbilities가 불안정한 이유는?

GA 내부에서 취소하려면 `CancelAbility()`를 호출한다. 이 함수는 `EndAbility()`를 호출하면서 `WasCancelled` 파라미터를 true로 설정한다.

외부에서 GA를 취소하려면 ASC가 제공하는 다음 함수들을 사용한다:

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

> **참고**  
> `CancelAllAbilities()`는 Non-Instanced GA가 있을 경우 제대로 동작하지 않는 것으로 확인된다. Non-Instanced GA를 만나면 처리를 포기하는 것으로 보인다. Non-Instanced GA가 포함된 경우 `CancelAbilities()`가 더 안정적으로 처리하며, 샘플 프로젝트에서도 이 함수를 사용한다(Jump는 Non-Instanced GA이다). 실제 동작은 상황에 따라 다를 수 있다.

<a name="concepts-ga-definition-activeability"></a>
#### 현재 활성화된 GA를 어떻게 찾고, 단일한 "활성 GA" 개념이 없는 이유는 무엇인가?

입문자들은 종종 "활성 GA를 어떻게 가져오나요?"라고 질문한다 — 변수를 설정하거나 취소하기 위해서다. 동시에 여러 GA가 활성화될 수 있으므로 단일한 "활성 GA"라는 개념은 존재하지 않는다. 대신 ASC의 `ActivatableAbilities` 목록(ASC가 소유한 부여된 GA 목록)을 순회하면서 찾고자 하는 `Asset 또는 Granted GameplayTag`와 일치하는 항목을 직접 탐색해야 한다.

`UAbilitySystemComponent::GetActivatableAbilities()`는 순회할 수 있는 `TArray<FGameplayAbilitySpec>`을 반환한다.

ASC는 `GameplayAbilitySpec` 목록을 직접 순회하는 대신 `GameplayTagContainer`를 파라미터로 받아 검색을 도와주는 헬퍼 함수도 제공한다. `bOnlyAbilitiesThatSatisfyTagRequirements` 파라미터를 true로 설정하면 GameplayTag 요건을 충족하여 지금 당장 활성화 가능한 GameplayAbilitySpec만 반환한다. 예를 들어, 무기 장착 여부에 따라 GameplayTag 요건이 달라지는 두 가지 기본 공격 GA(무기 장착 버전, 맨손 버전)가 있을 때 올바른 것을 골라 활성화할 수 있다. 자세한 내용은 Epic의 함수 주석을 참조하라.
```c++
UAbilitySystemComponent::GetActivatableGameplayAbilitySpecsByAllMatchingTags(const FGameplayTagContainer& GameplayTagContainer, TArray < struct FGameplayAbilitySpec* >& MatchingGameplayAbilities, bool bOnlyAbilitiesThatSatisfyTagRequirements = true)
```

원하는 `FGameplayAbilitySpec`을 찾았다면 `IsActive()`를 호출하여 현재 활성 상태인지 확인할 수 있다.

---

