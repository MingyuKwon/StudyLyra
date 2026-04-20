# 태그 기반 어빌리티 차단/취소 플로우

> 관련: [태그 조건 (9가지)](05_tag_conditions.md)  
> 소스: `AbilitySystemComponent_Abilities.cpp`, `LyraAbilitySystemComponent.cpp`, `GameplayAbility.cpp`

---

## 두 가지 메커니즘

GAS에서 "태그로 GA를 막는다"는 말은 목적이 다른 두 메커니즘을 가리킨다.

| 메커니즘 | 대상 | 방식 |
|----------|------|------|
| `BlockedAbilityTags` | **아직 시작 안 한** GA | 카운터 기반 — 새 활성화 시도 거부 |
| `CancelAbilities()` | **이미 실행 중인** GA | 즉시 강제 종료 |

---

## 메커니즘 1 — BlockedAbilityTags (신규 활성화 차단)

```cpp
// ASC 멤버
FGameplayTagCountContainer BlockedAbilityTags;  // 태그별 참조 카운터

void BlockAbilitiesWithTags(const FGameplayTagContainer& Tags)
{
    BlockedAbilityTags.UpdateTagCount(Tags, +1);  // 카운터 증가
}
void UnBlockAbilitiesWithTags(const FGameplayTagContainer& Tags)
{
    BlockedAbilityTags.UpdateTagCount(Tags, -1);  // 카운터 감소
}

bool AreAbilityTagsBlocked(const FGameplayTagContainer& Tags) const
{
    return Tags.HasAny(BlockedAbilityTags.GetExplicitGameplayTags());
    // GA의 AbilityTags 중 하나라도 차단 목록에 있으면 true
}
```

`CanActivateAbility()` → `DoesAbilitySatisfyTagRequirements()` 에서 맨 먼저 체크된다:

```cpp
// LyraGameplayAbility.cpp
if (AbilitySystemComponent.AreAbilityTagsBlocked(GetAssetTags()))
    bBlocked = true;
```

---

## 메커니즘 2 — CancelAbilities (실행 중 GA 강제 종료)

```cpp
void CancelAbilities(const FGameplayTagContainer* WithTags, ...)
{
    for (const FGameplayAbilitySpec& Spec : ActivatableAbilities)
    {
        if (Spec.Ability->AbilityTags.HasAny(*WithTags))
            CancelAbilitySpec(Spec, ...);
    }
}

void CancelAbilitySpec(FGameplayAbilitySpec& Spec, ...)
{
    // 현재 활성화된 인스턴스에만 CancelAbility() 호출
    for (UGameplayAbility* Instance : Spec.GetAbilityInstances())
        Instance->CancelAbility(...);
}
```

카운터 개념이 없다. 한 번 호출하면 즉시 종료.

---

## 두 메커니즘이 합쳐지는 지점 — ApplyAbilityBlockAndCancelTags

GA가 활성화/종료될 때 엔진이 이 함수를 호출한다.

```
PreActivate()  →  ApplyAbilityBlockAndCancelTags(bEnable=true,  bCancel=true)
EndAbility()   →  ApplyAbilityBlockAndCancelTags(bEnable=false, bCancel=false)
```

```cpp
// GameplayAbility.cpp — 엔진 기본 구현
void ApplyAbilityBlockAndCancelTags(
    const FGameplayTagContainer& AbilityTags,
    bool bEnableBlockTags,   const FGameplayTagContainer& BlockAbilitiesWithTag,
    bool bExecuteCancelTags, const FGameplayTagContainer& CancelAbilitiesWithTag)
{
    if (bEnableBlockTags)
        BlockAbilitiesWithTags(BlockAbilitiesWithTag);    // 카운터 +1
    else
        UnBlockAbilitiesWithTags(BlockAbilitiesWithTag);  // 카운터 -1

    if (bExecuteCancelTags)
        CancelAbilities(&CancelAbilitiesWithTag, nullptr, RequestingAbility);
    // EndAbility 시 bExecuteCancelTags=false → 취소 없음, 차단만 해제
}
```

**Lyra ASC는 이를 오버라이드해 TagRelationshipMapping을 끼워 넣는다:**

```cpp
// LyraAbilitySystemComponent.cpp:356
void ULyraAbilitySystemComponent::ApplyAbilityBlockAndCancelTags(...)
{
    FGameplayTagContainer ModifiedBlockTags  = BlockTags;   // GA 직접 설정값 복사
    FGameplayTagContainer ModifiedCancelTags = CancelTags;

    if (TagRelationshipMapping)
        TagRelationshipMapping->GetAbilityTagsToBlockAndCancel(
            AbilityTags, &ModifiedBlockTags, &ModifiedCancelTags);
    // Mapping이 BlockTags / CancelTags를 확장

    Super::ApplyAbilityBlockAndCancelTags(..., ModifiedBlockTags, ..., ModifiedCancelTags);
}
```

---

## 전체 생애주기 플로우

```
TryActivateAbility("근접공격 GA")
  │
  ├─ CanActivateAbility()
  │     └─ DoesAbilitySatisfyTagRequirements()
  │           ├─ AreAbilityTagsBlocked(AbilityTags)         ← BlockedAbilityTags 체크
  │           ├─ GetAdditionalActivationTagRequirements()   ← Mapping에서 Required/Blocked 주입
  │           └─ ASC 보유 태그 vs AllBlockedTags / AllRequiredTags → 통과 or 거부
  │
  ├─ PreActivate()
  │     └─ ApplyAbilityBlockAndCancelTags(bEnable=true, bCancel=true)
  │           ├─ [Lyra] Mapping.GetAbilityTagsToBlockAndCancel() → BlockTags/CancelTags 확장
  │           ├─ BlockAbilitiesWithTags(BlockTags)           ← 카운터 +1 (신규 GA 차단)
  │           └─ CancelAbilities(CancelTags)                 ← 실행 중인 GA 즉시 종료
  │
  ├─ ActivateAbility() 실행 중...
  │     └─ ActivationOwnedTags → ASC에 추가 (복제 안 됨)
  │          다른 GA들의 ActivationBlockedTags와 대조 → 차단 유발 가능
  │
  └─ EndAbility()
        └─ ApplyAbilityBlockAndCancelTags(bEnable=false, bCancel=false)
              ├─ [Lyra] Mapping.GetAbilityTagsToBlockAndCancel() ← 동일 매핑 재조회
              ├─ UnBlockAbilitiesWithTags(BlockTags)          ← 카운터 -1 (차단 해제)
              └─ (취소 없음 — bCancel=false)
```

---

## 태그 소스 3가지

어빌리티가 막히거나 취소되는 원인은 세 군데다.

| 소스 | 방식 | 예시 |
|------|------|------|
| **GA 직접 설정** | `BlockAbilitiesWithTag`, `CancelAbilitiesWithTag` | 근접 공격 GA가 다른 공격 GA 차단 |
| **TagRelationshipMapping** | DataAsset 중앙 관리, PreActivate 시 Lyra ASC가 확장 | PawnData 교체만으로 전체 규칙 변경 |
| **GE Granted Tags** | GE 지속 중 태그 부여 → `ActivationBlockedTags`에 걸림 | 스턴 GE → `Status.Debuff.Stun` → 공격 GA 차단 |

---

## 카운터 방식의 의미

```
GA_A 활성화 → BlockAbilitiesWithTags("Attack") → 카운터["Attack"] = 1
GA_B 활성화 → BlockAbilitiesWithTags("Attack") → 카운터["Attack"] = 2

GA_A 종료   → UnBlockAbilitiesWithTags("Attack") → 카운터["Attack"] = 1
// "Attack" GA는 아직 차단 중 — GA_B가 실행 중이기 때문

GA_B 종료   → UnBlockAbilitiesWithTags("Attack") → 카운터["Attack"] = 0
// 이제서야 "Attack" GA 활성화 가능
```

여러 GA가 동시에 같은 태그를 차단해도, **모두 종료돼야** 차단이 풀린다.
