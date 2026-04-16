# GA 태그 조건 (9가지 컨테이너)

> 참고: [GAS Doc 캐시](../cache/gas_doc_cache.md) | 소스: `LyraGameplayAbility.cpp`

---

## 9가지 태그 컨테이너

| 컨테이너 | 평가 시점 | 동작 |
|---|---|---|
| `AbilityTags` | 항상 | 이 GA 자체를 식별. 차단/취소의 대상이 됨 |
| `CancelAbilitiesWithTag` | 활성화 시 | 이 GA 활성화 시 해당 태그 가진 GA 즉시 취소 |
| `BlockAbilitiesWithTag` | 활성화 중 | 이 GA 실행 중 해당 태그 가진 GA 활성화 차단 |
| `ActivationOwnedTags` | 활성화 중 | 활성화 동안 소유자 ASC에 태그 추가 (복제 안 됨) |
| `ActivationRequiredTags` | `CanActivateAbility()` | 소유자가 이 태그 **모두** 보유해야 활성화 가능 |
| `ActivationBlockedTags` | `CanActivateAbility()` | 소유자가 이 태그 **하나라도** 보유하면 활성화 불가 |
| `SourceRequiredTags` | 이벤트 트리거 시만 | 이벤트 소스가 이 태그 모두 보유해야 |
| `SourceBlockedTags` | 이벤트 트리거 시만 | 이벤트 소스가 이 태그 가지면 불가 |
| `TargetRequiredTags` | 이벤트 트리거 시만 | 이벤트 타겟이 이 태그 모두 보유해야 |

---

## DoesAbilitySatisfyTagRequirements — Lyra 확장

Lyra는 표준 체크 외에 추가 처리를 한다.

```cpp
bool ULyraGameplayAbility::DoesAbilitySatisfyTagRequirements(
    const UAbilitySystemComponent& AbilitySystemComponent, ...) const
{
    bool bBlocked = false;
    bool bMissing = false;
    
    // 1. 표준 AbilityTags 차단 체크
    if (AbilitySystemComponent.AreAbilityTagsBlocked(GetAssetTags()))
        bBlocked = true;
    
    // 2. ActivationRequiredTags + ActivationBlockedTags 초기화
    AllRequiredTags = ActivationRequiredTags;
    AllBlockedTags = ActivationBlockedTags;
    
    // 3. TagRelationshipMapping에서 추가 태그 확장 (Lyra 전용)
    if (LyraASC)
        LyraASC->GetAdditionalActivationTagRequirements(GetAssetTags(), AllRequiredTags, AllBlockedTags);
    
    // 4. 소유자 현재 태그와 비교
    if (AllBlockedTags.Num() || AllRequiredTags.Num())
    {
        FGameplayTagContainer AbilitySystemComponentTags;
        AbilitySystemComponent.GetOwnedGameplayTags(AbilitySystemComponentTags);
        
        if (AbilitySystemComponentTags.HasAny(AllBlockedTags))
        {
            // 사망 태그로 인한 차단 시 특수 실패 코드 추가
            if (AbilitySystemComponentTags.HasTag(LyraGameplayTags::Status_Death))
                OptionalRelevantTags->AddTag(LyraGameplayTags::Ability_ActivateFail_IsDead);
            bBlocked = true;
        }
        
        if (!AbilitySystemComponentTags.HasAll(AllRequiredTags))
            bMissing = true;
    }
    
    // 5. Source/Target 태그 체크 (이벤트 트리거 시)
    // ...
    
    if (bBlocked)
    {
        OptionalRelevantTags->AddTag(BlockedTag);   // "Ability.ActivateFail.TagsBlocked"
        return false;
    }
    if (bMissing)
    {
        OptionalRelevantTags->AddTag(MissingTag);   // "Ability.ActivateFail.TagsMissing"
        return false;
    }
    return true;
}
```

---

## 실패 태그 → 사용자 피드백

ActivationBlockedTags/RequiredTags 체크 실패 시 반환되는 `OptionalRelevantTags`를
`FailureTagToUserFacingMessages`와 `FailureTagToAnimMontage`로 매핑해 피드백을 제공한다.

```
Ability.ActivateFail.IsDead      → "사망 중에는 사용 불가" 메시지
Ability.ActivateFail.TagsBlocked → 차단 태그 기반 메시지
Ability.ActivateFail.ActivationGroup → ActivationGroup 차단 메시지
```

---

## ActivationOwnedTags vs Granted Tags (GE)

| | `ActivationOwnedTags` | GE Granted Tags |
|---|---|---|
| **부여 시점** | GA 활성화 중 | GE Duration/Infinite 적용 중 |
| **복제** | 안 됨 | 됨 |
| **자동 제거** | GA 종료 시 | GE 제거 시 |
| **용도** | 로컬 상태 표시 | 네트워크 동기화 필요한 상태 |

예: 근접 공격 중 "공격 중" 태그를 추가해 다른 근접 GA를 잠시 차단하려면
→ `ActivationOwnedTags`에 추가 + 다른 GA의 `ActivationBlockedTags`에 같은 태그 설정

---

## 스턴 구현 패턴 예시

```
스턴 GE 적용:
    Granted Tags += Status.Debuff.Stun

모든 공격/이동 GA:
    ActivationBlockedTags += Status.Debuff.Stun

스턴 시 이동 속도 처리:
    CharacterMovementComponent::GetMaxSpeed()에서 ASC 태그 체크
    → HasTag(Status.Debuff.Stun) → 0 반환
```
