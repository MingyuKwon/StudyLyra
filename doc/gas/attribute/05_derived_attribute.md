# Derived Attribute

> **GASDoc**: 4.3.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-derived"></a>
#### 4.3.5 Derived Attribute

하나 이상의 다른 Attribute로부터 일부 또는 전체 값을 파생하는 Attribute를 만들려면 하나 이상의 `Attribute Based` 또는 [`MMC`](#concepts-ge-mmc) [`Modifier`](#concepts-ge-mods)를 가진 `Infinite` GameplayEffect를 사용한다. Derived Attribute는 의존하는 Attribute가 업데이트되면 자동으로 갱신된다.

Derived Attribute의 모든 Modifier에 대한 최종 공식은 Modifier Aggregator와 동일한 공식을 사용한다. 특정 순서로 계산이 이루어져야 한다면 MMC 내부에서 모두 처리한다.

```
((CurrentValue + Additive) * Multiplicitive) / Division
```

> **참고**  
> PIE에서 여러 클라이언트로 플레이할 때는 에디터 설정에서 `Run Under One Process`를 비활성화해야 한다. 활성화 상태에서는 첫 번째 클라이언트 이외의 클라이언트에서 독립 Attribute가 업데이트될 때 Derived Attribute가 갱신되지 않는다.

아래 예시는 `TestAttrA = (TestAttrA + TestAttrB) * ( 2 * TestAttrC)` 공식으로 `TestAttrA`의 값을 `TestAttrB`와 `TestAttrC` Attribute로부터 파생하는 `Infinite` GameplayEffect를 보여준다. `TestAttrA`는 어느 Attribute라도 값이 변경될 때마다 자동으로 재계산된다.

![Derived Attribute Example](https://github.com/tranek/GASDocumentation/raw/master/Images/derivedattribute.png)

---

## 내 분석

### Derived Attribute는 별도 타입이 아니다

`Derived Attribute`는 GASDoc이 붙인 **패턴 이름**이다.
엔진 코드에 `FDerivedAttribute` 같은 클래스나 타입은 없고, 구조체도 똑같은 `FGameplayAttributeData`다.

실제로 하는 일은 이것뿐이다:

```
AttackPower라는 평범한 Attribute를 만든다
  + Infinite GE 하나를 항상 붙여둔다
  + 그 GE의 Modifier를 "Strength 값 * 2를 Add해라"로 설정한다
```

부모-자식처럼 특별한 링크가 있는 게 아니라, Aggregator가 "이 Attribute를 계산할 때 Strength를 참조하라"는 정보를 갖고 있을 뿐이다.
Strength가 바뀌면 Aggregator가 감지하고 AttackPower를 재계산한다.

**Derived Attribute = 평범한 Attribute + Infinite GE 패턴**이다.

---

### Derived Attribute가 뭘 위한 건가

다른 Attribute의 값에서 자동으로 계산되는 Attribute가 필요할 때 쓴다.

```
AttackPower = BaseAttack + (Strength * 2)
MaxHealth   = BaseHP + (Endurance * 10)
CritChance  = BaseCrit + (Agility * 0.5)
```

이런 값을 코드에서 직접 계산하면 `Strength`가 바뀔 때마다 `AttackPower`를 수동으로 갱신해야 한다.
Derived Attribute로 만들면 `Strength`가 바뀌는 순간 `AttackPower`가 **자동으로 재계산**된다.

### 왜 Infinite GE를 통해서만 하는가

핵심은 **Aggregator**다.
Infinite GE의 Modifier는 Aggregator에 등록되고, Aggregator는 의존 Attribute가 바뀔 때 자동으로 `OnDirty` 이벤트를 받아 재계산을 트리거한다.
개발자가 "언제 재계산할지"를 관리할 필요가 없다.

```
Strength Attribute 변경
  → Aggregator: "AttackPower에 Strength 기반 Modifier가 있다" 감지
  → AttackPower Aggregator OnDirty
  → AttackPower CurrentValue 재계산
```

### GE 없이도 할 수 있는가

기술적으로는 가능하다.
`PostAttributeChange`에서 `Strength`가 바뀔 때 `AttackPower`를 직접 세팅하면 된다.
하지만:

- 의존 관계를 수동 관리해야 함
- 버프가 `Strength`를 건드리면 버프 제거 시 `AttackPower`도 수동으로 원복해야 함
- Aggregator가 알아서 해주는 것을 전부 직접 구현하는 셈

Infinite GE + Attribute Based Modifier 방식은 이 모든 것을 GAS가 대신 처리해주는 공식 패턴이다.
