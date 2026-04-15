# GameplayTag

> 참고: [GAS Doc 캐시](gas_doc_cache.md) | 소스: `LyraAbilityTagRelationshipMapping.h/cpp`, `LyraGameplayTags.h`

---

## 계층 구조

GameplayTag는 점(`.`)으로 구분되는 계층형 문자열 식별자다.

```
Ability.Attack.Melee
Ability.Attack.Ranged
Status.Death
Status.Debuff.Stun
Gameplay.AbilityInputBlocked
InitState.Spawned
InitState.DataAvailable
InitState.DataInitialized
InitState.GameplayReady
```

- `A.B.C`는 `A.B`의 자식
- `HasTag("A.B")`는 `"A.B.C"`를 **포함하지 않음** (Exact match)
- `HasTag` with `bExact=false`이면 부모 태그도 매칭됨

### FGameplayTag vs FGameplayTagContainer

```cpp
FGameplayTag SingleTag;       // 단일 태그
FGameplayTagContainer Tags;   // 태그 집합 (HasAny, HasAll, HasTag 등)
```

UFUNCTION 파라미터로는 `FGameplayTagContainer` 권장 (단일 태그도 컨테이너로 전달).

---

## GAS에서의 역할

### 1. GA 태그 (9가지 컨테이너)

| 컨테이너 이름 | 동작 |
|---|---|
| `AbilityTags` | 이 GA를 식별하는 태그 |
| `CancelAbilitiesWithTag` | 활성화 시 해당 태그 GA 취소 |
| `BlockAbilitiesWithTag` | 활성화 중 해당 태그 GA 차단 |
| `ActivationOwnedTags` | 활성화 중 소유자 ASC에 부여 (복제 안 됨) |
| `ActivationRequiredTags` | 소유자가 모두 가져야 활성화 가능 |
| `ActivationBlockedTags` | 소유자가 가지면 활성화 불가 |
| `SourceRequiredTags` | 이벤트 트리거 시 소스가 보유해야 함 |
| `SourceBlockedTags` | 이벤트 트리거 시 소스가 가지면 불가 |
| `TargetRequiredTags` | 이벤트 트리거 시 타겟이 보유해야 함 |

### 2. GE 태그 (7가지)

| 태그 유형 | 동작 |
|---|---|
| `Asset Tags` | GE 자체를 설명 |
| `Granted Tags` | GE 활성화 중 ASC에 자동 추가, 제거 시 자동 제거 |
| `Ongoing Required Tags` | 없으면 GE Inhibit (일시 비활성화) |
| `Ongoing Ignored Tags` | 있으면 GE Inhibit |
| `Application Required Tags` | 없으면 GE 적용 자체 불가 |
| `Application Ignored Tags` | 있으면 GE 적용 자체 불가 |
| `Remove GEs with Tags` | 이 GE 적용 시 해당 태그 가진 기존 GE 제거 |

### 3. 런타임 태그 조작

```cpp
// 복제 없음 — 서버+클라이언트 양쪽에서 호출해야 함
ASC->AddLooseGameplayTag(Tag);
ASC->RemoveLooseGameplayTag(Tag);

// 복제됨
ASC->AddReplicatedLooseGameplayTag(Tag);
ASC->RemoveReplicatedLooseGameplayTag(Tag);

// GE를 통한 태그 부여 (Lyra 방식)
ASC->AddDynamicTagGameplayEffect(Tag);    // DynamicTagGameplayEffect 사용
ASC->RemoveDynamicTagGameplayEffect(Tag);
```

Lyra에서는 `DynamicTagGameplayEffect`(설정에서 지정된 GE)를 통해 태그를 GE로 관리한다.

```cpp
// LyraAbilitySystemComponent.cpp
void ULyraAbilitySystemComponent::AddDynamicTagGameplayEffect(const FGameplayTag& Tag)
{
    const TSubclassOf<UGameplayEffect> DynamicTagGE =
        ULyraAssetManager::GetSubclass(ULyraGameData::Get().DynamicTagGameplayEffect);
    
    const FGameplayEffectSpecHandle SpecHandle = MakeOutgoingSpec(DynamicTagGE, 1.0f, MakeEffectContext());
    FGameplayEffectSpec* Spec = SpecHandle.Data.Get();
    Spec->DynamicGrantedTags.AddTag(Tag);
    ApplyGameplayEffectSpecToSelf(*Spec);
}
```

---

## Ability 활성화 조건 태그 — Lyra 확장

표준 GAS의 태그 조건 외에, Lyra는 `ULyraAbilityTagRelationshipMapping`으로
**데이터 기반 태그 관계**를 추가한다.

### DoesAbilitySatisfyTagRequirements 확장

`ULyraGameplayAbility::DoesAbilitySatisfyTagRequirements()`에서 기본 엔진 체크 외에:

```cpp
// TagRelationshipMapping에서 추가 required/blocked 태그를 가져와 합산
if (LyraASC)
{
    LyraASC->GetAdditionalActivationTagRequirements(GetAssetTags(), AllRequiredTags, AllBlockedTags);
}
```

사망 상태 특수 처리:
```cpp
if (AbilitySystemComponentTags.HasTag(LyraGameplayTags::Status_Death))
{
    OptionalRelevantTags->AddTag(LyraGameplayTags::Ability_ActivateFail_IsDead);
}
```

### Pawn 초기화 상태 태그

`LyraPawnExtensionComponent`가 사용하는 상태 태그:

```
InitState.Spawned
InitState.DataAvailable
InitState.DataInitialized
InitState.GameplayReady
```

---

## TagRelationshipMapping

> 소스: `LyraAbilityTagRelationshipMapping.h/cpp`

`ULyraAbilityTagRelationshipMapping`은 GA 태그 간의 차단/취소 관계를 데이터로 정의하는 DataAsset.
`ULyraPawnData`에 참조되어 Pawn 초기화 시 ASC에 설정된다.

### 구조

```cpp
USTRUCT()
struct FLyraAbilityTagRelationship
{
    FGameplayTag AbilityTag;              // 이 태그를 가진 GA에 대해
    FGameplayTagContainer AbilityTagsToBlock;    // 이 태그를 가진 다른 GA를 차단
    FGameplayTagContainer AbilityTagsToCancel;   // 이 태그를 가진 다른 GA를 취소
    FGameplayTagContainer ActivationRequiredTags; // 활성화에 추가로 필요한 태그
    FGameplayTagContainer ActivationBlockedTags;  // 활성화를 막는 추가 태그
};
```

### 동작 방식

```
GA 활성화 시도
    │
    ▼
ULyraAbilitySystemComponent::ApplyAbilityBlockAndCancelTags()
    │ TagRelationshipMapping->GetAbilityTagsToBlockAndCancel()
    │ → AbilityTag 기반으로 BlockTags/CancelTags 확장
    │
    ▼
ULyraGameplayAbility::DoesAbilitySatisfyTagRequirements()
    │ LyraASC->GetAdditionalActivationTagRequirements()
    │ → TagRelationshipMapping->GetRequiredAndBlockedActivationTags()
    │ → 추가 Required/Blocked 태그 확인
```

### 구현 (cpp)

```cpp
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
```

### ASC에 설정되는 시점

```cpp
// LyraPawnExtensionComponent::InitializeAbilitySystem() 에서
if (ensure(PawnData))
{
    InASC->SetTagRelationshipMapping(PawnData->TagRelationshipMapping);
}
```

`ULyraPawnData`의 `TagRelationshipMapping` 필드(DataAsset 참조)가 Pawn마다 다를 수 있어,
캐릭터 타입별 서로 다른 능력 관계를 설정할 수 있다.

---

## 디버깅

```
showdebug abilitysystem   ← 현재 ASC의 태그 목록 확인
AbilitySystem.Debug.NextCategory  ← 페이지 전환
```

게임플레이 디버거 (`'` 키):
- 숫자패드 3 → Ability 카테고리 → 현재 태그/GE/GA 상태 확인
