# AttributeSet 정의 & 설계

> **GASDoc**: 4.4.1~4.4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-as"></a>
### 4.4 Attribute Set

<a name="concepts-as-definition"></a>
#### 4.4.1 AttributeSet 정의

`AttributeSet`은 `Attribute`들을 정의하고, 보유하며, 변경을 관리한다. 개발자는 [`UAttributeSet`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UAttributeSet/index.html)을 상속하여 구현해야 한다. `OwnerActor`의 생성자에서 `AttributeSet`을 생성하면 해당 ASC에 자동으로 등록된다. **이 작업은 반드시 C++로 수행해야 한다.**

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-as-design"></a>
#### 4.4.2 AttributeSet 설계

ASC는 하나 또는 여러 개의 `AttributeSet`을 가질 수 있다. `AttributeSet`의 메모리 오버헤드는 매우 작으므로, 몇 개를 사용할지는 개발자의 조직적인 판단에 달려 있다.

게임의 모든 `Actor`가 하나의 큰 모놀리식 `AttributeSet`을 공유하고, 필요한 Attribute만 사용하고 나머지는 무시하는 방식도 허용된다.

또는 Attribute 그룹별로 `AttributeSet`을 분리하여 필요한 `Actor`에만 선택적으로 추가하는 방식도 있다. 예를 들어 Health 관련 `AttributeSet`, Mana 관련 `AttributeSet` 등을 별도로 둘 수 있다. MOBA 게임이라면 영웅에게는 Mana `AttributeSet`이 필요하지만 미니언에게는 불필요하므로, 영웅에만 Mana `AttributeSet`을 부여하면 된다.

또한 `AttributeSet`을 서브클래싱하여 어떤 Attribute를 가질지 선택적으로 구성하는 방법도 있다. Attribute는 내부적으로 `AttributeSetClassName.AttributeName` 형식으로 참조되므로, 서브클래스를 만들어도 부모 클래스의 Attribute 앞에는 여전히 부모 클래스 이름이 접두사로 붙는다.

`AttributeSet`을 여러 개 사용할 수는 있지만, 동일한 클래스의 `AttributeSet`을 ASC에 두 개 이상 등록해서는 안 된다. 같은 클래스의 `AttributeSet`이 두 개 이상 있으면, 어느 것을 사용할지 판단하지 못하고 임의로 하나를 선택하게 된다.

<a name="concepts-as-design-subcomponents"></a>
##### 4.4.2.1 개별 Attribute를 갖는 서브컴포넌트

`Pawn`에 개별적으로 피해를 받는 컴포넌트(예: 갑옷 부위별 피해 처리)가 여러 개 있는 경우, `Pawn`이 가질 수 있는 최대 컴포넌트 수만큼의 Health Attribute(DamageableCompHealth0, DamageableCompHealth1 등)를 하나의 `AttributeSet`에 논리적 '슬롯'으로 정의하는 방식을 권장한다. 그 다음 피해 가능한 컴포넌트 클래스 인스턴스에서 슬롯 번호 `Attribute`를 할당하고, `GameplayAbility`나 [`Execution`](#concepts-ge-ec)에서 해당 번호를 읽어 어느 `Attribute`에 피해를 줄지 결정하면 된다. 최대 수보다 적은 수의 피해 가능 컴포넌트를 가지거나 아예 없는 `Pawn`이 있어도 괜찮다. `AttributeSet`에 `Attribute`가 정의되어 있다고 해서 반드시 사용해야 하는 것은 아니며, 사용하지 않는 `Attribute`는 메모리를 거의 차지하지 않는다.

서브컴포넌트마다 많은 수의 `Attribute`가 필요하거나, 서브컴포넌트 수가 무한정 늘어날 가능성이 있거나, 다른 플레이어가 떼어 사용할 수 있는 경우(예: 무기), 또는 어떤 이유로든 이 방식이 적합하지 않다면 `Attribute` 대신 컴포넌트에 평범한 float를 저장하는 방식으로 전환하는 것을 권장한다. [Item Attributes](#concepts-as-design-itemattributes) 참고.

<a name="concepts-as-design-addremoveruntime"></a>
##### 4.4.2.2 런타임에 AttributeSet 추가/제거

`AttributeSet`은 런타임에 `ASC`에 추가하거나 제거할 수 있다. 그러나 **`AttributeSet`을 제거하는 것은 위험하다.** 예를 들어, 클라이언트에서 서버보다 먼저 `AttributeSet`이 제거된 상태에서 `Attribute` 값 변경이 클라이언트로 복제되면, 클라이언트는 해당 `AttributeSet`을 찾지 못해 게임이 크래시된다.

무기를 인벤토리에 추가할 때:
```c++
AbilitySystemComponent->GetSpawnedAttributes_Mutable().AddUnique(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();
```

무기를 인벤토리에서 제거할 때:
```c++
AbilitySystemComponent->GetSpawnedAttributes_Mutable().Remove(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();
```

---

## 내 분석
