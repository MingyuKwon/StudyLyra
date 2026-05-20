# Attribute 값 클램핑

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 기본 클램핑 — PreAttributeChange / PreAttributeBaseChange

Health처럼 0과 MaxHealth 사이를 유지해야 하는 Attribute는 `PreAttributeBaseChange` / `PreAttributeChange`에서 클램핑하는 것을 권장한다. 외부 시스템이 클램핑 전 값을 관찰하기 전에 처리할 수 있기 때문이다.

예: 현재 Health가 30인 상태에서 50을 차감하는 Instant GE가 적용되면, `PreAttributeChange`에서 NewValue를 -20이 아닌 0으로 오버라이드한다.

```cpp
void UMyHealthAttributeSet::PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)
{
    if (Attribute == GetHealthAttribute())
    {
        NewValue = FMath::Clamp(NewValue, 0.0f, GetMaxHealth());
    }
    Super::PreAttributeChange(Attribute, NewValue);
}
```

### Meta Attribute를 이용한 클램핑 (Lyra/Fortnite 방식)

GE와 Execution은 Meta Attribute만 설정하고, AttributeSet이 `PostGameplayEffectExecute`에서 실제 Attribute를 클램핑된 값으로 직접 설정하는 방식이다.

```cpp
void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    Super::PostGameplayEffectExecute(Data);
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // Damage meta attribute를 소비해 Health에 적용
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));
        SetDamage(0.0f);
    }
}
```

---

## 동적 Min-Max 재클램핑 — PostAttributeChange

MaxHealth처럼 최댓값 자체가 변경될 수 있는 경우, `PostAttributeChange`에서 현재 값이 새 범위를 벗어나지 않도록 재클램핑한다.

```cpp
void ULyraHealthSet::PostAttributeChange(
    const FGameplayAttribute& Attribute, float OldValue, float NewValue)
{
    Super::PostAttributeChange(Attribute, OldValue, NewValue);

    if (Attribute == GetMaxHealthAttribute())
    {
        // MaxHealth가 줄었을 때 현재 Health가 초과하지 않도록 보정
        if (GetHealth() > NewValue)
        {
            // Health를 새 MaxHealth로 클램핑 (ASC를 통해 설정)
        }
    }
}
```
