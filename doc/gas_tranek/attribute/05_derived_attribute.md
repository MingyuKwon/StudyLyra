# Derived Attribute

> **GASDoc**: 4.3.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-derived"></a>
#### 4.3.5 Derived Attribute

하나 이상의 다른 Attribute로부터 일부 또는 전체 값을 파생하는 Attribute를 만들려면 하나 이상의 `Attribute Based` 또는 `MMC` `Modifier`를 가진 `Infinite` GameplayEffect를 사용한다. Derived Attribute는 의존하는 Attribute가 업데이트되면 자동으로 갱신된다.

Derived Attribute의 모든 Modifier에 대한 최종 공식은 Modifier Aggregator와 동일한 공식을 사용한다. 특정 순서로 계산이 이루어져야 한다면 MMC 내부에서 모두 처리한다.

```
((CurrentValue + Additive) * Multiplicitive) / Division
```

> **참고**  
> PIE에서 여러 클라이언트로 플레이할 때는 에디터 설정에서 `Run Under One Process`를 비활성화해야 한다. 활성화 상태에서는 첫 번째 클라이언트 이외의 클라이언트에서 독립 Attribute가 업데이트될 때 Derived Attribute가 갱신되지 않는다.

아래 예시는 `TestAttrA = (TestAttrA + TestAttrB) * ( 2 * TestAttrC)` 공식으로 `TestAttrA`의 값을 `TestAttrB`와 `TestAttrC` Attribute로부터 파생하는 `Infinite` GameplayEffect를 보여준다. `TestAttrA`는 어느 Attribute라도 값이 변경될 때마다 자동으로 재계산된다.

![Derived Attribute Example](https://github.com/tranek/GASDocumentation/raw/master/Images/derivedattribute.png)

---

`Derived Attribute`는 GASDoc이 붙인 **패턴 이름**이지, 별도의 타입이나 클래스가 아니다.
엔진에 `FDerivedAttribute` 같은 건 없고, 구조체도 똑같은 `FGameplayAttributeData`다.

용도는 다른 Attribute의 값으로부터 자동 계산되는 Attribute가 필요할 때다.

```
AttackPower = BaseAttack + (Strength * 2)
MaxHealth   = BaseHP + (Endurance * 10)
```

코드에서 직접 계산하면 `Strength`가 바뀔 때마다 `AttackPower`를 수동으로 갱신해야 한다.
이 패턴을 쓰면 **자동으로 재계산**된다.

구현은 단순하다 — 평범한 Attribute에 Infinite GE 하나를 항상 붙여두는 것뿐이다.

```
AttackPower Attribute (평범한 FGameplayAttributeData)
  + Infinite GE: Modifier = "Strength * 2를 Add"
```

자동 재계산이 가능한 이유는 Aggregator 때문이다.
Infinite GE의 Modifier가 Aggregator에 등록되면, Aggregator는 의존 Attribute(`Strength`)가 바뀔 때 `OnDirty`를 받아 `AttackPower`를 즉시 재계산한다.
부모-자식 링크처럼 보이지만 실제로는 Aggregator가 의존 관계를 추적하는 것이다.

`PostAttributeChange`에서 수동으로 구현할 수도 있지만, 버프가 `Strength`를 건드렸다 제거될 때 `AttackPower`도 함께 원복해야 하는 등 직접 관리 비용이 크다.
Infinite GE + Aggregator 방식은 이를 GAS가 전부 대신 처리하는 공식 패턴이다.

