# Cost — 능력 사용 비용

> 소스: `LyraGameplayAbility.h/cpp`, `LyraAbilityCost.h`

---

## 표준 Cost GE

기본 GAS의 Cost는 GE(Instant)로 Attribute에서 차감한다.

```
GA::CheckCost()  → GE가 적용 가능한지 확인 (Attribute >= Cost?)
GA::ApplyCost()  → Cost GE 실제 적용
```

설정 방법: GA 에디터에서 `Cost Gameplay Effect Class` 설정.

---

## ULyraAbilityCost — 추가 비용 시스템

Lyra는 표준 Cost GE 외에 `ULyraAbilityCost` 인터페이스로 확장 가능한 비용 시스템을 제공한다.

### 인터페이스

```cpp
// LyraAbilityCost.h (추정 구조)
UCLASS(Abstract, DefaultToInstanced, EditInlineNew)
class ULyraAbilityCost : public UObject
{
    // 비용 지불 가능 여부 체크
    virtual bool CheckCost(const ULyraGameplayAbility* Ability,
                           const FGameplayAbilitySpecHandle Handle,
                           const FGameplayAbilityActorInfo* ActorInfo,
                           FGameplayTagContainer* OptionalRelevantTags) const;
    
    // 실제 비용 지불
    virtual void ApplyCost(const ULyraGameplayAbility* Ability,
                           const FGameplayAbilitySpecHandle Handle,
                           const FGameplayAbilityActorInfo* ActorInfo,
                           const FGameplayAbilityActivationInfo ActivationInfo);
    
    // true이면 히트가 발생했을 때만 비용 지불
    virtual bool ShouldOnlyApplyCostOnHit() const { return false; }
};
```

### GA에서 사용

```cpp
// LyraGameplayAbility.h
UPROPERTY(EditDefaultsOnly, Instanced, Category = Costs)
TArray<TObjectPtr<ULyraAbilityCost>> AdditionalCosts;
```

에디터에서 `AdditionalCosts` 배열에 ULyraAbilityCost 서브클래스를 추가.
`Instanced` + `EditInlineNew` 덕분에 에디터에서 인라인으로 설정 가능.

---

## CheckCost — 비용 체크

```cpp
bool ULyraGameplayAbility::CheckCost(
    const FGameplayAbilitySpecHandle Handle,
    const FGameplayAbilityActorInfo* ActorInfo,
    FGameplayTagContainer* OptionalRelevantTags) const
{
    // 1. 기본 Cost GE 체크
    if (!Super::CheckCost(Handle, ActorInfo, OptionalRelevantTags) || !ActorInfo)
        return false;
    
    // 2. AdditionalCosts 체크
    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
    {
        if (AdditionalCost != nullptr)
        {
            if (!AdditionalCost->CheckCost(this, Handle, ActorInfo, OptionalRelevantTags))
                return false;
        }
    }
    
    return true;
}
```

---

## ApplyCost — 비용 지불

```cpp
void ULyraGameplayAbility::ApplyCost(
    const FGameplayAbilitySpecHandle Handle,
    const FGameplayAbilityActorInfo* ActorInfo,
    const FGameplayAbilityActivationInfo ActivationInfo) const
{
    Super::ApplyCost(Handle, ActorInfo, ActivationInfo);

    // 히트 여부를 지연 계산 (필요할 때만)
    auto DetermineIfAbilityHitTarget = [&]() -> bool
    {
        if (ActorInfo->IsNetAuthority())
        {
            FGameplayAbilityTargetDataHandle TargetData;
            ASC->GetAbilityTargetData(Handle, ActivationInfo, TargetData);
            for (int32 i = 0; i < TargetData.Data.Num(); ++i)
            {
                if (UAbilitySystemBlueprintLibrary::TargetDataHasHitResult(TargetData, i))
                    return true;
            }
        }
        return false;
    };

    bool bAbilityHitTarget = false;
    bool bHasDetermined = false;
    
    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
    {
        if (AdditionalCost != nullptr)
        {
            // ShouldOnlyApplyCostOnHit() = true이면 히트했을 때만 비용 지불
            if (AdditionalCost->ShouldOnlyApplyCostOnHit())
            {
                if (!bHasDetermined)
                {
                    bAbilityHitTarget = DetermineIfAbilityHitTarget();
                    bHasDetermined = true;
                }
                if (!bAbilityHitTarget) continue;  // 히트 안 했으면 스킵
            }
            
            AdditionalCost->ApplyCost(this, Handle, ActorInfo, ActivationInfo);
        }
    }
}
```

### ShouldOnlyApplyCostOnHit 패턴

총기 무기에서 유용:
- 발사 시 탄약 소모 → `ShouldOnlyApplyCostOnHit() = false` (발사 자체에 비용)
- 특수 탄약/자원 → `ShouldOnlyApplyCostOnHit() = true` (히트했을 때만 소모)

---

## Cooldown GE

쿨다운은 Duration GE + Granted Tag 패턴으로 구현된다.

```
GA 활성화
    │
    ▼
ApplyCooldown() → CooldownGE 적용 (Duration)
    │ CooldownTag("Cooldown.Ability.X") 부여
    │
    ▼
Cooldown 중:
    │ CooldownTag가 ASC에 존재
    │ → CanActivateAbility()에서 차단 (Cooldown태그가 ActivationBlockedTags에 있으면)
    │
    ▼ (Duration 만료)
CooldownGE 제거 → CooldownTag 자동 제거 → 능력 다시 사용 가능
```

남은 쿨다운 시간 확인:
```cpp
float TimeRemaining, Duration;
GetCooldownTimeRemainingAndDuration(Handle, ActorInfo, TimeRemaining, Duration);
```

> **주의**: 쿨다운은 예측 불가. 지연이 높은 클라이언트는 불이익 가능.
