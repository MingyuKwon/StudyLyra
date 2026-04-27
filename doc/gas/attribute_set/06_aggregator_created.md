# OnAttributeAggregatorCreated()

> **GASDoc**: 4.4.7 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-as-onattributeaggregatorcreated"></a>
#### 4.4.7 OnAttributeAggregatorCreated()

`OnAttributeAggregatorCreated(const FGameplayAttribute& Attribute, FAggregator* NewAggregator)`는 이 AttributeSet 내 `Attribute`에 대해 `Aggregator`가 생성될 때 발동된다. 이 함수를 통해 [`FAggregatorEvaluateMetaData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FAggregatorEvaluateMetaData/index.html)를 커스텀 설정할 수 있다. `AggregatorEvaluateMetaData`는 `Aggregator`가 적용된 모든 `Modifier`를 기반으로 `Attribute`의 `CurrentValue`를 평가할 때 어떤 Modifier가 조건을 충족하는지 결정하는 데 사용된다. 기본적으로 `AggregatorEvaluateMetaData`는 `MostNegativeMod_AllPositiveMods`를 예시로 하여, 모든 양수 Modifier는 허용하되 음수 Modifier는 가장 음수인 것 하나만 허용하는 조건에서 어떤 Modifier가 자격을 갖추는지 결정하기 위해 `Aggregator`에서만 사용된다. Paragon은 이를 활용하여 플레이어에게 슬로우 효과가 몇 개나 걸려 있더라도 가장 강한 이동속도 감속 효과 하나만 적용하면서, 모든 양수 이동속도 버프는 모두 적용시켰다. 자격을 갖추지 못한 Modifier들은 여전히 `ASC`에 존재하며, 단지 최종 `CurrentValue`로 집계되지 않을 뿐이다. 조건이 변경되면(예: 가장 음수인 Modifier가 만료되면) 그 다음으로 음수인 Modifier(존재하는 경우)가 자격을 얻는다.

가장 음수인 Modifier와 모든 양수 Modifier만 허용하는 예시에서 `AggregatorEvaluateMetaData`를 사용하려면:

```c++
virtual void OnAttributeAggregatorCreated(const FGameplayAttribute& Attribute, FAggregator* NewAggregator) const override;
```

```c++
void UGSAttributeSetBase::OnAttributeAggregatorCreated(const FGameplayAttribute& Attribute, FAggregator* NewAggregator) const
{
	Super::OnAttributeAggregatorCreated(Attribute, NewAggregator);

	if (!NewAggregator)
	{
		return;
	}

	if (Attribute == GetMoveSpeedAttribute())
	{
		NewAggregator->EvaluationMetaData = &FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods;
	}
}
```

조건 판별을 위한 커스텀 `AggregatorEvaluateMetaData`는 `FAggregatorEvaluateMetaDataLibrary`에 정적 변수로 추가해야 한다.

---

## 내 분석
