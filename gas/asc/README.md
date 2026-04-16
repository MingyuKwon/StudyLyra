# AbilitySystemComponent (ASC)

> 소스: `LyraAbilitySystemComponent.h/cpp`, `LyraPlayerState.h/cpp`, `LyraPawnExtensionComponent.h/cpp`

ASC는 GAS의 **허브 컴포넌트**다. Ability, Effect, Attribute, Tag, Cue 모두 ASC를 통해 관리된다.

---

## 문서 목록

| 문서 | 내용 |
|---|---|
| [01. Owner/Avatar 구조](01_owner_avatar.md) | Owner Actor vs Avatar Actor, Lyra에서의 PlayerState/Character 분리 |
| [02. 초기화 흐름](02_initialization.md) | InitAbilityActorInfo, PawnExtensionComponent 상태 머신 |
| [03. 입력 바인딩](03_input_binding.md) | InputTag → AbilitySpec → 활성화 전체 흐름 |
| [04. ActivationGroup](04_activation_group.md) | Independent/Exclusive_Replaceable/Exclusive_Blocking |
| [05. TagRelationshipMapping](05_tag_relationship.md) | → [GameplayTag 문서](../tag/README.md#tagrelationshipmapping) |

---

## ASC 클래스 계층

```
UActorComponent
    └── UAbilitySystemComponent  (엔진 기본)
            └── ULyraAbilitySystemComponent  (Lyra 확장)
```

## 핵심 확장 포인트 (Lyra 추가 기능)

```cpp
// 1. InputTag 기반 입력 처리
void AbilityInputTagPressed(const FGameplayTag& InputTag);
void AbilityInputTagReleased(const FGameplayTag& InputTag);
void ProcessAbilityInput(float DeltaTime, bool bGamePaused);

// 2. ActivationGroup 관리
bool IsActivationGroupBlocked(ELyraAbilityActivationGroup Group) const;
void AddAbilityToActivationGroup(ELyraAbilityActivationGroup Group, ULyraGameplayAbility* Ability);
void RemoveAbilityFromActivationGroup(ELyraAbilityActivationGroup Group, ULyraGameplayAbility* Ability);

// 3. TagRelationshipMapping 연동
void SetTagRelationshipMapping(ULyraAbilityTagRelationshipMapping* NewMapping);
void GetAdditionalActivationTagRequirements(...) const;

// 4. 동적 태그 GE 관리
void AddDynamicTagGameplayEffect(const FGameplayTag& Tag);
void RemoveDynamicTagGameplayEffect(const FGameplayTag& Tag);

// 5. GlobalAbilitySystem 등록
// → EndPlay: UnregisterASC(), InitAbilityActorInfo(new pawn): RegisterASC()
```
