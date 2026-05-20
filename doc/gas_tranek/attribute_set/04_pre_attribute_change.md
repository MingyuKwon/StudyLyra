# PreAttributeChange()

> **GASDoc**: 4.4.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-preattributechange"></a>
#### PreAttributeChange()는 언제 호출되며, 어떤 용도로만 써야 하는가?

`PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)`는 Attribute의 `CurrentValue`가 변경되기 **직전**에 호출된다. 참조 파라미터 `NewValue`를 수정하면 실제 적용 값을 변경할 수 있어, **클램핑 용도**로 사용하기에 적합하다.

```c++
if (Attribute == GetMoveSpeedAttribute())
{
	// 최솟값 150, 최댓값 1000으로 클램핑
	NewValue = FMath::Clamp<float>(NewValue, 150, 1000);
}
```

Attribute setter 또는 GE를 통한 모든 변경에서 발동된다.

**주의사항 두 가지:**

1. **클램핑은 ASC의 Modifier를 영구 변경하지 않는다.** Modifier 쿼리 시 반환값만 변경한다. `GameplayEffectExecutionCalculation`이나 `ModifierMagnitudeCalculation`처럼 모든 Modifier에서 `CurrentValue`를 재계산하는 코드에서는 클램핑을 별도로 구현해야 한다.

2. **게임플레이 이벤트에는 사용하지 않는다.** Epic의 공식 주석에도 클램핑 용도로만 사용하라고 명시되어 있다. Attribute 변경에 반응하는 게임플레이 이벤트는 `UAbilitySystemComponent::GetGameplayAttributeValueChangeDelegate()`를 사용한다.

---
