# Attribute 변화 감지

> **GASDoc**: 4.3.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-changes"></a>
#### Attribute 변화를 UI나 게임플레이 로직에서 감지하려면 어떻게 해야 하는가?

`UAbilitySystemComponent::GetGameplayAttributeValueChangeDelegate()`로 델리게이트를 바인딩한다. Attribute가 변경될 때마다 `NewValue`, `OldValue`, `FGameplayEffectModCallbackData`를 담은 `FOnAttributeChangeData`가 전달된다.

```cpp
AbilitySystemComponent->GetGameplayAttributeValueChangeDelegate(
    AttributeSetBase->GetHealthAttribute()
).AddUObject(this, &AGDPlayerState::HealthChanged);

virtual void HealthChanged(const FOnAttributeChangeData& Data);
```

> **참고:** `FGameplayEffectModCallbackData`는 서버에서만 설정된다.

블루프린트에서는 이를 `AsyncTask`로 래핑한 커스텀 노드를 사용할 수 있다. `UMG` 위젯의 `Destruct` 이벤트에서 `EndTask()`를 호출해 수동으로 해제해야 한다.

![Listen for Attribute Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/attributechange.png)

---

### Attribute 변화 델리게이트 콜백에서 서버와 클라이언트가 받는 정보는 왜 다른가?

```cpp
struct FOnAttributeChangeData
{
    FGameplayAttribute                    Attribute;
    float                                 NewValue;
    float                                 OldValue;
    const FGameplayEffectModCallbackData* GEModData; // 서버만 채워짐
};
```

| 경로 | 발동 주체 | GEModData |
|---|---|---|
| GE 적용 (`InternalUpdateNumericalAttribute`) | 서버 | 채워짐 |
| 복제 수신 | 클라이언트 | nullptr |

UI 업데이트처럼 값 변화만 필요하면 두 경로 모두 쓸 수 있다. "누가 데미지를 줬는지" 같은 컨텍스트가 필요하면 `GEModData != nullptr` 체크가 필수다.

---

### FGameplayEffectModCallbackData는 어디서 사용되며, 어떤 정보를 제공하는가?

```cpp
struct FGameplayEffectModCallbackData
{
    const FGameplayEffectSpec&        EffectSpec;    // GE 전체 스펙 (Instigator, 태그, 레벨 등)
    FGameplayModifierEvaluatedData&   EvaluatedData; // 계산 완료된 Modifier 결과
    UAbilitySystemComponent&          Target;        // 적용 대상 ASC
};
```

두 곳에서 사용된다.

**① FOnAttributeChangeData.GEModData** — 어떤 GE가 변화를 만들었는지 확인:
```cpp
Data.EffectSpec.GetContext().GetInstigator();          // 발동자
Data.EvaluatedData.Attribute == GetDamageAttribute();  // 어떤 Attribute가 바뀌었는지
```

**② Pre/PostGameplayEffectExecute 인자** — AttributeSet 콜백에서 변경 전후 컨텍스트:
```cpp
virtual bool PreGameplayEffectExecute(FGameplayEffectModCallbackData& Data);  // false 반환 시 취소
virtual void PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data);
```

실제 호출 순서 (`GameplayEffect.cpp — InternalExecuteMod`):
```cpp
FGameplayEffectModCallbackData ExecuteData(Spec, ModEvalData, *Owner);
if (AttributeSet->PreGameplayEffectExecute(ExecuteData))  // 1. 적용 직전
{
    ApplyModToAttribute(...);                              // 2. 실제 값 변경
    AttributeSet->PostGameplayEffectExecute(ExecuteData); // 3. 적용 직후
}
```

**Pre/Post는 BaseValue가 바뀔 때만 호출된다.**

| GE 종류 | 호출 여부 |
|---|---|
| Instant (BaseValue 변경) | 호출됨 |
| Duration / Infinite (Aggregator → CurrentValue) | 호출 안 됨 |
| Periodic (틱마다 BaseValue 변경) | 호출됨 (틱마다) |

### PreGameplayEffectExecute와 PreAttributeChange는 어떻게 다르며 각각 언제 써야 하는가?

| | PreGameplayEffectExecute | PreAttributeChange |
|---|---|---|
| 인자 | `FGameplayEffectModCallbackData` (누가/어떤 GE/얼마) | `(Attribute, NewValue&)` 두 개뿐 |
| 변경 취소 | `false` 반환으로 가능 | 불가 |
| 호출 범위 | Instant/Periodic GE (BaseValue 변경)만 | 원인 불문 모든 변경 |

**변경 원인별 커버 범위:**

| 변경 원인 | PreGameplayEffectExecute | PreAttributeChange |
|---|---|---|
| Instant GE → BaseValue | ✅ | ✅ |
| Duration/Infinite GE → CurrentValue | ❌ | ✅ |
| Periodic GE → BaseValue | ✅ | ✅ |

```cpp
// PreAttributeChange — 클램핑. 원인 불문 항상 유효 범위 보장
void ULyraHealthSet::PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)
{
    if (Attribute == GetHealthAttribute())
        NewValue = FMath::Clamp(NewValue, 0.f, GetMaxHealth());
}

// PostGameplayEffectExecute — 비즈니스 로직. Instigator 확인, 방어막 차감, 사망 처리 등
void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    // ...
}
```

`PreAttributeChange`는 값 범위 방어선, `PreGameplayEffectExecute`는 GE 컨텍스트를 알고 처리하는 비즈니스 로직 지점이다.
