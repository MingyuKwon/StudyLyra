# Ability System Component

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 어떤 Actor에 ASC를 붙일 수 있나?

Attribute(속성값)와 GameplayTag로 상호작용할 필요가 있는 모든 Actor에 `AbilitySystemComponent`(ASC)를 붙일 수 있다. 캐릭터나 차량 같은 조작 가능한 오브젝트뿐 아니라, 파괴 가능한 상자나 루팅 가능한 보물상자 같은 수동적인 오브젝트도 포함된다.

---

## 하나의 Actor에 ASC가 여러 개 붙을 수 있나?

**불가. 강력히 권장하지 않는다.** 엔진 코드 여러 곳에서 Actor당 ASC가 최대 하나라고 가정하고 있다.

- ASC 클래스는 소유 Actor의 `AttributeSet` 서브오브젝트를 자동으로 탐지해 GameplayAttribute로 등록한다. Actor에 ASC가 여러 개 있으면 모든 ASC가 동일한 AttributeSet을 중복 등록하게 된다.

- 어떤 Actor 클래스든 `IAbilitySystemInterface`를 구현하면 `AbilitySystemBlueprintLibrary` 등의 GAS 코드가 해당 Actor(또는 연결된 다른 Actor)의 ASC를 찾을 수 있다. ASC가 여러 개인 경우 이 인터페이스의 동작은 정의되지 않는다(undefined behavior).
