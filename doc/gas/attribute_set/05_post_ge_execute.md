# PostGameplayEffectExecute()

> **GASDoc**: 4.4.6 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-as-postgameplayeffectexecute"></a>
#### 4.4.6 PostGameplayEffectExecute()

`PostGameplayEffectExecute(const FGameplayEffectModCallbackData & Data)`는 인스턴트 [`GameplayEffect`](#concepts-ge)에 의해 `Attribute`의 `BaseValue`가 변경된 **이후에만** 발동된다. `GameplayEffect`로 인한 `Attribute` 변경 시 추가적인 `Attribute` 조작을 수행하기에 적합한 위치다.

예를 들어, 샘플 프로젝트에서는 이 함수에서 최종 피해 `Meta Attribute`를 Health `Attribute`에서 차감한다. 방어막(Shield) `Attribute`가 있다면 먼저 방어막에서 피해를 차감하고 나머지를 Health에서 차감한다. 또한 샘플 프로젝트는 이 위치를 피격 반응 애니메이션 재생, 부유 피해 숫자(Floating Damage Numbers) 표시, 처치자에게 경험치와 골드 보상 지급에도 활용한다. 설계상 피해 `Meta Attribute`는 항상 인스턴트 `GameplayEffect`를 통해 전달되며, `Attribute` setter를 통해 직접 설정되지 않는다.

Mana나 Stamina처럼 인스턴트 `GameplayEffect`로만 `BaseValue`가 변경되는 다른 `Attribute`들도 이 시점에 최대값에 해당하는 `Attribute`에 맞춰 클램핑할 수 있다.

> **참고**  
> `PostGameplayEffectExecute()`가 호출될 때, `Attribute`의 변경은 이미 이루어진 상태이지만 아직 클라이언트에 복제되지 않은 상태다. 따라서 여기서 값을 클램핑해도 클라이언트에 두 번의 네트워크 업데이트가 발생하지 않는다. 클라이언트는 클램핑 이후의 값만 받게 된다.

---

## 내 분석
