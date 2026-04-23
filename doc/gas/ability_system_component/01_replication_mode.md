# Replication Mode

> **GASDoc**: 4.1.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-asc"></a>
### 4.1 Ability System Component

`AbilitySystemComponent`(`ASC`)는 GAS의 핵심이다. `UActorComponent`([`UAbilitySystemComponent`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UAbilitySystemComponent/index.html))로서 시스템과의 모든 상호작용을 처리한다. [`GameplayAbilities`](#concepts-ga)를 사용하거나, [`Attribute`](#concepts-a)를 보유하거나, [`GameplayEffect`](#concepts-ge)를 받으려는 `Actor`는 반드시 하나의 `ASC`를 부착해야 한다. 이러한 오브젝트들은 모두 `ASC` 내부에 존재하며 `ASC`에 의해 관리되고 복제된다(단, `Attribute`는 [`AttributeSet`](#concepts-as)이 복제를 담당한다). 개발자가 이 클래스를 서브클래싱하는 것이 권장되지만 필수는 아니다.

`ASC`가 부착된 `Actor`는 해당 `ASC`의 `OwnerActor`라고 부른다. `ASC`의 물리적 표현 `Actor`는 `AvatarActor`라고 한다. `OwnerActor`와 `AvatarActor`는 MOBA 게임의 단순한 AI 미니언처럼 동일한 `Actor`일 수 있다. 또는 MOBA 게임의 플레이어 제어 영웅처럼 `OwnerActor`가 `PlayerState`이고 `AvatarActor`가 영웅의 `Character` 클래스인 경우처럼 서로 다른 `Actor`일 수도 있다. 대부분의 `Actor`는 `ASC`를 자기 자신에 가지고 있다. 리스폰 후에도 `Attribute`나 `GameplayEffect`의 지속성이 필요한 `Actor`(MOBA의 영웅 등)라면 `ASC`를 `PlayerState`에 두는 것이 이상적이다.

**참고:** `ASC`가 `PlayerState`에 있다면 `PlayerState`의 `NetUpdateFrequency`를 높여야 한다. `PlayerState`의 기본값은 매우 낮아서 클라이언트에서 `Attribute`나 `GameplayTag` 같은 변경 사항이 지연되거나 랙으로 느껴질 수 있다. [`Adaptive Network Update Frequency`](https://docs.unrealengine.com/en-US/Gameplay/Networking/Actors/Properties/index.html#adaptivenetworkupdatefrequency)를 반드시 활성화할 것. Fortnite에서도 이를 사용한다.

`OwnerActor`와 `AvatarActor`가 서로 다른 `Actor`인 경우, 두 `Actor` 모두 `IAbilitySystemInterface`를 구현해야 한다. 이 인터페이스에는 반드시 오버라이드해야 하는 함수 `UAbilitySystemComponent* GetAbilitySystemComponent() const`가 있으며, 이 함수는 `ASC`에 대한 포인터를 반환한다. `ASC`들은 시스템 내부에서 이 인터페이스 함수를 찾아 서로 상호작용한다.

`ASC`는 현재 활성화된 `GameplayEffect`를 `FActiveGameplayEffectsContainer ActiveGameplayEffects`에 보관한다.

`ASC`는 부여된 `GameplayAbility`를 `FGameplayAbilitySpecContainer ActivatableAbilities`에 보관한다. `ActivatableAbilities.Items`를 순회할 때는 반드시 루프 위에 `ABILITYLIST_SCOPE_LOCK();`을 추가하여 목록이 변경되는 것(어빌리티 제거 등)을 막아야 한다. 스코프 내의 `ABILITYLIST_SCOPE_LOCK();`마다 `AbilityScopeLockCount`를 1 증가시키고, 스코프를 벗어나면 감소시킨다. `ABILITYLIST_SCOPE_LOCK();` 스코프 안에서는 어빌리티를 제거하려 하지 말 것(어빌리티 제거 함수들은 내부적으로 `AbilityScopeLockCount`를 확인하여 목록이 잠겨 있으면 제거를 방지한다).

<a name="concepts-asc-rm"></a>
### 4.1.1 Replication Mode

`ASC`는 `GameplayEffect`, `GameplayTag`, `GameplayCue`를 복제하는 세 가지 모드를 정의한다 — `Full`, `Mixed`, `Minimal`. `Attribute`의 복제는 `AttributeSet`이 담당한다.

| Replication Mode | 사용 상황 | 설명 |
| ---------------- | --------- | ---- |
| `Full` | 싱글플레이어 | 모든 `GameplayEffect`를 모든 클라이언트에 복제한다. |
| `Mixed` | 멀티플레이어, 플레이어 제어 `Actor` | `GameplayEffect`는 소유 클라이언트에만 복제된다. `GameplayTag`와 `GameplayCue`만 모두에게 복제된다. |
| `Minimal` | 멀티플레이어, AI 제어 `Actor` | `GameplayEffect`는 누구에게도 복제되지 않는다. `GameplayTag`와 `GameplayCue`만 모두에게 복제된다. |

**참고:** `Mixed` 복제 모드는 `OwnerActor`의 `Owner`가 `Controller`여야 한다. `PlayerState`의 `Owner`는 기본적으로 `Controller`이지만 `Character`의 경우는 그렇지 않다. `OwnerActor`가 `PlayerState`가 아닌 상태에서 `Mixed` 복제 모드를 사용할 경우, 유효한 `Controller`를 인자로 `SetOwner()`를 `OwnerActor`에 호출해야 한다.

4.24부터 `PossessedBy()`가 `Pawn`의 Owner를 새 `Controller`로 자동 설정한다.

---

## 내 분석
