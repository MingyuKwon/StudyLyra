# AttributeSet 정의 & 설계

> **GASDoc**: 4.4.1~4.4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as"></a>
### AttributeSet은 무엇이며, ASC와 어떤 관계인가?

`AttributeSet`은 Attribute들을 정의하고, 보유하며, 변경을 관리하는 클래스다. `UAttributeSet`을 상속해 구현하며, `OwnerActor`의 생성자에서 생성하면 해당 ASC에 자동으로 등록된다. **반드시 C++로 구현해야 한다.**

<a name="concepts-as-definition"></a>
#### AttributeSet을 정의하고 ASC에 등록하는 방법은?

`OwnerActor`의 생성자에서 `AttributeSet`을 `CreateDefaultSubobject`로 생성하면 ASC에 자동 등록된다. 별도의 등록 호출은 필요하지 않다.

<a name="concepts-as-design"></a>
#### AttributeSet을 하나로 통합해야 하는가, 여러 개로 분리해야 하는가?

두 방식 모두 허용된다. `AttributeSet`의 메모리 오버헤드는 매우 작으므로 조직적 판단에 따라 결정한다.

| 방식 | 설명 |
|------|------|
| 단일 모놀리식 | 모든 Actor가 하나의 큰 `AttributeSet` 공유, 불필요한 Attribute는 무시 |
| 역할별 분리 | Health용, Mana용 등 별도 `AttributeSet`으로 나누고 필요한 Actor에만 부여 |
| 서브클래싱 | 부모 `AttributeSet`을 상속해 선택적으로 구성 (단, Attribute 참조 시 부모 클래스명이 접두사로 붙음) |

**주의**: 동일한 클래스의 `AttributeSet`을 ASC에 두 개 이상 등록하면 안 된다. 어느 것을 사용할지 판단하지 못하고 임의로 하나를 선택한다.

<a name="concepts-as-design-subcomponents"></a>
##### 피해받는 부위가 여러 개인 컴포넌트에 Attribute를 어떻게 설계해야 하는가?

피해 가능한 컴포넌트 수만큼의 Health Attribute(예: `DamageableCompHealth0`, `DamageableCompHealth1`)를 하나의 `AttributeSet`에 슬롯으로 정의한다. 컴포넌트 인스턴스에서 슬롯 번호 Attribute를 할당하고, GA나 Execution에서 해당 번호를 읽어 어느 Attribute에 피해를 줄지 결정한다.

사용하지 않는 Attribute는 메모리를 거의 차지하지 않으므로, 컴포넌트가 없는 Actor에 이 `AttributeSet`이 존재해도 문제없다.

단, 다음 경우에는 Attribute 대신 **컴포넌트에 float를 직접 저장**하는 방식으로 전환을 권장한다.
- 서브컴포넌트마다 많은 수의 Attribute가 필요한 경우
- 서브컴포넌트 수가 무한정 늘어날 가능성이 있는 경우
- 다른 플레이어가 떼어 사용할 수 있는 아이템(예: 무기)인 경우

<a name="concepts-as-design-addremoveruntime"></a>
##### 런타임에 AttributeSet을 추가하거나 제거할 때 어떤 위험이 있는가?

**제거는 크래시 위험이 있다.** 클라이언트에서 서버보다 먼저 `AttributeSet`이 제거된 상태에서 Attribute 변경이 복제되면, 클라이언트가 해당 `AttributeSet`을 찾지 못해 크래시된다.

추가/제거 후에는 반드시 `ForceReplication()`을 호출해 클라이언트에 동기화한다.

```c++
// 추가
AbilitySystemComponent->GetSpawnedAttributes_Mutable().AddUnique(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();

// 제거
AbilitySystemComponent->GetSpawnedAttributes_Mutable().Remove(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();
```

---
