# Cost & Cooldown

> **GASDoc**: 4.6.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-commit"></a>
#### GA의 Cost와 Cooldown은 내부적으로 어떻게 구현되며, CommitAbility를 언제 호출해야 하는가?

- **Cost**: GA를 활성화하기 위해 ASC가 보유해야 하는 Attribute 양. `Instant GE`로 구현된다.
- **Cooldown**: GA의 재활성화를 방지하는 타이머. `Duration GE`로 구현된다.

`ActivateAbility()` 호출 전에 `CanActivateAbility()`가 `CheckCost()`와 `CheckCooldown()`을 실행한다. 활성화 이후 원하는 시점에 `CommitAbility()`를 호출하면 Cost와 Cooldown이 적용된다. `CommitAbility()`는 내부적으로 `CommitCost()`와 `CommitCooldown()`을 호출하며, 각각 따로 호출하는 것도 가능하다.

커밋 시점에 `CheckCost()`와 `CheckCooldown()`이 한 번 더 실행된다. GA가 활성화된 이후 Attribute가 변경되어 커밋 시점에 Cost를 충족하지 못할 수 있기 때문이다. 커밋 시점에 Prediction Key가 유효하다면 Cost와 Cooldown 커밋도 로컬 예측이 가능하다.

<a name="concepts-ga-leveling"></a>
#### GA를 레벨업하는 두 가지 방법(Ungrant 후 Regrant vs Spec 레벨 증가)의 차이는 무엇인가?

| 레벨업 방법 | 동작 | 활성 중인 GA 처리 |
|---|---|---|
| Ungrant 후 새 레벨로 Regrant | 서버에서 GA를 제거하고 다음 레벨로 다시 부여 | **종료됨** |
| `GameplayAbilitySpec`의 레벨 증가 | 서버에서 Spec을 찾아 레벨을 올리고 dirty 표시 → owning client로 복제 | **유지됨** |

`UGameplayAbility` 서브클래스에 어떤 방법을 사용할지 지정하는 `bool` 변수를 추가하는 것을 권장한다.

<a name="concepts-ga-sets"></a>
#### GameplayAbilitySet DataAsset은 어떤 역할을 하며 반드시 사용해야 하는가?

캐릭터의 초기 GA 목록과 입력 바인딩을 보관하고, GA를 부여하는 로직을 포함하는 편의용 `UDataAsset` 클래스다. Paragon에서는 각 영웅마다 자신의 모든 GA를 포함하는 `GameplayAbilitySet`이 존재했다.

GASDoc 저자 기준으로는 불필요하다고 판단하며, 샘플 프로젝트는 `GDCharacterBase`에서 이 기능을 직접 처리한다. 반드시 사용해야 하는 것은 아니다.

---
