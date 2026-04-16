# ATTRIBUTE_ACCESSORS & Clamp

## ATTRIBUTE_ACCESSORS 매크로가 생성하는 3가지 함수

`ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)` 한 줄이 아래 세 함수를 자동 생성한다.

```cpp
// 1. Getter: CurrentValue 반환 (실제 게임에서 쓰는 값)
float GetHealth() const
{
    return Health.GetCurrentValue();
}

// 2. Setter: ASC를 통해 BaseValue 변경
void SetHealth(float NewVal)
{
    AbilityComp->SetNumericAttributeBase(GetHealthAttribute(), NewVal);
}

// 3. Initter: BaseValue와 CurrentValue 둘 다 직접 설정 (초기화 전용)
void InitHealth(float NewVal)
{
    Health.SetBaseValue(NewVal);
    Health.SetCurrentValue(NewVal);
}
```

> **SetHealth vs InitHealth 차이:**
> - `SetHealth` → ASC + Aggregator를 통해 설정. Duration GE modifier가 있으면 CurrentValue가 재계산됨.
> - `InitHealth` → 자료구조를 직접 쓴다. ASC나 Aggregator를 건너뜀. **초기화할 때만 사용.**

## 생성자에서 초기값 설정

```cpp
// LyraHealthSet.cpp
ULyraHealthSet::ULyraHealthSet()
    : Health(100.0f)     // FGameplayAttributeData(100.f) → BaseValue = CurrentValue = 100
    , MaxHealth(100.0f)
{}
```

`FGameplayAttributeData(float DefaultValue)` 생성자가 BaseValue와 CurrentValue를 동시에 설정한다.

## PostGameplayEffectExecute에서의 실제 사용

```cpp
// LyraHealthSet.cpp - Damage Meta Attribute 처리
if (Data.EvaluatedData.Attribute == GetDamageAttribute())
{
    // GetHealth()     → Health.GetCurrentValue() 읽기
    // GetDamage()     → Damage.GetCurrentValue() 읽기
    // SetHealth(...)  → ASC->SetNumericAttributeBase() → BaseValue 변경
    SetHealth(FMath::Clamp(GetHealth() - GetDamage(), 0.0f, GetMaxHealth()));
    SetDamage(0.0f);  // Meta Attribute 초기화
}
```

## Clamp는 어디서 하는가?

GAS에서 Clamp를 처리하는 콜백은 두 개다.

| 콜백 | 언제 호출 | 용도 |
|------|----------|------|
| `PreAttributeChange` | CurrentValue 변경 직전 (Duration GE modifier 재계산 시) | 임시값 Clamp |
| `PreAttributeBaseChange` | BaseValue 변경 직전 (Instant GE, SetHealth 호출 시) | 영구값 Clamp |

```cpp
// LyraHealthSet.cpp
void ULyraHealthSet::ClampAttribute(const FGameplayAttribute& Attribute, float& NewValue) const
{
    if (Attribute == GetHealthAttribute())
    {
        NewValue = FMath::Clamp(NewValue, 0.0f, GetMaxHealth());
    }
    else if (Attribute == GetMaxHealthAttribute())
    {
        NewValue = FMath::Max(NewValue, 1.0f);
    }
}
```
