# OnAttributeAggregatorCreated()

> **GASDoc**: 4.4.7 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-onattributeaggregatorcreated"></a>
#### OnAttributeAggregatorCreated()를 활용해 여러 디버프 중 가장 강한 것만 적용하려면 어떻게 하는가?

`OnAttributeAggregatorCreated(const FGameplayAttribute& Attribute, FAggregator* NewAggregator)`는 Attribute에 대한 `Aggregator`가 생성될 때 호출된다. 이 함수에서 `FAggregatorEvaluateMetaData`를 커스텀 설정하면 `Aggregator`가 `CurrentValue`를 평가할 때 어떤 Modifier를 적용할지 제어할 수 있다.

**사용 사례 — 가장 강한 슬로우 하나만 적용 (Paragon 방식)**

`FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods`를 사용하면 음수 Modifier 중 가장 큰 것 하나만 적용하고, 양수 Modifier는 모두 적용한다. 슬로우 디버프가 여러 개 걸려 있어도 가장 강한 것 하나만 실제 이동속도에 반영된다.

자격을 얻지 못한 Modifier는 ASC에 계속 존재하며, 조건이 변경되면(예: 가장 강한 슬로우가 만료되면) 그 다음 Modifier가 자동으로 자격을 얻는다.

```c++
// 헤더
virtual void OnAttributeAggregatorCreated(const FGameplayAttribute& Attribute, FAggregator* NewAggregator) const override;
```

```c++
// .cpp
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

커스텀 `AggregatorEvaluateMetaData`가 필요하다면 `FAggregatorEvaluateMetaDataLibrary`에 정적 변수로 추가한다.

---
