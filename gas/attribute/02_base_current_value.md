# BaseValue vs CurrentValue

## FGameplayAttributeData 구조

```cpp
USTRUCT(BlueprintType)
struct FGameplayAttributeData
{
    float BaseValue;    // 영구적인 기본값
    float CurrentValue; // 버프/디버프 포함 실제값
};
```

## 왜 나눠지는가?

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
