# 태그 시스템 — TagRelationshipMapping / GlobalAbilitySystem

> 출처:  
> `Source/LyraGame/AbilitySystem/LyraAbilityTagRelationshipMapping.h/.cpp`  
> `Source/LyraGame/AbilitySystem/LyraGlobalAbilitySystem.h/.cpp`

---

## ULyraAbilityTagRelationshipMapping

### 존재 이유

기본 GAS에서는 어빌리티 간 차단/취소 관계를 **각 어빌리티 에셋 안에** 직접 태그로 설정한다.  
게임이 복잡해지면 여러 어빌리티에 흩어진 관계를 추적하고 수정하기가 어려워진다.

| 방식 | 문제 |
|------|------|
| GA 직접 설정 (`BlockAbilitiesWithTag` 등) | GA 클래스 수정 필요. 블루프린트 GA는 더 번거로움 |
| **TagRelationshipMapping** | DataAsset만 수정. GA 수정 없이 규칙 교체 가능. PawnData마다 다른 규칙 적용 가능 |

```cpp
// LyraAbilityTagRelationshipMapping.h
struct FLyraAbilityTagRelationship
{
    FGameplayTag AbilityTag;                    // 이 태그를 가진 GA에 적용
    FGameplayTagContainer AbilityTagsToBlock;   // → 이 태그 가진 GA들을 차단
    FGameplayTagContainer AbilityTagsToCancel;  // → 이 태그 가진 GA들을 취소
    FGameplayTagContainer ActivationRequiredTags; // → ASC에 이 태그 있어야 활성화 가능
    FGameplayTagContainer ActivationBlockedTags;  // → ASC에 이 태그 있으면 활성화 차단
};
```

---

### 1단계 — ASC에 꽂히는 경로

```cpp
// LyraPawnExtensionComponent.cpp:146
// InitState: DataInitialized 전이 시 호출
void ULyraPawnExtensionComponent::InitializeAbilitySystem(...)
{
    InASC->InitAbilityActorInfo(InOwnerActor, Pawn);

    if (ensure(PawnData))
        InASC->SetTagRelationshipMapping(PawnData->TagRelationshipMapping);
        // → ASC.TagRelationshipMapping 멤버에 저장. 이후 두 훅에서 참조됨
}
```

---

### 2단계 — 훅 A: `CanActivateAbility` 체크 시 (활성화 전)

GA 활성화 시도 → `CanActivateAbility` → `DoesAbilitySatisfyTagRequirements` 에서 매핑 조회:

```cpp
// LyraGameplayAbility.cpp:316
bool ULyraGameplayAbility::DoesAbilitySatisfyTagRequirements(...) const
{
    AllRequiredTags = ActivationRequiredTags;  // GA 자체 설정값 복사
    AllBlockedTags  = ActivationBlockedTags;

    // 매핑에서 이 GA의 태그 기준으로 추가 조건 주입
    if (LyraASC)
        LyraASC->GetAdditionalActivationTagRequirements(GetAssetTags(), AllRequiredTags, AllBlockedTags);

    // ASC 현재 보유 태그와 대조
    AbilitySystemComponent.GetOwnedGameplayTags(AbilitySystemComponentTags);
    if (AbilitySystemComponentTags.HasAny(AllBlockedTags))   bBlocked = true;
    if (!AbilitySystemComponentTags.HasAll(AllRequiredTags)) bMissing = true;
    ...
}

// LyraAbilitySystemComponent.cpp:379
void ULyraAbilitySystemComponent::GetAdditionalActivationTagRequirements(...) const
{
    if (TagRelationshipMapping)
        TagRelationshipMapping->GetRequiredAndBlockedActivationTags(AbilityTags, &OutRequired, &OutBlocked);
}
```

---

### 3단계 — 훅 B: `PreActivate` / `EndAbility` 시 (Block/Cancel 실행)

GA가 실제 활성화되거나 종료될 때 엔진이 `ApplyAbilityBlockAndCancelTags`를 호출한다.  
Lyra ASC가 이를 오버라이드해 매핑 기반 태그를 합산한다:

```cpp
// 엔진 — PreActivate() 내 (GameplayAbility.cpp:992)
Comp->ApplyAbilityBlockAndCancelTags(GetAssetTags(), this,
    true, BlockAbilitiesWithTag,   // bEnable=true → Block ON
    true, CancelAbilitiesWithTag); // bExecute=true → 취소 실행

// 엔진 — EndAbility() 내 (GameplayAbility.cpp:888)
Comp->ApplyAbilityBlockAndCancelTags(GetAssetTags(), this,
    false, BlockAbilitiesWithTag,  // bEnable=false → Block OFF
    false, CancelAbilitiesWithTag); // bExecute=false → 취소 안 함
```

```cpp
// LyraAbilitySystemComponent.cpp:356 — 오버라이드
void ULyraAbilitySystemComponent::ApplyAbilityBlockAndCancelTags(
    const FGameplayTagContainer& AbilityTags, ...,
    const FGameplayTagContainer& BlockTags,
    const FGameplayTagContainer& CancelTags)
{
    FGameplayTagContainer ModifiedBlockTags  = BlockTags;   // GA 직접 설정값 복사
    FGameplayTagContainer ModifiedCancelTags = CancelTags;

    if (TagRelationshipMapping)
    {
        // GA의 AbilityTag 기준으로 매핑 조회 → BlockTags / CancelTags 확장
        TagRelationshipMapping->GetAbilityTagsToBlockAndCancel(
            AbilityTags, &ModifiedBlockTags, &ModifiedCancelTags);
    }

    // 합산된 태그로 실제 Block/Cancel 실행
    Super::ApplyAbilityBlockAndCancelTags(..., ModifiedBlockTags, ..., ModifiedCancelTags);
    // Super: BlockAbilitiesWithTags(카운터+1) + CancelAbilities(강제종료)
}
```

---

### 전체 흐름 요약

```
[PawnData DataAsset]
    TagRelationshipMapping ──── SetTagRelationshipMapping() ──▶ ASC.TagRelationshipMapping

──── GA 활성화 시도 ────────────────────────────────────────────────────
TryActivateAbility()
  → CanActivateAbility()
      → DoesAbilitySatisfyTagRequirements()       [훅 A]
            GetAdditionalActivationTagRequirements()
              → Mapping.GetRequiredAndBlockedActivationTags()
                  GA AbilityTag 기준 조회
                  → ActivationRequiredTags / ActivationBlockedTags 주입
            ASC 보유 태그 대조 → 통과 or 거부

──── GA 활성화 확정 ────────────────────────────────────────────────────
PreActivate()
  → ApplyAbilityBlockAndCancelTags(bEnable=true, bCancel=true)  [훅 B]
        Mapping.GetAbilityTagsToBlockAndCancel()
          → BlockTags 확장, CancelTags 확장
        Super() → BlockAbilitiesWithTags(+1) + CancelAbilities()

──── GA 종료 ────────────────────────────────────────────────────────────
EndAbility()
  → ApplyAbilityBlockAndCancelTags(bEnable=false, bCancel=false)
        Mapping.GetAbilityTagsToBlockAndCancel()  ← 동일 매핑 재조회
        Super() → UnBlockAbilitiesWithTags(-1)     ← 차단 해제만, 취소 없음
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
