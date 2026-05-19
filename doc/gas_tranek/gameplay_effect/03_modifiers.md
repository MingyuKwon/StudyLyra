# GE Modifier

> **GASDoc**: 4.5.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-mods"></a>
#### 4.5.4 Gameplay Effect Modifiers

Modifier는 Attribute를 변경하는 수단이며, 예측(Prediction)적으로 Attribute를 변경할 수 있는 **유일한 방법**이다. GE는 Modifier를 0개 이상 가질 수 있고, 각 Modifier는 지정된 연산을 통해 하나의 Attribute만 담당한다.

| 연산       | 설명 |
| ---------- | ---- |
| `Add`      | Modifier에 지정된 Attribute에 결과값을 더한다. 음수값을 사용하면 빼기도 가능하다 |
| `Multiply` | Modifier에 지정된 Attribute에 결과값을 곱한다 |
| `Divide`   | Modifier에 지정된 Attribute를 결과값으로 나눈다 |
| `Override` | Modifier에 지정된 Attribute를 결과값으로 덮어쓴다. 마지막으로 적용된 Modifier가 우선된다 |

Attribute의 `CurrentValue`는 `BaseValue`에 모든 Modifier를 집산한 결과다. 집산 공식은 `GameplayEffectAggregator.cpp`의 `FAggregatorModChannel::EvaluateWithBase`에 다음과 같이 정의되어 있다.

```c++
((InlineBaseValue + Additive) * Multiplicitive) / Division
```

`Override` Modifier는 마지막으로 적용된 Modifier가 우선하여 최종값을 덮어쓴다.

> **참고**  
> 퍼센트 기반 변경은 덧셈 이후에 처리되도록 반드시 `Multiply` 연산을 사용해야 한다.

> **참고**  
> Prediction은 퍼센트 변경과 궁합이 좋지 않다.

Modifier의 종류는 Scalable Float, Attribute Based, Custom Calculation Class, Set By Caller의 네 가지다. 이들은 각각 float 값을 생성하며, 이 값이 Modifier의 연산에 따라 지정된 Attribute를 변경하는 데 사용된다.

| Modifier 타입              | 설명 |
| -------------------------- | ---- |
| `Scalable Float`           | `FScalableFloat`는 행이 변수, 열이 레벨인 DataTable을 참조하는 구조체다. 어빌리티의 현재 레벨(GameplayEffectSpec에서 재정의 가능)에 해당하는 테이블 행의 값을 자동으로 읽어온다. 이 값에는 계수(coefficient)를 추가로 적용할 수 있다. DataTable/행을 지정하지 않으면 값을 1로 취급하므로, 계수만으로 모든 레벨에서 고정 값을 하드코딩할 수 있다 |
| `Attribute Based`          | `Attribute Based` Modifier는 Source(GameplayEffectSpec을 생성한 쪽) 또는 Target(GameplayEffectSpec을 수신한 쪽)의 특정 Attribute의 `CurrentValue` 또는 `BaseValue`를 가져와, 계수와 계수 전후 가산값을 추가로 적용한다. **Snapshotting**: GameplayEffectSpec 생성 시점에 Attribute를 캡처하는 방식과, 적용 시점에 캡처하는 방식을 선택할 수 있다 |
| `Custom Calculation Class` | `Custom Calculation Class`는 복잡한 Modifier에 가장 높은 유연성을 제공한다. 이 Modifier는 `ModifierMagnitudeCalculation` 클래스를 사용하며, 결과 float 값에 계수와 계수 전후 가산값을 추가로 적용할 수 있다 |
| `Set By Caller`            | `SetByCaller` Modifier는 GameplayEffect 외부에서 런타임에 어빌리티 또는 GameplayEffectSpec 생성자가 GameplayEffectSpec에 직접 설정하는 값이다. 예를 들어, 플레이어가 버튼을 누르고 있는 시간에 따라 데미지를 설정하고 싶을 때 `SetByCaller`를 사용한다. `SetByCaller`는 기본적으로 GameplayEffectSpec에 저장되는 `TMap<FGameplayTag, float>`다. Modifier는 Aggregator에게 지정된 GameplayTag와 연결된 `SetByCaller` 값을 찾으라고 지시한다. Modifier에서 사용하는 `SetByCaller`는 GameplayTag 버전만 사용 가능하며, FName 버전은 사용할 수 없다. Modifier가 `SetByCaller`로 설정되어 있는데 GameplayEffectSpec에 올바른 GameplayTag가 존재하지 않으면, 게임은 런타임 에러를 발생시키고 0을 반환한다. `Divide` 연산의 경우 이로 인한 문제가 생길 수 있으니 주의가 필요하다. 자세한 사용법은 `SetByCallers`를 참조 |

<a name="concepts-ge-mods-multiplydivide"></a>
##### 4.5.4.1 Multiply/Divide Modifier의 합산 방식

기본적으로 모든 `Multiply`와 `Divide` Modifier는 Attribute의 BaseValue에 곱하거나 나누기 전에 **서로 더해진다**.

```c++
float FAggregatorModChannel::EvaluateWithBase(float InlineBaseValue, const FAggregatorEvaluateParameters& Parameters) const
{
	...
	float Additive = SumMods(Mods[EGameplayModOp::Additive], GameplayEffectUtilities::GetModifierBiasByModifierOp(EGameplayModOp::Additive), Parameters);
	float Multiplicitive = SumMods(Mods[EGameplayModOp::Multiplicitive], GameplayEffectUtilities::GetModifierBiasByModifierOp(EGameplayModOp::Multiplicitive), Parameters);
	float Division = SumMods(Mods[EGameplayModOp::Division], GameplayEffectUtilities::GetModifierBiasByModifierOp(EGameplayModOp::Division), Parameters);
	...
	return ((InlineBaseValue + Additive) * Multiplicitive) / Division;
	...
}
```

```c++
float FAggregatorModChannel::SumMods(const TArray<FAggregatorMod>& InMods, float Bias, const FAggregatorEvaluateParameters& Parameters)
{
	float Sum = Bias;

	for (const FAggregatorMod& Mod : InMods)
	{
		if (Mod.Qualifies())
		{
			Sum += (Mod.EvaluatedMagnitude - Bias);
		}
	}

	return Sum;
}
```
*from `GameplayEffectAggregator.cpp`*

이 공식에서 `Multiply`와 `Divide`의 Bias 값은 `1`이며, `Add`의 Bias는 `0`이다. 따라서 합산 공식은 다음과 같다.

```
1 + (Mod1.Magnitude - 1) + (Mod2.Magnitude - 1) + ...
```

이 공식은 예상치 못한 결과를 낳는다. 첫째, 이 공식은 모든 Modifier를 더한 뒤 BaseValue에 곱하거나 나누는 방식이다. 대부분의 사람들은 서로 곱해질 것으로 기대한다. 예를 들어, `1.5` 두 개의 `Multiply` Modifier가 있을 때 많은 사람들이 BaseValue에 `1.5 × 1.5 = 2.25`가 곱해질 것이라 예상하지만, 실제로는 `1.5`들을 더하여 BaseValue에 `2`를 곱한다(`50% 증가 + 50% 증가 = 100% 증가`). 이는 `GameplayPrediction.h`의 예시에서 기반 속도 `500`에 `10%` 속도 버프가 적용되면 `550`이 되고, 또 하나의 `10%` 버프가 추가되면 `600`이 되는 방식과 같다.

둘째, 이 공식은 Paragon을 기준으로 설계되었기 때문에 사용 가능한 값에 대한 비문서화된 규칙이 있다.

`Multiply`와 `Divide` 곱셈 합산 공식의 규칙:
- `(1 미만의 값은 최대 1개)` AND `(1, 2) 범위 값은 여러 개 가능)`
- OR `(2 이상의 값 1개)`

공식의 Bias는 `[1, 2)` 범위 숫자들의 정수 자릿수를 빼는 역할을 한다. 첫 번째 Modifier의 Bias가 시작 Sum 값(루프 전에 Bias로 초기화)에서 빠지기 때문에, 값이 하나만 있을 때는 어떤 값이든 올바르게 동작하며, 1 미만 값 하나는 [1, 2) 범위의 값들과 함께 사용할 수 있다.

`Multiply` 예시:  
Multiplier: `0.5`  
`1 + (0.5 - 1) = 0.5`, 정확

Multiplier: `0.5, 0.5`  
`1 + (0.5 - 1) + (0.5 - 1) = 0`, 부정확 (예상값은 `1`). 1 미만 값 여러 개를 더하는 것은 Multiplier 합산 방식과 맞지 않는다. Paragon은 [가장 큰 음수 값만 Multiply Modifier로 사용하도록 설계되어 1 미만 값이 최대 하나만 BaseValue에 곱해지도록 했다.

Multiplier: `1.1, 0.5`  
`1 + (0.5 - 1) + (1.1 - 1) = 0.6`, 정확

Multiplier: `5, 5`  
`1 + (5 - 1) + (5 - 1) = 9`, 부정확 (예상값은 `10`). 결과는 항상 `Modifier의 합계 - Modifier의 개수 + 1`이 된다.

많은 게임들은 `Multiply`와 `Divide` Modifier가 BaseValue에 적용되기 전에 서로 실제로 곱해지길 원할 것이다. 이를 구현하려면 `FAggregatorModChannel::EvaluateWithBase()`의 **엔진 코드를 직접 수정**해야 한다.

```c++
float FAggregatorModChannel::EvaluateWithBase(float InlineBaseValue, const FAggregatorEvaluateParameters& Parameters) const
{
	...
	float Multiplicitive = MultiplyMods(Mods[EGameplayModOp::Multiplicitive], Parameters);
	float Division = MultiplyMods(Mods[EGameplayModOp::Division], Parameters);
	...

	return ((InlineBaseValue + Additive) * Multiplicitive) / Division;
}
```

```c++
float FAggregatorModChannel::MultiplyMods(const TArray<FAggregatorMod>& InMods, const FAggregatorEvaluateParameters& Parameters)
{
	float Multiplier = 1.0f;

	for (const FAggregatorMod& Mod : InMods)
	{
		if (Mod.Qualifies())
		{
			Multiplier *= Mod.EvaluatedMagnitude;
		}
	}

	return Multiplier;
}
```

<a name="concepts-ge-mods-gameplaytags"></a>
##### 4.5.4.2 Modifier의 GameplayTag 조건

각 Modifier에 대해 `SourceTags`와 `TargetTags`를 지정할 수 있다. 이 태그들은 GameplayEffect의 `Application Tag Requirements`와 동일하게 동작한다. 즉, 태그 조건은 GE가 처음 적용되는 시점에만 평가된다. 다시 말해, 주기적으로 실행되는 Infinite GE의 경우, 최초 적용 시에는 태그 조건을 고려하지만 이후 각 주기 실행 시에는 재검사하지 않는다.

`Attribute Based` Modifier는 추가로 `SourceTagFilter`와 `TargetTagFilter`를 설정할 수 있다. `Attribute Based` Modifier의 Source Attribute 크기를 결정할 때, 이 필터는 해당 Attribute에 영향을 주는 특정 Modifier를 제외하는 데 사용된다. Source 또는 Target이 필터의 모든 태그를 보유하지 않은 Modifier는 제외된다.

더 자세히 설명하면: Source ASC와 Target ASC의 태그는 GameplayEffect에 의해 캡처된다. Source ASC의 태그는 GameplayEffectSpec 생성 시 캡처되고, Target ASC의 태그는 Effect 실행 시 캡처된다. Infinite 또는 Duration Effect의 Modifier가 적용 조건("qualifies")을 충족하는지 판단할 때(즉, Aggregator가 조건을 충족할 때), 해당 필터가 설정되어 있다면 캡처된 태그를 필터와 비교한다.

---

### Aggregator — Modifier를 모아 CurrentValue를 계산하는 객체

> 소스: `GameplayEffectAggregator.h:278`, `GameplayEffect.h:1960`

**Attribute 하나당 Aggregator 하나**가 존재한다. 그 Attribute에 영향을 주는 모든 Duration/Infinite GE의 Modifier를 모아두고, 요청 시 `BaseValue + 모든 Mod`를 집산해서 `CurrentValue`를 계산한다.

```cpp
// GameplayEffect.h:1960 — FActiveGameplayEffectsContainer 안
TMap<FGameplayAttribute, FAggregatorRef> AttributeAggregatorMap;
// AttributeAggregatorMap[Health]    → Health Aggregator
// AttributeAggregatorMap[MoveSpeed] → MoveSpeed Aggregator
```

#### Aggregator 내부 구조

```cpp
// GameplayEffectAggregator.h:278
struct FAggregator
{
    float BaseValue;                            // Instant GE가 영구 수정하는 기준값
    FAggregatorModChannelContainer ModChannels; // 쌓인 Modifier들 (연산별로 분류)
    TArray<FActiveGameplayEffectHandle> Dependents; // 변화 구독 GE 목록
    FOnAggregatorDirty OnDirty;                 // 값 변경 시 알림 델리게이트
};
```

#### GE Apply/Remove와 Aggregator

```
GE Apply  → AddAggregatorMod()    → Mod 추가 → OnDirty 발생 → CurrentValue 재계산
GE Remove → RemoveAggregatorMod() → Mod 제거 → OnDirty 발생 → CurrentValue 재계산
```

Instant GE는 Aggregator를 거치지 않고 `BaseValue`를 직접 영구 수정한다. Duration/Infinite GE만 Aggregator에 Modifier를 등록하며, 제거될 때 함께 빠진다.

#### CurrentValue 계산 흐름

```
Aggregator.Evaluate()
  → UpdateQualifiesOnAllMods()    태그 조건 체크 → IsQualified 갱신
  → ModChannels.EvaluateWithBase(BaseValue)
       Channel0 → Channel1 → ... 순서대로 순차 계산
  → 반환값 = CurrentValue
```

---

### 집산 공식과 연산 종류

> 소스: `GameplayEffectTypes.h:112`, `GameplayEffectAggregator.cpp:76`

공식은 엔진에 고정되어 있다. Modifier를 아무리 많이 붙여도 이 틀 안에서 처리된다.

```cpp
// GameplayEffectTypes.h:116 — 엔진 주석에 명시된 공식
((BaseValue + AddBase) * MultiplyAdditive / DivideAdditive * MultiplyCompound) + AddFinal
```

| 연산 | 동작 | 비고 |
|---|---|---|
| `AddBase` | BaseValue에 더함. 먼저 처리 | 구버전 이름: `Additive` |
| `MultiplyAdditive` | **더해진 뒤** 한 번에 곱함 (1.5 + 1.5 = ×2.0) | 구버전: `Multiplicitive` |
| `DivideAdditive` | **더해진 뒤** 한 번에 나눔 | 구버전: `Division` |
| `Override` | 결과를 즉시 덮어씀 | 아래 참조 |
| `MultiplyCompound` | **진짜 곱셈** (1.5 × 1.5 = ×2.25) | UE 5.x 신규 |
| `AddFinal` | 모든 곱셈 후 마지막에 덧셈 | UE 5.x 신규 |

공식 자체를 바꾸려면 엔진 코드 수정이 필요하다.

#### Override는 나머지를 전부 건너뛴다

```cpp
// GameplayEffectAggregator.cpp:78
float FAggregatorModChannel::EvaluateWithBase(float InlineBaseValue, ...) const
{
    for (const FAggregatorMod& Mod : Mods[EGameplayModOp::Override])
    {
        if (Mod.Qualifies())
            return Mod.EvaluatedMagnitude;  // 즉시 반환 — AddBase/Multiply 계산 안 함
    }
    // Override가 없을 때만 아래 도달
    float Additive = SumMods(...);
    ...
    return ((InlineBaseValue + Additive) * Multiplicitive / Division * CompoundMultiply) + FinalAdd;
}
```

Qualify된 Override가 하나라도 있으면 Add/Multiply/AddFinal 계산 전체를 건너뛴다.

Override가 여러 개면 **먼저 Apply된 것(배열 앞쪽)** 이 이긴다. 개념 요약의 "마지막으로 적용된 Modifier가 우선된다"는 설명과 실제 코드가 반대다.

---

### Channel — Modifier 계층을 직렬로 쌓는 것

> 소스: `GameplayEffectAggregator.h:181`, `GameplayEffectAggregator.cpp:250`

기본적으로 모든 Modifier는 Channel0 하나에 들어간다. Channel을 여러 개 쓰면 **이전 채널의 계산 결과가 다음 채널의 BaseValue**가 된다.

```cpp
// GameplayEffectAggregator.cpp:250
float ComputedValue = InlineBaseValue;
for (auto& ChannelEntry : ModChannelsMap)   // Channel0 → 1 → 2 → ...
    ComputedValue = CurChannel.EvaluateWithBase(ComputedValue, Parameters);
```

```
BaseValue=100
  Channel0: Add+50        → 150
  Channel1: Override=200  → 200   ← Channel0 결과(150) 무시, 200으로 덮어씀
  Channel2: Add+10        → 210   ← Override된 200에 추가 보정 가능
```

Override는 같은 Channel 안의 계산만 건너뛴다. 다음 Channel의 계산은 막지 못한다.

Channel0~Channel9까지 10개 슬롯이 있으며, `AbilitySystemGlobals`에서 활성화해야 사용 가능하다. 대부분의 게임에서는 Channel0만 쓴다.

---

### Modifier와 태그의 관계

> 소스: `GameplayEffectAggregator.h:55`, `GameplayEffectAggregator.cpp:28`

태그와 Modifier의 관계는 두 종류다.

#### 관계 1 — Modifier의 집산 포함 여부를 태그로 제어

`FAggregatorMod`(Aggregator에 쌓이는 Modifier 단위)는 태그 조건을 갖는다.

```cpp
// GameplayEffectAggregator.h:57
struct FAggregatorMod
{
    const FGameplayTagRequirements* SourceTagReqs;  // Source가 가져야 할 태그 조건
    const FGameplayTagRequirements* TargetTagReqs;  // Target이 가져야 할 태그 조건
    float EvaluatedMagnitude;
    mutable bool IsQualified;   // 이 Modifier가 집산에 포함되는지 여부
};
```

`UpdateQualifies()`가 Source/Target의 현재 태그를 조건과 비교해 `IsQualified`를 결정한다.

```cpp
// GameplayEffectAggregator.cpp:33
bool bSourceMet = (!SourceTagReqs || SourceTagReqs->IsEmpty())
                  || SourceTagReqs->RequirementsMet(SrcTags);
bool bTargetMet = (!TargetTagReqs || TargetTagReqs->IsEmpty())
                  || TargetTagReqs->RequirementsMet(TgtTags);
IsQualified = bSourceMet && bTargetMet && ...;
```

집산 시 `SumMods()`는 `Qualifies()`가 true인 Modifier만 합산에 포함한다.

```cpp
for (const FAggregatorMod& Mod : InMods)
{
    if (Mod.Qualifies())   // false면 이 Modifier는 무시
        Sum += (Mod.EvaluatedMagnitude - Bias);
}
```

**사용 예**: "독 상태(Tag: Status.Poisoned)일 때만 방어력 감소 Modifier 적용"처럼 상황에 따라 Modifier를 선택적으로 켜고 끌 수 있다.

#### 관계 2 — AttributeBased Modifier의 TagFilter

`Attribute Based` Modifier가 Source Attribute 값을 읽을 때, 그 Attribute에 영향을 주는 Modifier 중 특정 태그를 가진 것만 포함하거나 제외하는 필터다.

```cpp
// GameplayEffectAggregator.cpp:62
const FGameplayTagContainer* SourceTags =
    HandleComponent->GetGameplayEffectSourceTagsFromHandle(ActiveHandle);
bSourceFilterMet = (SourceTags && SourceTags->HasAll(Parameters.AppliedSourceTagFilter));
```

**사용 예**: "내 공격력 계산 시 장비 버프 GE에서 온 Modifier만 제외하고 계산"처럼 세밀한 Attribute 값 필터링에 쓴다.

#### 핵심 — 태그 조건 평가 타이밍

Modifier의 태그 조건은 **GE Apply 시점에 한 번만 평가**된다.

```
GE Apply 시:  Modifier가 Aggregator에 등록 → 태그 조건 체크 → IsQualified 결정
이후:         태그가 바뀌어도 IsQualified 재계산 없음

예시:
  Apply 시 Target에 "Shield" 태그 있음 → IsQualified = true
  나중에 Shield 태그 제거됨
  Attribute 집산 시: IsQualified = true 그대로 → Modifier 여전히 적용
```

적용 이후 태그 변화에 반응하려면 Modifier 태그 조건이 아니라 `OngoingTagRequirements`(GE 전체를 켜고 끄는 것)를 써야 한다.
