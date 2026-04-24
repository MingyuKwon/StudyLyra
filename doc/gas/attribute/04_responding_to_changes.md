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
    FGameplayAttribute                    Attribute;  // 바뀐 Attribute
    float                                 NewValue;   // 변경 후 값
    float                                 OldValue;   // 변경 전 값
    const FGameplayEffectModCallbackData* GEModData;  // GE 컨텍스트 (서버만 유효, 클라이언트는 nullptr)
};
```

**언제 전달되는가 — 두 경로**

소스에서 `FOnAttributeChangeData`가 Broadcast되는 지점이 두 곳이다.

**경로 1 — 서버: GE 적용으로 값이 바뀔 때** (`GameplayEffect.cpp:3912` — `InternalUpdateNumericalAttribute`)

```cpp
FOnAttributeChangeData CallbackData;
CallbackData.GEModData = DataToShare;  // FGameplayEffectModCallbackData 채워짐
NewDelegate->Broadcast(CallbackData);
```

**경로 2 — 클라이언트: 복제로 값이 도착할 때** (`GameplayEffect.cpp:3724`)

```cpp
FOnAttributeChangeData CallbackData;
CallbackData.GEModData = nullptr;      // GE 컨텍스트 없음
Delegate->Broadcast(CallbackData);
```

| 경로 | 발동 주체 | GEModData |
|---|---|---|
| GE 적용 | 서버 | 채워짐 |
| 복제 수신 | 클라이언트 | nullptr |

UI 업데이트처럼 "값이 바뀌었다"는 사실만 필요하면 두 경로 모두 쓸 수 있다.
"누가 데미지를 줬는지" 같은 컨텍스트가 필요하면 `GEModData != nullptr` 체크가 필수다.

---

### FGameplayEffectModCallbackData — Pre/Post 콜백에 전달되는 컨텍스트

`UAttributeSet`에는 GE가 Attribute를 변경할 때 호출되는 두 가상 함수가 있다.

```cpp
// AttributeSet.h
virtual bool PreGameplayEffectExecute(FGameplayEffectModCallbackData& Data);  // 변경 직전, false 반환 시 취소
virtual void PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data); // 변경 직후
```

소스에서 확인한 실제 호출 순서 (`GameplayEffect.cpp:4046 — InternalExecuteMod`):

```cpp
FGameplayEffectModCallbackData ExecuteData(Spec, ModEvalData, *Owner); // 컨텍스트 생성

if (AttributeSet->PreGameplayEffectExecute(ExecuteData))  // 1. 적용 직전
{
    ApplyModToAttribute(...);                              // 2. 실제 값 변경

    AttributeSet->PostGameplayEffectExecute(ExecuteData); // 3. 적용 직후
}
```

- **Pre**: 값 변경 전 가로채기 지점. `false` 반환 시 변경 취소(면역 처리 등).
- **Post**: 값이 바뀐 뒤 후처리 지점. Damage Meta Attribute를 읽어 방어막·체력에 분배하는 로직이 여기 들어간다.

> **참고**  
> 이 두 함수는 **Instant GE(BaseValue 변경)에서만 호출된다.**  
> Duration/Infinite GE가 Aggregator를 통해 CurrentValue를 바꿀 때는 호출되지 않는다.  
> 버프/디버프 수치 조작이 필요하면 `PreAttributeChange`를 써야 한다.

`FGameplayEffectModCallbackData`는 이 두 함수가 공유하는 컨텍스트 구조체다.

```cpp
// GameplayEffectExtension.h
struct FGameplayEffectModCallbackData
{
    const FGameplayEffectSpec&         EffectSpec;    // 이 Modifier를 만든 GE의 전체 스펙
    FGameplayModifierEvaluatedData&    EvaluatedData; // 계산 완료된 Modifier 결과값
    UAbilitySystemComponent&           Target;        // 적용 대상 ASC
};
```

**EffectSpec** — GE의 전체 정보. 발동자(Instigator), 태그, 레벨 등을 꺼낼 수 있다.

```cpp
Data.EffectSpec.GetContext().GetInstigator(); // 누가 데미지를 줬는지
```

**EvaluatedData** — 계산이 끝난 Modifier 결과값이다.

```cpp
// GameplayEffectTypes.h
struct FGameplayModifierEvaluatedData
{
    FGameplayAttribute                Attribute;   // 어떤 Attribute를 건드렸나
    TEnumAsByte<EGameplayModOp::Type> ModifierOp; // Add / Multiply / Override 중 무엇
    float                             Magnitude;   // 계산된 최종 수치
    FActiveGameplayEffectHandle       Handle;       // 이 Modifier를 만든 ActiveGE 핸들
};
```

어떤 Attribute가 바뀌었는지 확인하는 패턴이 바로 이 멤버를 쓰는 것이다.

```cpp
if (Data.EvaluatedData.Attribute == GetDamageAttribute()) { ... }
```

**Target** — 적용 대상 ASC. 피격자의 다른 Attribute를 읽거나 태그를 확인할 때 사용한다.

> **참고**  
> `FGameplayEffectModCallbackData`는 서버에서만 채워진다. 클라이언트 측 `FOnAttributeChangeData` 콜백에서 이 포인터는 nullptr일 수 있다.
