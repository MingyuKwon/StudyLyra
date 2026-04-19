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
    int32  AbilityLevel = 1;
    FGameplayTag InputTag;   // 입력 태그 연결 — 이 태그가 눌리면 어빌리티 활성화 시도
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

## FLyraAbilitySet_GrantedHandles — 부여 추적 핸들

AbilitySet을 부여한 쪽이 나중에 회수할 수 있도록 핸들을 보관한다.

```cpp
struct FLyraAbilitySet_GrantedHandles
{
    TArray<FGameplayAbilitySpecHandle>  AbilitySpecHandles;
    TArray<FActiveGameplayEffectHandle> GameplayEffectHandles;
    TArray<TObjectPtr<UAttributeSet>>   GrantedAttributeSets;

    void TakeFromAbilitySystem(ULyraAbilitySystemComponent* LyraASC);
    // → ASC->SetRemoveAbilityOnEnd(Handle)  — 실행 중인 GA는 종료 후 제거
    // → ASC->RemoveActiveGameplayEffect(Handle)
    // → ASC->RemoveSpawnedAttribute(Set)
};
```

부여한 쪽(GameFeatureAction, EquipmentManager 등)이 이 핸들을 들고 있다가, 비활성화 시점에 `TakeFromAbilitySystem()`을 호출해 일괄 회수한다.

---

## 3가지 부여 경로

### 1. PawnData → Experience (항상 부여)

```
ULyraPawnData.AbilitySets[]
  → Experience 로드 시 ULyraPlayerState::OnExperienceLoaded()
  → AbilitySet.GiveToAbilitySystem(PlayerState ASC)
```

- **PlayerState ASC에 부여** — 폰이 바뀌어도 유지
- `ActivationPolicy = OnSpawn`이어도, 폰이 빙의되기 전까지는 활성화 안 됨
- 점프, 달리기 같은 기본 이동 어빌리티

### 2. GameFeatureAction_AddAbilities (Experience/플러그인 활성화 시)

```cpp
// GameFeatureAction_AddAbilities.cpp
void AddActorAbilities(AActor* Actor, ...)
{
    for (const TSoftObjectPtr<const ULyraAbilitySet>& SetPtr : Entry.GrantedAbilitySets)
    {
        const ULyraAbilitySet* Set = SetPtr.Get();
        Set->GiveToAbilitySystem(LyraASC,
            &AddedExtensions.AbilitySetHandles.AddDefaulted_GetRef());
    }
}
```

- Experience 또는 GameFeature 플러그인에 선언
- 플러그인/Experience 비활성화 시 `TakeFromAbilitySystem()`으로 자동 회수

### 3. Equipment (장비 장착 시)

```cpp
// LyraEquipmentManagerComponent.cpp
FLyraEquipmentActorToSpawn EquipItem(...)
{
    for (const ULyraAbilitySet* AbilitySet : EquipmentDefinition->AbilitySetsToGrant)
    {
        AbilitySet->GiveToAbilitySystem(LyraASC,
            &EquipmentEntry.GrantedHandles);
    }
}
```

- 장비 장착 시 부여, 해제 시 `TakeFromAbilitySystem()`으로 회수
- 무기 발사, 조준 등 장비별 고유 어빌리티
