# Derived Attribute

> **GASDoc**: 4.3.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-derived"></a>
#### 다른 Attribute의 값으로 자동 계산되는 Derived Attribute는 어떻게 구현하는가?

`Attribute Based` 또는 `MMC` Modifier를 가진 `Infinite` GE를 항상 붙여두는 것으로 구현한다. 의존 Attribute가 업데이트되면 자동으로 재계산된다.

별도 클래스나 타입이 있는 것이 아니다. 구조체는 똑같은 `FGameplayAttributeData`고, GASDoc이 붙인 패턴 이름이다.

```
AttackPower Attribute (평범한 FGameplayAttributeData)
  + Infinite GE: Modifier = "Strength * 2를 Add"
```

자동 재계산이 가능한 이유는 Aggregator 때문이다. Infinite GE Modifier가 Aggregator에 등록되면, Aggregator는 의존 Attribute(`Strength`)가 바뀔 때 `OnDirty`를 받아 `AttackPower`를 즉시 재계산한다.

Modifier 최종 계산 공식:
```
((CurrentValue + Additive) * Multiplicative) / Division
```

순서가 중요하면 MMC 내부에서 직접 처리한다.

아래 예시는 `TestAttrA = (TestAttrA + TestAttrB) * (2 * TestAttrC)` 공식이다.

![Derived Attribute Example](https://github.com/tranek/GASDocumentation/raw/master/Images/derivedattribute.png)

---

`PostAttributeChange`에서 수동으로 구현할 수도 있지만, 버프가 `Strength`를 건드렸다 제거될 때 `AttackPower`도 함께 원복해야 하는 등 직접 관리 비용이 크다. Infinite GE + Aggregator 방식은 이를 GAS가 전부 대신 처리한다.

> **PIE 주의:** 여러 클라이언트로 플레이할 때 `Run Under One Process`를 비활성화해야 한다. 활성화 상태에서는 첫 번째 클라이언트 이외에서 의존 Attribute 변경 시 Derived Attribute가 갱신되지 않는다.
