# GE Modifier

> **GASDoc**: 4.5.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-mods"></a>
#### 4.5.4 Gameplay Effect Modifiers

Modifier는 Attribute를 변경하는 수단이며, [예측(Prediction)](#concepts-p)적으로 Attribute를 변경할 수 있는 **유일한 방법**이다. GE는 Modifier를 0개 이상 가질 수 있고, 각 Modifier는 지정된 연산을 통해 하나의 Attribute만 담당한다.

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

**참고:** 퍼센트 기반 변경은 덧셈 이후에 처리되도록 반드시 `Multiply` 연산을 사용해야 한다.

**참고:** [Prediction](#concepts-p)은 퍼센트 변경과 궁합이 좋지 않다.

Modifier의 종류는 Scalable Float, Attribute Based, Custom Calculation Class, Set By Caller의 네 가지다. 이들은 각각 float 값을 생성하며, 이 값이 Modifier의 연산에 따라 지정된 Attribute를 변경하는 데 사용된다.

| Modifier 타입              | 설명 |
| -------------------------- | ---- |
| `Scalable Float`           | `FScalableFloat`는 행이 변수, 열이 레벨인 DataTable을 참조하는 구조체다. 어빌리티의 현재 레벨([GameplayEffectSpec](#concepts-ge-spec)에서 재정의 가능)에 해당하는 테이블 행의 값을 자동으로 읽어온다. 이 값에는 계수(coefficient)를 추가로 적용할 수 있다. DataTable/행을 지정하지 않으면 값을 1로 취급하므로, 계수만으로 모든 레벨에서 고정 값을 하드코딩할 수 있다 |
| `Attribute Based`          | `Attribute Based` Modifier는 Source(GameplayEffectSpec을 생성한 쪽) 또는 Target(GameplayEffectSpec을 수신한 쪽)의 특정 Attribute의 `CurrentValue` 또는 `BaseValue`를 가져와, 계수와 계수 전후 가산값을 추가로 적용한다. **Snapshotting**: GameplayEffectSpec 생성 시점에 Attribute를 캡처하는 방식과, 적용 시점에 캡처하는 방식을 선택할 수 있다 |
| `Custom Calculation Class` | `Custom Calculation Class`는 복잡한 Modifier에 가장 높은 유연성을 제공한다. 이 Modifier는 [`ModifierMagnitudeCalculation`](#concepts-ge-mmc) 클래스를 사용하며, 결과 float 값에 계수와 계수 전후 가산값을 추가로 적용할 수 있다 |
| `Set By Caller`            | `SetByCaller` Modifier는 GameplayEffect 외부에서 런타임에 어빌리티 또는 GameplayEffectSpec 생성자가 GameplayEffectSpec에 직접 설정하는 값이다. 예를 들어, 플레이어가 버튼을 누르고 있는 시간에 따라 데미지를 설정하고 싶을 때 `SetByCaller`를 사용한다. `SetByCaller`는 기본적으로 GameplayEffectSpec에 저장되는 `TMap<FGameplayTag, float>`다. Modifier는 Aggregator에게 지정된 GameplayTag와 연결된 `SetByCaller` 값을 찾으라고 지시한다. Modifier에서 사용하는 `SetByCaller`는 GameplayTag 버전만 사용 가능하며, FName 버전은 사용할 수 없다. Modifier가 `SetByCaller`로 설정되어 있는데 GameplayEffectSpec에 올바른 GameplayTag가 존재하지 않으면, 게임은 런타임 에러를 발생시키고 0을 반환한다. `Divide` 연산의 경우 이로 인한 문제가 생길 수 있으니 주의가 필요하다. 자세한 사용법은 [`SetByCallers`](#concepts-ge-spec-setbycaller)를 참조 |

**[⬆ Back to Top](#table-of-contents)**

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
- `(1 미만의 값은 최대 1개)` AND `([1, 2) 범위 값은 여러 개 가능)`
- OR `(2 이상의 값 1개)`

공식의 Bias는 `[1, 2)` 범위 숫자들의 정수 자릿수를 빼는 역할을 한다. 첫 번째 Modifier의 Bias가 시작 Sum 값(루프 전에 Bias로 초기화)에서 빠지기 때문에, 값이 하나만 있을 때는 어떤 값이든 올바르게 동작하며, 1 미만 값 하나는 [1, 2) 범위의 값들과 함께 사용할 수 있다.

`Multiply` 예시:  
Multiplier: `0.5`  
`1 + (0.5 - 1) = 0.5`, 정확

Multiplier: `0.5, 0.5`  
`1 + (0.5 - 1) + (0.5 - 1) = 0`, 부정확 (예상값은 `1`). 1 미만 값 여러 개를 더하는 것은 Multiplier 합산 방식과 맞지 않는다. Paragon은 [가장 큰 음수 값만 Multiply Modifier로 사용](#cae-nonstackingge)하도록 설계되어 1 미만 값이 최대 하나만 BaseValue에 곱해지도록 했다.

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

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ge-mods-gameplaytags"></a>
##### 4.5.4.2 Modifier의 GameplayTag 조건

각 [Modifier](#concepts-ge-mods)에 대해 `SourceTags`와 `TargetTags`를 지정할 수 있다. 이 태그들은 GameplayEffect의 [`Application Tag Requirements`](#concepts-ge-tags)와 동일하게 동작한다. 즉, 태그 조건은 GE가 처음 적용되는 시점에만 평가된다. 다시 말해, 주기적으로 실행되는 Infinite GE의 경우, 최초 적용 시에는 태그 조건을 고려하지만 이후 각 주기 실행 시에는 재검사하지 않는다.

`Attribute Based` Modifier는 추가로 `SourceTagFilter`와 `TargetTagFilter`를 설정할 수 있다. `Attribute Based` Modifier의 Source Attribute 크기를 결정할 때, 이 필터는 해당 Attribute에 영향을 주는 특정 Modifier를 제외하는 데 사용된다. Source 또는 Target이 필터의 모든 태그를 보유하지 않은 Modifier는 제외된다.

더 자세히 설명하면: Source ASC와 Target ASC의 태그는 GameplayEffect에 의해 캡처된다. Source ASC의 태그는 GameplayEffectSpec 생성 시 캡처되고, Target ASC의 태그는 Effect 실행 시 캡처된다. Infinite 또는 Duration Effect의 Modifier가 적용 조건("qualifies")을 충족하는지 판단할 때(즉, Aggregator가 조건을 충족할 때), 해당 필터가 설정되어 있다면 캡처된 태그를 필터와 비교한다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
