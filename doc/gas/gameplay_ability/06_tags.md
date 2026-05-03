# Ability Tags

> **GASDoc**: 4.6.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-tags"></a>
#### 4.6.9 Ability Tags

`GameplayAbility`에는 내장 로직을 가진 `GameplayTagContainer`가 여러 개 포함되어 있다. 이 `GameplayTag`들은 복제되지 않는다.

| `GameplayTag Container`     | 설명                                                                                                                                                                                                                              |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Ability Tags`              | `GameplayAbility`가 소유하는 `GameplayTag`. 해당 GameplayAbility를 설명하는 용도의 태그다.                                                                                                                                        |
| `Cancel Abilities with Tag` | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화될 때 취소된다.                                                                                                                              |
| `Block Abilities with Tag`  | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화 중인 동안 활성화가 차단된다.                                                                                                                |
| `Activation Owned Tags`     | 이 `GameplayAbility`가 활성화 중인 동안, 해당 GameplayAbility의 Owner에게 부여되는 `GameplayTag`. 이 태그들은 복제되지 않는다는 점에 유의할 것.                                                                                    |
| `Activation Required Tags`  | Owner가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다.                                                                                                                                             |
| `Activation Blocked Tags`   | Owner가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다.                                                                                                                                           |
| `Source Required Tags`      | `Source`가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Source Blocked Tags`       | `Source`가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |
| `Target Required Tags`      | `Target`이 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Target Blocked Tags`       | `Target`이 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |

---

## 내 분석

### Source / Owner / Target이 가리키는 대상

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`  
**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/GameplayAbility.cpp`

`InternalTryActivateAbility` 내부의 이 한 줄이 전부를 설명한다.

```cpp
// AbilitySystemComponent_Abilities.cpp
const FGameplayTagContainer* SourceTags = TriggerEventData ? &TriggerEventData->InstigatorTags : nullptr;
const FGameplayTagContainer* TargetTags = TriggerEventData ? &TriggerEventData->TargetTags : nullptr;
```

| 용어 | 실제 데이터 | 설명 |
|---|---|---|
| **Owner** | `ASC->GetOwnedGameplayTags()` | GA를 소유한 ASC의 현재 태그 집합 (캐릭터 자신의 상태) |
| **Source** | `FGameplayEventData::InstigatorTags` | 이벤트를 보낸 쪽의 태그 |
| **Target** | `FGameplayEventData::TargetTags` | 이벤트의 대상 쪽 태그 |

`DoesAbilitySatisfyTagRequirements` 내부에서 각각 다른 컨테이너를 검사한다:

```cpp
// Owner 태그 검사 (항상 실행)
CheckForBlocked(AbilitySystemComponent.GetOwnedGameplayTags(), ActivationBlockedTags);
CheckForRequired(AbilitySystemComponent.GetOwnedGameplayTags(), ActivationRequiredTags);

// Source 태그 검사 (SourceTags != nullptr일 때만)
if (SourceTags != nullptr)
{
    CheckForBlocked(*SourceTags, SourceBlockedTags);
    CheckForRequired(*SourceTags, SourceRequiredTags);
}

// Target 태그 검사 (TargetTags != nullptr일 때만)
if (TargetTags != nullptr)
{
    CheckForBlocked(*TargetTags, TargetBlockedTags);
    CheckForRequired(*TargetTags, TargetRequiredTags);
}
```

---

### 핵심: Source/Target은 이벤트 트리거 시에만 존재

GA를 직접 활성화(`TryActivateAbility`)하면 `TriggerEventData`가 `nullptr` → `SourceTags`, `TargetTags` 모두 `nullptr` → **Source/Target Required/Blocked Tags 검사 자체가 생략된다.**

`SendGameplayEventToActor` 등으로 이벤트를 통해 트리거될 때만 `FGameplayEventData`가 채워지고, 비로소 Source/Target 태그 검사가 활성화된다. 문서의 "이벤트로 트리거된 경우에만 설정된다"는 이 코드 경로를 가리킨다.

---

### 용도 정리

| 태그 컨테이너 | 검사 대상 | 언제 쓰는가 |
|---|---|---|
| `ActivationRequired/BlockedTags` | Owner (자신) | 내가 특정 상태일 때만 발동 가능 |
| `SourceRequired/BlockedTags` | Source (이벤트 발신자) | 특정 GA나 무기가 보낸 이벤트일 때만 반응 |
| `TargetRequired/BlockedTags` | Target (이벤트 대상) | 대상이 기절 상태일 때만 처형기 발동 등 |
