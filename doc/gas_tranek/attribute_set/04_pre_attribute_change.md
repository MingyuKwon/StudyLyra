# PreAttributeChange()

> **GASDoc**: 4.4.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-preattributechange"></a>
#### 4.4.5 PreAttributeChange()

`PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)`는 `AttributeSet`에서 `Attribute`의 `CurrentValue` 변경에 응답하는 주요 함수 중 하나로, 변경이 일어나기 **전에** 호출된다. 참조 파라미터 `NewValue`를 통해 들어오는 `CurrentValue` 변경을 클램핑하기에 이상적인 위치다.

예를 들어, 샘플 프로젝트에서 이동속도 Modifier를 클램핑하는 방식은 다음과 같다:
```c++
if (Attribute == GetMoveSpeedAttribute())
{
	// Cannot slow less than 150 units/s and cannot boost more than 1000 units/s
	NewValue = FMath::Clamp<float>(NewValue, 150, 1000);
}
```
`GetMoveSpeedAttribute()` 함수는 `AttributeSet.h`에 추가한 매크로 블록(Attribute 선언)에 의해 생성된다.

이 함수는 `Attribute` setter(Attribute 선언의 매크로 블록에 의해 정의된)를 사용하거나 `GameplayEffect`를 통한 것 등 `Attribute`의 모든 변경에서 발동된다.

> **참고**  
> 여기서 수행하는 클램핑은 `ASC`의 Modifier를 영구적으로 변경하지 않는다. 단지 Modifier를 쿼리할 때 반환되는 값만 변경할 뿐이다. 즉, `GameplayEffectExecutionCalculations`나 `ModifierMagnitudeCalculations`처럼 모든 Modifier에서 `CurrentValue`를 재계산하는 코드에서는 클램핑을 별도로 구현해야 한다.

> **참고**  
> Epic의 `PreAttributeChange()`에 대한 주석에는 게임플레이 이벤트에는 사용하지 말고 주로 클램핑 용도로만 사용하라고 명시되어 있다. `Attribute` 변경에 대한 게임플레이 이벤트의 권장 위치는 `UAbilitySystemComponent::GetGameplayAttributeValueChangeDelegate(FGameplayAttribute Attribute)`(Attribute 변경에 응답하기)이다.

---

