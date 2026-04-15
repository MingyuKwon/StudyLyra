# GE 지속 타입

> 참고: [GAS Doc 캐시](../gas_doc_cache.md)

---

## 3가지 Duration 타입

| 타입 | 적용 대상 | 지속 시간 | Attribute 영향 |
|---|---|---|---|
| `Instant` | BaseValue | 즉시, 영구 적용 | BaseValue 영구 변경 |
| `Duration` | Aggregator | 지정 시간 후 자동 제거 | CurrentValue만 변경 (GE 제거 시 원상복구) |
| `Infinite` | Aggregator | 수동 제거할 때까지 | CurrentValue만 변경 |

---

## Instant GE — BaseValue 영구 변경

```
Instant GE 적용
    │
    ▼
PreAttributeBaseChange(Attr, NewValue&)  ← Clamp 처리
    │
    ▼
[BaseValue 변경]
    │
    ▼
CurrentValue = BaseValue (Aggregator 없을 때)
    │
    ▼
PostAttributeChange(Attr, OldValue, NewValue)
```

**특징**:
- 제거 불가 (이미 값이 영구 변경됨)
- 데미지, 일회성 체력 회복, 레벨업 스탯 증가 등에 사용
- ExecCalc와 함께 사용 시 `AddOutputModifier(attr, Additive, value)` 패턴

---

## Duration/Infinite GE — Aggregator 기반

```
Duration/Infinite GE 적용
    │
    ▼
Aggregator에 Modifier 등록 (BaseValue 불변)
    │
    ▼
PreAttributeChange(Attr, NewValue&)  ← Clamp 처리 (Aggregator 재계산 시마다 호출)
    │
    ▼
CurrentValue = 재계산값 (BaseValue + 모든 등록된 Modifier)
    │
    ▼
GE 제거 시: Aggregator에서 해당 Modifier 제거 → CurrentValue 재계산
```

**특징**:
- 버프/디버프, 장비 스탯 보너스 등에 사용
- 여러 GE가 같은 Attribute에 동시 적용 가능 (Aggregator가 합산)
- `OnAttributeAggregatorCreated` 콜백: 첫 Duration/Infinite GE 적용 시 호출

---

## Clamp 주의사항

`PreAttributeChange`에서 값을 수정해도 **Aggregator 내부 Modifier 값은 변하지 않는다**.

예시 문제:
1. MaxHealth = 100, Health = 100
2. MaxHealth를 50으로 줄이는 GE 적용
3. `PreAttributeChange`에서 MaxHealth = max(50, 0) = 50 처리됨
4. **Health는 여전히 100** (Aggregator 내부 값은 변하지 않음)

해결책: `PostAttributeChange`에서 Health를 MaxHealth 이하로 강제 조정하는 Instant GE 적용:
```cpp
void ULyraHealthSet::PostAttributeChange(const FGameplayAttribute& Attribute, ...)
{
    if (Attribute == GetMaxHealthAttribute())
    {
        // MaxHealth가 줄었으면 Health도 같이 줄임
        if (GetMaxHealth() < GetHealth())
        {
            // ASC를 통해 Override GE 적용
        }
    }
}
```

---

## Periodic GE

Duration/Infinite GE에 주기를 설정하면 Periodic GE가 된다.

```
Infinite GE + Period = 1.0f
    → 매 1초마다 Instant처럼 한 번 적용
    → 1초마다 PostGameplayEffectExecute 호출
    → 재생 틱, 독 틱 등에 활용
```

**중요**: Periodic GE는 예측 불가 (서버에서만 실행).

---

## Ongoing Tag Requirements — Inhibit

GE가 활성화된 상태에서도 특정 태그 조건에 따라 일시적으로 비활성화(Inhibit)할 수 있다.

```
Ongoing Required Tags: 이 태그가 없으면 GE 일시 Inhibit
Ongoing Ignored Tags: 이 태그가 있으면 GE 일시 Inhibit
```

예: "무적 상태" 태그가 있을 때 모든 데미지 GE를 Inhibit하는 패턴.

---

## Apply/Remove API

```cpp
// Apply
FActiveGameplayEffectHandle Handle = ASC->ApplyGameplayEffectSpecToSelf(*Spec, PredictionKey);
// 콜백: OnActiveGameplayEffectAddedDelegateToSelf

// Remove by Handle
ASC->RemoveActiveGameplayEffect(Handle, StacksToRemove);

// Remove by Query
FGameplayEffectQuery Query = FGameplayEffectQuery::MakeQuery_MatchAnyOwningTags(Tags);
ASC->RemoveActiveEffects(Query);
// 콜백: OnAnyGameplayEffectRemovedDelegate
```
