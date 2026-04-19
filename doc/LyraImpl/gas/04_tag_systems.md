# 태그 시스템 — TagRelationshipMapping / GlobalAbilitySystem

> 출처:  
> `Source/LyraGame/AbilitySystem/LyraAbilityTagRelationshipMapping.h/.cpp`  
> `Source/LyraGame/AbilitySystem/LyraGlobalAbilitySystem.h/.cpp`

---

## ULyraAbilityTagRelationshipMapping

### 존재 이유

기본 GAS에서는 어빌리티 간 차단/취소 관계를 **각 어빌리티 에셋 안에** 직접 태그로 설정한다. 게임이 복잡해지면 여러 어빌리티에 흩어진 관계를 추적하고 수정하기가 어려워진다.

Lyra는 이 관계를 **하나의 DataAsset으로 분리**해서 중앙 관리한다.

```cpp
// LyraAbilityTagRelationshipMapping.h
struct FLyraAbilityTagRelationship
{
    FGameplayTag AbilityTag;               // 이 태그를 가진 어빌리티에 적용

    FGameplayTagContainer AbilityTagsToBlock;   // 이 태그를 가진 어빌리티들을 차단
    FGameplayTagContainer AbilityTagsToCancel;  // 이 태그를 가진 어빌리티들을 취소

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

### 실제 조회 로직

```cpp
// LyraAbilityTagRelationshipMapping.cpp

// 이 어빌리티 태그들이 있을 때 차단/취소할 태그 계산
void ULyraAbilityTagRelationshipMapping::GetAbilityTagsToBlockAndCancel(
    const FGameplayTagContainer& AbilityTags,
    FGameplayTagContainer* OutTagsToBlock,
    FGameplayTagContainer* OutTagsToCancel) const
{
    for (const FLyraAbilityTagRelationship& Tags : AbilityTagRelationships)
    {
        if (AbilityTags.HasTag(Tags.AbilityTag))
        {
            if (OutTagsToBlock)  OutTagsToBlock->AppendTags(Tags.AbilityTagsToBlock);
            if (OutTagsToCancel) OutTagsToCancel->AppendTags(Tags.AbilityTagsToCancel);
        }
    }
}

// 이 어빌리티 태그들에 대한 활성화 필수/차단 태그 계산
void ULyraAbilityTagRelationshipMapping::GetRequiredAndBlockedActivationTags(
    const FGameplayTagContainer& AbilityTags,
    FGameplayTagContainer* OutActivationRequired,
    FGameplayTagContainer* OutActivationBlocked) const
{
    for (const FLyraAbilityTagRelationship& Tags : AbilityTagRelationships)
    {
        if (AbilityTags.HasTag(Tags.AbilityTag))
        {
            if (OutActivationRequired) OutActivationRequired->AppendTags(Tags.ActivationRequiredTags);
            if (OutActivationBlocked)  OutActivationBlocked->AppendTags(Tags.ActivationBlockedTags);
        }
    }
}

// ActionTag가 이 어빌리티를 취소하는지 확인
bool ULyraAbilityTagRelationshipMapping::IsAbilityCancelledByTag(
    const FGameplayTagContainer& AbilityTags, const FGameplayTag& ActionTag) const
{
    for (const FLyraAbilityTagRelationship& Tags : AbilityTagRelationships)
    {
        if (Tags.AbilityTag == ActionTag && Tags.AbilityTagsToCancel.HasAny(AbilityTags))
            return true;
    }
    return false;
}
```

### ASC에서 호출하는 시점

`DoesAbilitySatisfyTagRequirements()`에서 Mapping을 통해 추가 태그 요구사항을 확장한다:

```cpp
// LyraGameplayAbility.cpp
bool ULyraGameplayAbility::DoesAbilitySatisfyTagRequirements(...) const
{
    static FGameplayTagContainer AllRequiredTags = ActivationRequiredTags;
    static FGameplayTagContainer AllBlockedTags  = ActivationBlockedTags;

    // Mapping에서 추가 필수/차단 태그를 가져와 확장
    if (LyraASC)
        LyraASC->GetAdditionalActivationTagRequirements(GetAssetTags(), AllRequiredTags, AllBlockedTags);

    // 확장된 태그로 검사
    if (AbilitySystemComponentTags.HasAny(AllBlockedTags))  bBlocked = true;
    if (!AbilitySystemComponentTags.HasAll(AllRequiredTags)) bMissing = true;
    ...
}
```

### 연결 방법

`ULyraPawnData` 에셋에 지정 → 폰 빙의 시 해당 ASC에 자동 세팅:

```
PawnData.TagRelationshipMapping (DataAsset 레퍼런스)
  → 폰 빙의 시 ULyraAbilitySystemComponent에 세팅
  → CanActivateAbility() 호출 시마다 적용
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
    // Class → (ASC → Handle) 맵 — 어떤 ASC에 어떤 어빌리티를 부여했는지 추적
    TMap<TSubclassOf<UGameplayAbility>, FGlobalAppliedAbilityList> AppliedAbilities;
    TMap<TSubclassOf<UGameplayEffect>,  FGlobalAppliedEffectList>  AppliedEffects;

    TArray<TObjectPtr<ULyraAbilitySystemComponent>> RegisteredASCs;
};
```

### 자동 등록 — RegisterASC

새 ASC가 등록될 때 **이미 전역 적용된 어빌리티/이펙트를 즉시 적용**한다:

```cpp
// LyraGlobalAbilitySystem.cpp
void ULyraGlobalAbilitySystem::RegisterASC(ULyraAbilitySystemComponent* ASC)
{
    // 이미 전역 적용된 항목을 새 ASC에 즉시 부여
    for (auto& Entry : AppliedAbilities)
        Entry.Value.AddToASC(Entry.Key, ASC);
    for (auto& Entry : AppliedEffects)
        Entry.Value.AddToASC(Entry.Key, ASC);

    RegisteredASCs.AddUnique(ASC);
}

void ULyraGlobalAbilitySystem::UnregisterASC(ULyraAbilitySystemComponent* ASC)
{
    // 이 ASC에서 전역 적용된 항목 모두 제거
    for (auto& Entry : AppliedAbilities)
        Entry.Value.RemoveFromASC(ASC);
    for (auto& Entry : AppliedEffects)
        Entry.Value.RemoveFromASC(ASC);

    RegisteredASCs.Remove(ASC);
}
```

### 전역 적용 로직

```cpp
// LyraGlobalAbilitySystem.cpp
void ULyraGlobalAbilitySystem::ApplyEffectToAll(TSubclassOf<UGameplayEffect> Effect)
{
    if (Effect && !AppliedEffects.Contains(Effect))
    {
        FGlobalAppliedEffectList& Entry = AppliedEffects.Add(Effect);
        // 현재 등록된 모든 ASC에 즉시 적용
        for (ULyraAbilitySystemComponent* ASC : RegisteredASCs)
            Entry.AddToASC(Effect, ASC);
    }
}

// FGlobalAppliedEffectList::AddToASC
void FGlobalAppliedEffectList::AddToASC(TSubclassOf<UGameplayEffect> Effect, ULyraAbilitySystemComponent* ASC)
{
    const UGameplayEffect* GE_CDO = Effect->GetDefaultObject<UGameplayEffect>();
    const FActiveGameplayEffectHandle Handle =
        ASC->ApplyGameplayEffectToSelf(GE_CDO, /*Level=*/1, ASC->MakeEffectContext());
    Handles.Add(ASC, Handle);  // ASC → Handle 저장 (나중에 제거용)
}
```

### 사용 예 — 웜업 페이즈 전역 대미지 면역

```
Phase_Warmup 활성화
  → ULyraGlobalAbilitySystem::ApplyEffectToAll(GE_PregameLobby)
    → 현재 등록된 모든 플레이어 ASC에 대미지 면역 태그 부여
    → 이후 접속하는 플레이어도 RegisterASC() 시점에 자동 적용

Phase_Warmup 종료
  → RemoveEffectFromAll(GE_PregameLobby)
    → 모든 ASC에서 대미지 면역 제거
```
