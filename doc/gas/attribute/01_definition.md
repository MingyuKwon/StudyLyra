# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-definition"></a>
#### 4.3.1 Attribute 정의

`Attribute`는 [`FGameplayAttributeData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayAttributeData/index.html) 구조체로 정의되는 float 값이다. 캐릭터의 체력, 캐릭터의 레벨, 포션의 충전 횟수 등 무엇이든 표현할 수 있다. Actor에 속하는 게임플레이 관련 수치라면 Attribute 사용을 고려해야 한다. Attribute는 ASC가 변경 사항을 [예측(predict)](#concepts-p)할 수 있도록 원칙적으로 [`GameplayEffect`](#concepts-ge)를 통해서만 수정해야 한다.

Attribute는 [`AttributeSet`](#concepts-as) 안에 정의되고 소속된다. AttributeSet은 복제 대상으로 표시된 Attribute의 복제를 담당한다. Attribute를 정의하는 방법은 [`AttributeSet`](#concepts-as) 섹션을 참고한다.

**팁:** 에디터의 Attribute 목록에 표시하고 싶지 않은 Attribute는 `Meta = (HideInDetailsView)` 프로퍼티 지정자를 사용한다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
