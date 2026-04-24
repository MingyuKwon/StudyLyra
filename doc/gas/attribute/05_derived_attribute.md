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
