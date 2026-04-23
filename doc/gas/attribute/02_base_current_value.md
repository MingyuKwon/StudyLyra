# BaseValue vs CurrentValue

> **GASDoc**: 4.3.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-value"></a>
#### 4.3.2 BaseValue vs CurrentValue

Attribute는 두 개의 값으로 구성된다. `BaseValue`는 Attribute의 영구적인 값이며, `CurrentValue`는 BaseValue에 GameplayEffect에 의한 임시 수정값을 더한 값이다. 예를 들어 캐릭터의 이동속도 Attribute의 BaseValue가 600 units/second라면, GameplayEffect가 이동속도를 수정하지 않는 한 CurrentValue도 600 u/s다. 여기에 임시 50 u/s 이동속도 버프를 받으면 BaseValue는 600 u/s로 유지되고 CurrentValue는 600 + 50으로 총 650 u/s가 된다. 이동속도 버프가 만료되면 CurrentValue는 다시 BaseValue인 600 u/s로 돌아간다.

GAS를 처음 접하는 사람들은 종종 BaseValue를 Attribute의 최대값으로 혼동하고 그렇게 다루려 한다. 이는 잘못된 접근이다. 어빌리티나 UI에서 참조할 수 있는 변동 가능한 최대값은 별도의 Attribute로 처리해야 한다. 하드코딩된 최대값과 최소값의 경우, 최대값과 최소값을 설정할 수 있는 `FAttributeMetaData`와 함께 `DataTable`을 정의하는 방법이 있지만, Epic의 해당 구조체 위 주석에 "작업 중(work in progress)"이라고 명시되어 있다. 자세한 내용은 `AttributeSet.h`를 참고한다. 혼란을 피하기 위해, 어빌리티나 UI에서 참조할 수 있는 최대값은 별도의 Attribute로 만들고, Attribute 클램핑에만 사용되는 하드코딩 최대값과 최소값은 AttributeSet의 하드코딩 float으로 정의하는 것을 권장한다. Attribute의 클램핑은 CurrentValue 변경 시 [PreAttributeChange()](#concepts-as-preattributechange)에서, GameplayEffect에 의한 BaseValue 변경 시 [PostGameplayEffectExecute()](#concepts-as-postgameplayeffectexecute)에서 처리한다.

`Instant` GameplayEffect는 BaseValue를 영구적으로 변경하며, `Duration`과 `Infinite` GameplayEffect는 CurrentValue를 변경한다. `Periodic` GameplayEffect는 Instant GameplayEffect처럼 취급되어 BaseValue를 변경한다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
