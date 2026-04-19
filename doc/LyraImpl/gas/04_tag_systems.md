# 태그 시스템 — TagRelationshipMapping / GlobalAbilitySystem

> 출처:  
> `Source/LyraGame/AbilitySystem/LyraAbilityTagRelationshipMapping.h`  
> `Source/LyraGame/AbilitySystem/LyraGlobalAbilitySystem.h`

---

## ULyraAbilityTagRelationshipMapping

### 존재 이유

기본 GAS에서는 어빌리티 간 차단/취소 관계를 **각 어빌리티 에셋 안에** 직접 태그로 설정한다. 게임이 복잡해지면 여러 어빌리티에 흩어진 관계를 추적하고 수정하기가 어려워진다.

Lyra는 이 관계를 **하나의 DataAsset으로 분리**했다.

```cpp
// LyraAbilityTagRelationshipMapping.h
struct FLyraAbilityTagRelationship
{
    FGameplayTag        AbilityTag;            // 이 태그를 가진 어빌리티에 적용
    FGameplayTagContainer AbilityTagsToBlock;  // 이 태그를 가진 어빌리티들을 차단
    FGameplayTagContainer AbilityTagsToCancel; // 이 태그를 가진 어빌리티들을 취소

    FGameplayTagContainer ActivationRequiredTags; // 활성화에 이 태그들이 필요
    FGameplayTagContainer ActivationBlockedTags;  // 이 태그들이 있으면 활성화 차단
};

UCLASS()
class ULyraAbilityTagRelationshipMapping : public UDataAsset
{
    UPROPERTY(EditAnywhere, meta=(TitleProperty="AbilityTag"))
    TArray<FLyraAbilityTagRelationship> AbilityTagRelationships;
};
```

### 연결 방법

`ULyraPawnData` 에셋에 지정 → 폰 빙의 시 해당 ASC에 자동 할당:

```
PawnData.TagRelationshipMapping
  → 폰 빙의 시 ULyraAbilitySystemComponent에 세팅
  → CanActivateAbility() / DoesAbilitySatisfyTagRequirements() 호출 시 적용
```

### API

```cpp
// 주어진 어빌리티 태그 집합에 대해 차단/취소할 태그 계산
void GetAbilityTagsToBlockAndCancel(
    const FGameplayTagContainer& AbilityTags,
    FGameplayTagContainer* OutTagsToBlock,
    FGameplayTagContainer* OutTagsToCancel) const;

// 활성화 필수/차단 태그 계산
void GetRequiredAndBlockedActivationTags(
    const FGameplayTagContainer& AbilityTags,
    FGameplayTagContainer* OutActivationRequired,
    FGameplayTagContainer* OutActivationBlocked) const;

// 특정 ActionTag가 이 어빌리티를 취소하는지 확인
bool IsAbilityCancelledByTag(
    const FGameplayTagContainer& AbilityTags,
    const FGameplayTag& ActionTag) const;
```

---

## ULyraGlobalAbilitySystem

### 역할

레벨의 **모든 `ULyraAbilitySystemComponent`를 추적**하고, 전체에 어빌리티/이펙트를 일괄 적용/제거한다.

```cpp
// LyraGlobalAbilitySystem.h
UCLASS()
class ULyraGlobalAbilitySystem : public UWorldSubsystem
{
    // 전역 적용된 어빌리티 목록: Class → (ASC → Handle)
    TMap<TSubclassOf<UGameplayAbility>, FGlobalAppliedAbilityList> AppliedAbilities;

    // 전역 적용된 이펙트 목록: Class → (ASC → Handle)
    TMap<TSubclassOf<UGameplayEffect>, FGlobalAppliedEffectList> AppliedEffects;

    // 등록된 모든 ASC
    TArray<TObjectPtr<ULyraAbilitySystemComponent>> RegisteredASCs;
};
```

### 자동 등록

`ULyraAbilitySystemComponent`는 초기화 중 자동으로 이 서브시스템에 등록/해제:

```cpp
// 초기화 시
ULyraGlobalAbilitySystem* GlobalASC = GetWorld()->GetSubsystem<ULyraGlobalAbilitySystem>();
GlobalASC->RegisterASC(this);

// 종료 시
GlobalASC->UnregisterASC(this);
```

등록 시점에 이미 전역 적용된 어빌리티/이펙트가 있다면, 새 ASC에 즉시 적용된다.

### API

```cpp
// 현재 + 이후 등록될 모든 ASC에 적용
void ApplyAbilityToAll(TSubclassOf<UGameplayAbility> Ability);
void ApplyEffectToAll(TSubclassOf<UGameplayEffect> Effect);

// 현재 등록된 모든 ASC에서 제거
void RemoveAbilityFromAll(TSubclassOf<UGameplayAbility> Ability);
void RemoveEffectFromAll(TSubclassOf<UGameplayEffect> Effect);
```

### 사용 예

웜업 페이즈 시작 시 모든 플레이어에게 대미지 면역 이펙트 적용:

```
Phase_Warmup 활성화
  → ApplyEffectToAll(GE_PregameLobby)
    → 모든 등록된 ASC에 대미지 면역 태그 부여
    → UI "매치 시작 전" 표시 Cue 트리거
Phase_Warmup 종료
  → RemoveEffectFromAll(GE_PregameLobby)
```
