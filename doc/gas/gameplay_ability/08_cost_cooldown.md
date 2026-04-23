# Cost & Cooldown

> **GASDoc**: 4.6.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-commit"></a>
#### 4.6.12 Ability Cost and Cooldown

`GameplayAbility`에는 선택적인 비용(Cost)과 쿨다운(Cooldown) 기능이 내장되어 있다. Cost는 `GameplayAbility`를 활성화하기 위해 ASC가 보유해야 하는 미리 정의된 Attribute 양이며, `Instant` `GameplayEffect`([`Cost GE`](#concepts-ge-cost))로 구현된다. Cooldown은 `GameplayAbility`의 재활성화를 만료될 때까지 방지하는 타이머이며, `Duration` `GameplayEffect`([`Cooldown GE`](#concepts-ge-cooldown))로 구현된다.

`GameplayAbility`는 `UGameplayAbility::Activate()`를 호출하기 전에 `UGameplayAbility::CanActivateAbility()`를 먼저 호출한다. 이 함수는 owning ASC가 Cost를 감당할 수 있는지(`UGameplayAbility::CheckCost()`)와 GameplayAbility가 쿨다운 중인지 아닌지(`UGameplayAbility::CheckCooldown()`)를 확인한다.

`GameplayAbility`가 `Activate()`를 호출한 이후에는 `UGameplayAbility::CommitAbility()`를 원하는 시점에 호출하여 Cost와 Cooldown을 선택적으로 커밋할 수 있다. `CommitAbility()`는 내부적으로 `UGameplayAbility::CommitCost()`와 `UGameplayAbility::CommitCooldown()`을 호출한다. 디자이너가 두 커밋을 동시에 하지 않아야 하는 경우에는 `CommitCost()`와 `CommitCooldown()`을 별도로 호출하는 것도 가능하다. Cost와 Cooldown을 커밋할 때 `CheckCost()`와 `CheckCooldown()`이 한 번 더 실행되며, 이것이 해당 항목으로 인해 `GameplayAbility`가 실패할 수 있는 마지막 기회다. `GameplayAbility`가 활성화된 이후에 owning ASC의 Attribute가 변경되어 커밋 시점에 Cost를 충족하지 못할 수 있기 때문이다. 커밋 시점에 [Prediction Key](#concepts-p-key)가 유효하다면 Cost와 Cooldown의 커밋도 [로컬 예측](#concepts-p)이 가능하다.

구현 세부 사항은 [`CostGE`](#concepts-ge-cost)와 [`CooldownGE`](#concepts-ge-cooldown) 항목을 참고할 것.

<a name="concepts-ga-leveling"></a>
#### 4.6.13 Leveling Up Abilities

어빌리티를 레벨업하는 방법에는 두 가지가 있다.

| 레벨업 방법                                    | 설명                                                                                                                                                                                                                       |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ungrant 후 새 레벨로 Regrant                   | 서버에서 ASC의 `GameplayAbility`를 제거(Ungrant)하고, 다음 레벨로 다시 부여(Regrant)한다. 이 시점에 GameplayAbility가 활성화 중이었다면 종료된다.                                                                          |
| `GameplayAbilitySpec`의 레벨 증가              | 서버에서 `GameplayAbilitySpec`을 찾아 레벨을 증가시키고 dirty 표시를 하여 owning client로 복제한다. 이 방법은 활성화 중인 `GameplayAbility`를 종료시키지 않는다.                                                            |

두 방법의 핵심적인 차이는 레벨업 시점에 활성화 중인 `GameplayAbility`를 취소할 것인지 여부다. `GameplayAbility`에 따라 두 방법 모두 사용하게 될 가능성이 높다. `UGameplayAbility` 서브클래스에 어떤 방법을 사용할지 지정하는 `bool` 변수를 추가하는 것을 권장한다.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-sets"></a>
#### 4.6.14 Ability Sets

`GameplayAbilitySet`은 캐릭터의 초기 `GameplayAbility` 목록과 입력 바인딩을 보관하고, GameplayAbility를 부여하는 로직을 포함하는 편의용 `UDataAsset` 클래스다. 서브클래스에는 추가적인 로직이나 프로퍼티를 포함할 수도 있다. Paragon에서는 각 영웅마다 자신의 모든 `GameplayAbility`를 포함하는 `GameplayAbilitySet`이 존재했다.

GASDoc 저자 기준으로 이 클래스는 불필요하다고 판단한다. 샘플 프로젝트는 `GDCharacterBase`와 그 서브클래스에서 `GameplayAbilitySet`의 모든 기능을 직접 처리하고 있다.

**[⬆ Back to Top](#table-of-contents)**
---

## 내 분석
