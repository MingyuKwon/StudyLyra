# Attribute 변화 감지

> **GASDoc**: 4.3.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-changes"></a>
#### 4.3.4 Attribute 변화에 응답하기

Attribute가 변경될 때 UI나 다른 게임플레이 요소를 업데이트하려면 `UAbilitySystemComponent::GetGameplayAttributeValueChangeDelegate(FGameplayAttribute Attribute)`를 사용한다. 이 함수는 Attribute가 변경될 때마다 자동으로 호출되는 델리게이트를 반환하며, 바인딩할 수 있다. 델리게이트는 `NewValue`, `OldValue`, `FGameplayEffectModCallbackData`를 담은 `FOnAttributeChangeData` 파라미터를 제공한다. > **참고**  
> `FGameplayEffectModCallbackData`는 서버에서만 설정된다.

```c++
AbilitySystemComponent->GetGameplayAttributeValueChangeDelegate(AttributeSetBase->GetHealthAttribute()).AddUObject(this, &AGDPlayerState::HealthChanged);
```

```c++
virtual void HealthChanged(const FOnAttributeChangeData& Data);
```

샘플 프로젝트는 `GDPlayerState`에서 Attribute 값 변경 델리게이트에 바인딩하여 HUD를 업데이트하고, 체력이 0이 됐을 때 플레이어 사망을 처리한다.

샘플 프로젝트에는 이를 `AsyncTask`로 래핑한 커스텀 블루프린트 노드도 포함되어 있다. `UI_HUD` UMG 위젯에서 체력, 마나, 스태미나 값을 업데이트하는 데 사용된다. 이 `AsyncTask`는 `EndTask()`를 수동으로 호출할 때까지 계속 살아있으며, UMG 위젯의 `Destruct` 이벤트에서 이를 처리한다. `AsyncTaskAttributeChanged.h/cpp`를 참고한다.

![Listen for Attribute Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/attributechange.png)

---

## 내 분석

### FOnAttributeChangeData — 델리게이트 콜백이 받는 인자

`GetGameplayAttributeValueChangeDelegate()`에 바인딩한 함수가 받는 구조체다.

```cpp
// GameplayEffectTypes.h:1009
struct FOnAttributeChangeData
{
    FGameplayAttribute                    Attribute;
    float                                 NewValue;
    float                                 OldValue;
    const FGameplayEffectModCallbackData* GEModData; // 아래 참고
};
```

소스에서 Broadcast 지점은 두 곳이다 (`GameplayEffect.cpp:3724, 3912`).

| 경로 | 발동 주체 | GEModData |
|---|---|---|
| GE 적용 (`InternalUpdateNumericalAttribute`) | 서버 | 채워짐 |
| 복제 수신 | 클라이언트 | nullptr |

UI 업데이트처럼 값 변화만 필요하면 두 경로 모두 쓸 수 있다.
"누가 데미지를 줬는지" 같은 컨텍스트가 필요하면 `GEModData != nullptr` 체크가 필수다.

---

### FGameplayEffectModCallbackData — 구조와 두 가지 쓰임

```cpp
// GameplayEffectExtension.h
struct FGameplayEffectModCallbackData
{
    const FGameplayEffectSpec&        EffectSpec;   // GE 전체 스펙 (Instigator, 태그, 레벨 등)
    FGameplayModifierEvaluatedData&   EvaluatedData;// 계산 완료된 Modifier 결과
    UAbilitySystemComponent&          Target;       // 적용 대상 ASC
};

// GameplayEffectTypes.h
struct FGameplayModifierEvaluatedData
{
    FGameplayAttribute                Attribute;    // 건드린 Attribute
    TEnumAsByte<EGameplayModOp::Type> ModifierOp;  // Add / Multiply / Override
    float                             Magnitude;    // 계산된 최종 수치
    FActiveGameplayEffectHandle       Handle;       // 이 Modifier를 만든 ActiveGE 핸들
};
```

이 구조체는 두 곳에서 쓰인다.

**① FOnAttributeChangeData.GEModData** — 델리게이트 콜백에서 "어떤 GE가 이 변화를 만들었는지" 확인할 때.

```cpp
Data.EffectSpec.GetContext().GetInstigator();          // 발동자
Data.EvaluatedData.Attribute == GetDamageAttribute();  // 어떤 Attribute가 바뀌었는지
```

**② Pre/PostGameplayEffectExecute 인자** — AttributeSet 콜백에서 값 변경 전후에 받는 컨텍스트.

```cpp
// AttributeSet.h
virtual bool PreGameplayEffectExecute(FGameplayEffectModCallbackData& Data);  // 변경 직전, false 반환 시 취소
virtual void PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data); // 변경 직후
```

실제 호출 순서 (`GameplayEffect.cpp:4046 — InternalExecuteMod`):

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
| Instant (BaseValue 변경) | **호출됨** |
| Duration / Infinite (Aggregator → CurrentValue) | **호출 안 됨** |
| Periodic (틱마다 BaseValue 변경) | **호출됨** (틱마다) |

Duration/Infinite GE의 CurrentValue 변경 시점을 가로채려면 `PreAttributeChange`를 써야 한다.
