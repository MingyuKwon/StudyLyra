# ActivationGroup — 능력 간 상호 배타 관리

> 소스: `LyraGameplayAbility.h`, `LyraAbilitySystemComponent.cpp`

---

## 개요

`ELyraAbilityActivationGroup`은 GA가 다른 GA와 어떻게 공존하는지를 정의한다.

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationGroup : uint8
{
    Independent,            // 다른 GA와 무관하게 독립 실행
    Exclusive_Replaceable,  // Exclusive 그룹에 속하지만, 새 Exclusive GA에 의해 교체될 수 있음
    Exclusive_Blocking,     // Exclusive 그룹에 속하며, 다른 Exclusive GA를 차단
    MAX
};
```

---

## 동작 규칙

| Group | 새 GA 활성화 가능? | 기존 GA에 미치는 영향 |
|---|---|---|
| `Independent` | 항상 가능 | 없음 |
| `Exclusive_Replaceable` | Exclusive_Blocking이 없을 때 가능 | 새 Exclusive GA가 활성화되면 이 GA는 취소됨 |
| `Exclusive_Blocking` | Exclusive_Blocking이 없을 때 가능 | 활성화 중 다른 Exclusive GA(Replaceable) 차단 |

**핵심 불변식**: Exclusive 계열 GA는 한 번에 최대 1개만 활성화될 수 있다.

---

## IsActivationGroupBlocked

```cpp
bool ULyraAbilitySystemComponent::IsActivationGroupBlocked(ELyraAbilityActivationGroup Group) const
{
    switch (Group)
    {
    case ELyraAbilityActivationGroup::Independent:
        // Independent는 절대 차단되지 않음
        return false;
        
    case ELyraAbilityActivationGroup::Exclusive_Replaceable:
    case ELyraAbilityActivationGroup::Exclusive_Blocking:
        // Exclusive_Blocking이 하나라도 실행 중이면 차단
        return (ActivationGroupCounts[(uint8)ELyraAbilityActivationGroup::Exclusive_Blocking] > 0);
    }
}
```

`ActivationGroupCounts`는 각 Group에서 현재 활성화된 GA 수를 추적하는 배열이다.

---

## AddAbilityToActivationGroup 실행 시 취소 로직

새 GA가 Exclusive 그룹으로 활성화될 때 기존 `Exclusive_Replaceable` GA를 취소한다.

```cpp
void ULyraAbilitySystemComponent::AddAbilityToActivationGroup(
    ELyraAbilityActivationGroup Group, ULyraGameplayAbility* LyraAbility)
{
    ActivationGroupCounts[(uint8)Group]++;

    switch (Group)
    {
    case ELyraAbilityActivationGroup::Independent:
        // Independent는 아무것도 취소하지 않음
        break;
        
    case ELyraAbilityActivationGroup::Exclusive_Replaceable:
    case ELyraAbilityActivationGroup::Exclusive_Blocking:
        // 기존 Exclusive_Replaceable GA를 모두 취소 (자신 제외)
        CancelActivationGroupAbilities(
            ELyraAbilityActivationGroup::Exclusive_Replaceable, LyraAbility, false);
        break;
    }
    
    // 불변식 확인: Exclusive 계열은 최대 1개
    const int32 ExclusiveCount = ActivationGroupCounts[Exclusive_Replaceable] + 
                                  ActivationGroupCounts[Exclusive_Blocking];
    ensure(ExclusiveCount <= 1);
}
```

---

## CanActivateAbility에서의 체크

```cpp
// LyraGameplayAbility.cpp
bool ULyraGameplayAbility::CanActivateAbility(...) const
{
    if (!Super::CanActivateAbility(...)) return false;
    
    ULyraAbilitySystemComponent* LyraASC = CastChecked<ULyraAbilitySystemComponent>(...);
    
    // ActivationGroup이 차단된 상태이면 활성화 불가
    if (LyraASC->IsActivationGroupBlocked(ActivationGroup))
    {
        if (OptionalRelevantTags)
            OptionalRelevantTags->AddTag(LyraGameplayTags::Ability_ActivateFail_ActivationGroup);
        return false;
    }
    
    return true;
}
```

---

## SetCanBeCanceled와 Group 관계

```cpp
void ULyraGameplayAbility::SetCanBeCanceled(bool bCanBeCanceled)
{
    // Exclusive_Replaceable GA는 bCanBeCanceled를 false로 설정할 수 없음
    // (새 Exclusive GA에 의해 반드시 교체될 수 있어야 하므로)
    if (!bCanBeCanceled && (ActivationGroup == ELyraAbilityActivationGroup::Exclusive_Replaceable))
    {
        UE_LOG(LogLyraAbilitySystem, Error, TEXT("SetCanBeCanceled: ..."));
        return;
    }
    Super::SetCanBeCanceled(bCanBeCanceled);
}
```

---

## 런타임 Group 변경

활성화 중에도 Group을 변경할 수 있다.

```cpp
// CanChangeActivationGroup: 변경 가능 여부 체크
bool ULyraGameplayAbility::CanChangeActivationGroup(ELyraAbilityActivationGroup NewGroup) const
{
    if (!IsInstantiated() || !IsActive()) return false;
    if (ActivationGroup == NewGroup) return true;
    
    // 새 Group이 차단된 상태이면 불가 (단, 현재 자신이 차단 중이면 예외)
    if ((ActivationGroup != ELyraAbilityActivationGroup::Exclusive_Blocking) &&
        LyraASC->IsActivationGroupBlocked(NewGroup))
        return false;
    
    // Exclusive_Replaceable로 바꾸려면 취소 가능해야 함
    if ((NewGroup == ELyraAbilityActivationGroup::Exclusive_Replaceable) && !CanBeCanceled())
        return false;
    
    return true;
}

// ChangeActivationGroup: 실제 변경
bool ULyraGameplayAbility::ChangeActivationGroup(ELyraAbilityActivationGroup NewGroup)
{
    if (!CanChangeActivationGroup(NewGroup)) return false;
    
    LyraASC->RemoveAbilityFromActivationGroup(ActivationGroup, this);
    LyraASC->AddAbilityToActivationGroup(NewGroup, this);
    ActivationGroup = NewGroup;
    return true;
}
```

---

## 활용 예시

- **기본 공격**: `Independent` — 점프나 회피와 동시에 사용 가능
- **근접 콤보**: `Exclusive_Blocking` — 콤보 중 다른 근접 콤보 차단
- **약한 스킬**: `Exclusive_Replaceable` — 더 강한 스킬에 의해 교체 가능
- **궁극기**: `Exclusive_Blocking` — 사용 중 다른 스킬 차단
