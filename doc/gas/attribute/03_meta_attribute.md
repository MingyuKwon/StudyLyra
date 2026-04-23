# Meta Attribute

> **GASDoc**: 4.3.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-meta"></a>
#### 4.3.3 Meta Attribute

일부 Attribute는 다른 Attribute와 상호작용하기 위한 임시 값의 플레이스홀더로 취급된다. 이를 `Meta Attribute`라고 한다. 예를 들어 우리는 흔히 데미지를 Meta Attribute로 정의한다. GameplayEffect가 체력 Attribute를 직접 변경하는 대신, `Damage`라는 Meta Attribute를 플레이스홀더로 사용한다. 이렇게 하면 데미지 값을 [`GameplayEffectExecutionCalculation`](#concepts-ge-ec)에서 버프와 디버프로 조정할 수 있고, 최종적으로 체력 Attribute에서 나머지를 차감하기 전에 현재 방어막 Attribute에서 데미지를 먼저 차감하는 등 AttributeSet에서 추가 조작이 가능하다. `Damage` Meta Attribute는 GameplayEffect 사이에서 값이 유지되지 않으며, 매번 덮어써진다. Meta Attribute는 일반적으로 복제되지 않는다.

Meta Attribute는 데미지나 힐링과 같은 것들에 대해 "얼마나 피해를 줬는가?"와 "이 피해를 어떻게 처리할 것인가?" 사이의 논리적 분리를 제공한다. 이 논리적 분리 덕분에 Gameplay Effect와 Execution Calculation은 Target이 데미지를 어떻게 처리하는지 알 필요가 없다. 데미지 예시를 이어가면, Gameplay Effect가 데미지의 양을 결정하고, AttributeSet이 그 데미지를 어떻게 처리할지 결정한다. 모든 캐릭터가 같은 Attribute를 갖지 않을 수 있는데, 특히 서브클래싱된 AttributeSet을 사용하는 경우 그렇다. 기본 AttributeSet 클래스는 체력 Attribute만 가질 수 있지만, 서브클래싱된 AttributeSet은 방어막 Attribute를 추가할 수 있다. 방어막 Attribute를 가진 서브클래싱 AttributeSet은 기본 AttributeSet 클래스와 다른 방식으로 받은 데미지를 분배할 것이다.

Meta Attribute는 좋은 설계 패턴이지만 필수는 아니다. 모든 데미지 인스턴스에 Execution Calculation 하나만 사용하고 모든 캐릭터가 하나의 AttributeSet 클래스를 공유한다면, Execution Calculation 내부에서 체력, 방어막 등에 데미지를 분배하고 해당 Attribute를 직접 수정해도 무방하다. 유연성을 희생하는 것이지만, 그것으로 충분할 수도 있다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
