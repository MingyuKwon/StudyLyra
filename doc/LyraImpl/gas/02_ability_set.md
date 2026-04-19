# ULyraAbilitySet — 어빌리티 묶음 데이터에셋

> 출처: `Source/LyraGame/AbilitySystem/LyraAbilitySet.h/.cpp`

---

## 구조

`ULyraAbilitySet`은 `UPrimaryDataAsset`을 상속한 **불변 데이터에셋**이다. GA + GE + AttributeSet을 하나로 묶어 ASC에 일괄 부여/회수한다.

```cpp
// LyraAbilitySet.h
UCLASS(BlueprintType, Const)
class ULyraAbilitySet : public UPrimaryDataAsset
{
    UPROPERTY(EditDefaultsOnly, Category = "Gameplay Abilities")
    TArray<FLyraAbilitySet_GameplayAbility> GrantedGameplayAbilities;

    UPROPERTY(EditDefaultsOnly, Category = "Gameplay Effects")
    TArray<FLyraAbilitySet_GameplayEffect> GrantedGameplayEffects;

    UPROPERTY(EditDefaultsOnly, Category = "Attribute Sets")
    TArray<FLyraAbilitySet_AttributeSet> GrantedAttributes;

    void GiveToAbilitySystem(ULyraAbilitySystemComponent* LyraASC,
                             FLyraAbilitySet_GrantedHandles* OutGrantedHandles,
                             UObject* SourceObject = nullptr) const;
};
```

### 항목별 구조

```cpp
struct FLyraAbilitySet_GameplayAbility
{
    TSubclassOf<ULyraGameplayAbility> Ability;
    int32        AbilityLevel = 1;
    FGameplayTag InputTag;  // 이 태그 입력 시 어빌리티 활성화 시도
};

struct FLyraAbilitySet_GameplayEffect
{
    TSubclassOf<UGameplayEffect> GameplayEffect;
    float EffectLevel = 1.0f;
};

struct FLyraAbilitySet_AttributeSet
{
    TSubclassOf<UAttributeSet> AttributeSet;
};
```

---

## GiveToAbilitySystem — 실제 부여 로직

서버 권한 확인 후 AttributeSet → GA → GE 순서로 부여한다.

```cpp
// LyraAbilitySet.cpp
void ULyraAbilitySet::GiveToAbilitySystem(ULyraAbilitySystemComponent* LyraASC,
    FLyraAbilitySet_GrantedHandles* OutGrantedHandles, UObject* SourceObject) const
{
    // 서버(Authority) 에서만 부여 가능
    if (!LyraASC->IsOwnerActorAuthoritative()) return;

    // 1. AttributeSet 생성 및 등록
    for (const FLyraAbilitySet_AttributeSet& SetToGrant : GrantedAttributes)
    {
        UAttributeSet* NewSet = NewObject<UAttributeSet>(LyraASC->GetOwner(), SetToGrant.AttributeSet);
        LyraASC->AddAttributeSetSubobject(NewSet);
        if (OutGrantedHandles) OutGrantedHandles->AddAttributeSet(NewSet);
    }

    // 2. GameplayAbility 부여
    for (const FLyraAbilitySet_GameplayAbility& AbilityToGrant : GrantedGameplayAbilities)
    {
        ULyraGameplayAbility* AbilityCDO = AbilityToGrant.Ability->GetDefaultObject<ULyraGameplayAbility>();

        FGameplayAbilitySpec AbilitySpec(AbilityCDO, AbilityToGrant.AbilityLevel);
        AbilitySpec.SourceObject = SourceObject;
        // InputTag을 DynamicSpecSourceTags에 추가 → ASC가 입력 이벤트와 매칭
        AbilitySpec.GetDynamicSpecSourceTags().AddTag(AbilityToGrant.InputTag);

        const FGameplayAbilitySpecHandle Handle = LyraASC->GiveAbility(AbilitySpec);
        if (OutGrantedHandles) OutGrantedHandles->AddAbilitySpecHandle(Handle);
    }

    // 3. GameplayEffect 적용
    for (const FLyraAbilitySet_GameplayEffect& EffectToGrant : GrantedGameplayEffects)
    {
        const UGameplayEffect* GE = EffectToGrant.GameplayEffect->GetDefaultObject<UGameplayEffect>();
        const FActiveGameplayEffectHandle Handle =
            LyraASC->ApplyGameplayEffectToSelf(GE, EffectToGrant.EffectLevel, LyraASC->MakeEffectContext());
        if (OutGrantedHandles) OutGrantedHandles->AddGameplayEffectHandle(Handle);
    }
}
```

---

## FLyraAbilitySet_GrantedHandles — 부여 추적 핸들

부여한 쪽이 나중에 회수할 수 있도록 핸들을 보관한다.

```cpp
// LyraAbilitySet.h
struct FLyraAbilitySet_GrantedHandles
{
    TArray<FGameplayAbilitySpecHandle>  AbilitySpecHandles;
    TArray<FActiveGameplayEffectHandle> GameplayEffectHandles;
    TArray<TObjectPtr<UAttributeSet>>   GrantedAttributeSets;
};
```

회수 시 `TakeFromAbilitySystem()` 호출:

```cpp
// LyraAbilitySet.cpp
void FLyraAbilitySet_GrantedHandles::TakeFromAbilitySystem(ULyraAbilitySystemComponent* LyraASC)
{
    if (!LyraASC->IsOwnerActorAuthoritative()) return;

    for (const FGameplayAbilitySpecHandle& Handle : AbilitySpecHandles)
        LyraASC->ClearAbility(Handle);       // GA 즉시 제거

    for (const FActiveGameplayEffectHandle& Handle : GameplayEffectHandles)
        LyraASC->RemoveActiveGameplayEffect(Handle);

    for (UAttributeSet* Set : GrantedAttributeSets)
        LyraASC->RemoveSpawnedAttribute(Set);

    // 핸들 비우기
    AbilitySpecHandles.Reset();
    GameplayEffectHandles.Reset();
    GrantedAttributeSets.Reset();
}
```

---

## 3가지 부여 경로

### 1. PawnData → Experience (항상 부여)

```
ULyraPawnData.AbilitySets[]
  → Experience 로드 완료 → ULyraPlayerState::OnExperienceLoaded()
  → AbilitySet.GiveToAbilitySystem(PlayerState ASC, &GrantedHandles)
```

- **PlayerState ASC에 부여** — 폰이 바뀌어도 유지
- `ActivationPolicy = OnSpawn`이어도 폰이 빙의되기 전까지는 활성화 안 됨
- 점프, 달리기 같은 기본 이동 어빌리티

### 2. GameFeatureAction_AddAbilities (Experience/플러그인 활성화 시)

```cpp
// GameFeatureAction_AddAbilities.cpp
void UGameFeatureAction_AddAbilities::AddActorAbilities(AActor* Actor, ...)
{
    for (const TSoftObjectPtr<const ULyraAbilitySet>& SetPtr : Entry.GrantedAbilitySets)
    {
        const ULyraAbilitySet* Set = SetPtr.Get();
        // OutGrantedHandles에 핸들 저장 → 비활성화 시 회수에 사용
        Set->GiveToAbilitySystem(LyraASC,
            &AddedExtensions.AbilitySetHandles.AddDefaulted_GetRef());
    }
}
```

플러그인/Experience 비활성화 시 `TakeFromAbilitySystem()`으로 자동 회수:

```cpp
void UGameFeatureAction_AddAbilities::RemoveActorAbilities(AActor* Actor, ...)
{
    for (FLyraAbilitySet_GrantedHandles& SetHandle : ActorExtensions->AbilitySetHandles)
        SetHandle.TakeFromAbilitySystem(LyraASC);
}
```

### 3. Equipment (장비 장착 시)

```cpp
// LyraEquipmentManagerComponent.cpp
ULyraEquipmentInstance* ULyraEquipmentManagerComponent::EquipItem(
    TSubclassOf<ULyraEquipmentDefinition> EquipmentDefinition)
{
    for (const ULyraAbilitySet* AbilitySet : EquipmentDef->AbilitySetsToGrant)
    {
        AbilitySet->GiveToAbilitySystem(LyraASC, &EquipmentEntry.GrantedHandles);
    }
}

void ULyraEquipmentManagerComponent::UnequipItem(ULyraEquipmentInstance* ItemInstance)
{
    EquipmentEntry.GrantedHandles.TakeFromAbilitySystem(LyraASC);
}
```

- 장비 장착 시 부여, 해제 시 회수
- 무기 발사, 조준 등 장비별 고유 어빌리티
