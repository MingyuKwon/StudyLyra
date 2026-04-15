# Attribute & AttributeSet

## FGameplayAttributeData 구조

```cpp
USTRUCT(BlueprintType)
struct FGameplayAttributeData
{
    float BaseValue;    // 영구적인 기본값
    float CurrentValue; // 버프/디버프 포함 실제값
};
```

## BaseValue vs CurrentValue - 왜 나눠지는가?

**핵심 개념:** GAS는 Attribute 수치 변화를 "영구"와 "임시"로 분리해서 관리한다.

| | BaseValue | CurrentValue |
|---|---|---|
| 의미 | 영구적인 기반 수치 | 버프/디버프까지 반영한 실제 수치 |
| 변경 시점 | Instant GE 적용, 직접 SetBase 호출 | Duration/Infinite GE 적용/만료 시 Aggregator가 재계산 |
| 예시 | 기본 공격력 100, 아이템으로 +20 | 버프 발동 중 150, 버프 만료 후 120 |

### 시나리오로 이해하기

```
초기 상태
  BaseValue  = 100
  CurrentValue = 100

→ Instant GE (+20 영구 강화)
  BaseValue  = 120   ← 직접 변경 (영구)
  CurrentValue = 120

→ Duration GE (버프, +50% 공격력, 10초)
  BaseValue  = 120   ← 그대로
  CurrentValue = 180  ← Aggregator가 재계산: 120 * 1.5

→ 버프 만료
  BaseValue  = 120   ← 그대로
  CurrentValue = 120  ← Aggregator 재계산, 버프 modifier 제거됨
```

## GameplayEffect 종류에 따른 내부 동작

### Instant GE → BaseValue 직접 변경 (영구)

엔진 코드(`GameplayEffect.cpp`)에서 Instant GE는 `InternalExecuteMod` →
`ApplyModToAttribute` → `SetAttributeBaseValue`를 호출해 BaseValue를 직접 수정한다.

```
InternalExecuteMod()
  └─ ApplyModToAttribute()
        ├─ GetAttributeBaseValue()       // 현재 BaseValue 읽기
        ├─ StaticExecModOnBaseValue()    // 연산 (Add / Multiply / Override)
        └─ SetAttributeBaseValue()       // BaseValue 영구 변경
```

### Duration / Infinite GE → Aggregator에 Modifier 추가 (임시)

BaseValue는 건드리지 않고, `FAggregator`에 Modifier를 등록한다.
GE가 유효한 동안 CurrentValue는 Aggregator가 매번 다음 공식으로 재계산한다.

```
CurrentValue = ((BaseValue + Additive) * Multiplicative / Division) + FinalAdd
```

GE가 만료되면 Modifier만 제거되고, CurrentValue는 자동으로 BaseValue 기반으로 복원된다.

## BaseValue 변경 → CurrentValue 동기화 콜체인

BaseValue가 바뀔 때 CurrentValue도 따라 바뀌는 흐름은 `SetAttributeBaseValue` 내부에서
**Aggregator 존재 여부**에 따라 경로가 갈린다.

### Aggregator가 없는 경우 (활성 Duration/Infinite GE 없음)

BaseValue → CurrentValue가 동일 값으로 바로 기록된다.

```
SetAttributeBaseValue(Attribute, NewBaseValue)
  ├─ DataPtr->SetBaseValue(NewBaseValue)       // ① BaseValue 기록
  └─ InternalUpdateNumericalAttribute()        // ② Aggregator 없으므로 바로 진행
        └─ SetNumericAttribute_Internal()
              └─ SetNumericValueChecked()
                    └─ DataPtr->SetCurrentValue(NewBaseValue)  // ③ CurrentValue = BaseValue
```

### Aggregator가 있는 경우 (Duration/Infinite GE 활성 중)

BaseValue 변경이 dirty 이벤트를 통해 Aggregator 재계산을 트리거하고,
`BaseValue + 모든 Modifier`를 합산한 결과가 CurrentValue에 들어간다.

```
SetAttributeBaseValue(Attribute, NewBaseValue)
  ├─ DataPtr->SetBaseValue(NewBaseValue)       // ① BaseValue 기록
  └─ Aggregator->SetBaseValue(NewBaseValue)
        └─ BroadcastOnDirty()                  // ② dirty 이벤트 발생
              └─ OnDirty 델리게이트 발동
                    └─ ASC::OnAttributeAggregatorDirty()
                          └─ Aggregator->Evaluate()    // ③ BaseValue + 모든 Modifier 재계산
                                └─ InternalUpdateNumericalAttribute(NewValue)
                                      └─ SetNumericAttribute_Internal()
                                            └─ SetNumericValueChecked()
                                                  └─ DataPtr->SetCurrentValue(NewValue)  // ④ CurrentValue 갱신
```

### Aggregator가 언제 생성되는가?

이 Attribute에 처음 Duration/Infinite GE가 적용되는 순간 `AttributeAggregatorMap`에 생성된다.
생성 시 ASC의 `OnAttributeAggregatorDirty`를 `OnDirty` 델리게이트에 등록해두기 때문에
이후 BaseValue가 바뀔 때마다 Aggregator가 자동으로 CurrentValue를 재계산할 수 있다.

```cpp
// GameplayEffect.cpp
NewAttributeAggregator->OnDirty.AddUObject(
    Owner,
    &UAbilitySystemComponent::OnAttributeAggregatorDirty,
    Attribute, false
);
```

> **결론:** 두 경로 모두 최종적으로 `DataPtr->SetCurrentValue()`를 호출한다.
> BaseValue를 바꾸면 CurrentValue는 항상 자동으로 갱신되며, 버프가 걸려있어도 버프 효과는 보존된 채 재계산된다.

## 코드에서 설정하는 방법

### ATTRIBUTE_ACCESSORS 매크로가 생성하는 3가지 함수

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

### 생성자에서 초기값 설정

```cpp
// LyraHealthSet.cpp
ULyraHealthSet::ULyraHealthSet()
    : Health(100.0f)     // FGameplayAttributeData(100.f) → BaseValue = CurrentValue = 100
    , MaxHealth(100.0f)
{}
```

`FGameplayAttributeData(float DefaultValue)` 생성자가 BaseValue와 CurrentValue를 동시에 설정한다.

### PostGameplayEffectExecute에서의 실제 사용

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

## Meta Attribute 패턴

`Damage`와 `Healing`처럼 "연산용 임시값"으로만 쓰이는 Attribute.

- 복제(`UPROPERTY Replicated`)하지 않는다.
- GE가 이 Attribute를 수정 → `PostGameplayEffectExecute`에서 실제 Attribute(`Health`)에 반영 → 즉시 0으로 초기화.
- `HideFromModifiers` 메타 지정으로 에디터에서 GE Modifier 대상에서 숨김.

```cpp
// 선언부 (LyraHealthSet.h)
UPROPERTY(BlueprintReadOnly, Category="Lyra|Health", Meta=(HideFromModifiers, AllowPrivateAccess=true))
FGameplayAttributeData Damage;  // 복제 없음, HideFromModifiers

// 사용부 (LyraHealthSet.cpp - PostGameplayEffectExecute)
SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));
SetDamage(0.0f);  // 처리 후 반드시 0으로 초기화
```

## Lyra에서의 참고 파일

- `Source/LyraGame/AbilitySystem/Attributes/LyraHealthSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraCombatSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraAttributeSet.h`
