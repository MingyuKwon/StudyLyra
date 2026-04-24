# Replication Mode

> **GASDoc**: 4.1.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-asc"></a>
### 4.1 Ability System Component

`AbilitySystemComponent`(`ASC`)는 GAS의 핵심이다.
`UActorComponent`([`UAbilitySystemComponent`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UAbilitySystemComponent/index.html))로서
시스템과의 모든 상호작용을 처리한다.

`GameplayAbilities`를 사용하거나, `Attribute`를 보유하거나, `GameplayEffect`를 받으려는 `Actor`는
반드시 하나의 `ASC`를 부착해야 한다.
이러한 오브젝트들은 모두 `ASC` 내부에 존재하며 `ASC`에 의해 관리되고 복제된다
(단, `Attribute`는 `AttributeSet`이 복제를 담당한다).
개발자가 이 클래스를 서브클래싱하는 것이 권장되지만 필수는 아니다.

`ASC`가 부착된 `Actor`는 해당 `ASC`의 `OwnerActor`라고 부른다.
`ASC`의 물리적 표현 `Actor`는 `AvatarActor`라고 한다.

`OwnerActor`와 `AvatarActor`는 AI 미니언처럼 동일한 `Actor`일 수 있다.
또는 플레이어 제어 영웅처럼 `OwnerActor`가 `PlayerState`이고 `AvatarActor`가 `Character`인 경우처럼
서로 다른 `Actor`일 수도 있다.

리스폰 후에도 `Attribute`나 `GameplayEffect`의 지속성이 필요한 `Actor`라면
`ASC`를 `PlayerState`에 두는 것이 이상적이다.

> **참고**  
> `ASC`가 `PlayerState`에 있다면 `PlayerState`의 `NetUpdateFrequency`를 높여야 한다.
> 기본값은 매우 낮아서 클라이언트에서 `Attribute`나 `GameplayTag` 변경 사항이 지연되거나 랙으로 느껴질 수 있다.
> [`Adaptive Network Update Frequency`](https://docs.unrealengine.com/en-US/Gameplay/Networking/Actors/Properties/index.html#adaptivenetworkupdatefrequency)를
> 반드시 활성화할 것. Fortnite에서도 이를 사용한다.

`OwnerActor`와 `AvatarActor`가 서로 다른 `Actor`인 경우,
두 `Actor` 모두 `IAbilitySystemInterface`를 구현해야 한다.
이 인터페이스에는 `UAbilitySystemComponent* GetAbilitySystemComponent() const` 함수가 있으며,
`ASC`들은 시스템 내부에서 이 인터페이스를 통해 서로 상호작용한다.

`ASC`는 현재 활성화된 `GameplayEffect`를 `FActiveGameplayEffectsContainer ActiveGameplayEffects`에 보관한다.

`ASC`는 부여된 `GameplayAbility`를 `FGameplayAbilitySpecContainer ActivatableAbilities`에 보관한다.
`ActivatableAbilities.Items`를 순회할 때는 반드시 루프 위에 `ABILITYLIST_SCOPE_LOCK();`을 추가해야 한다.
이 매크로는 `AbilityScopeLockCount`를 1 증가시켜 순회 중 목록 변경을 막는다.
스코프를 벗어나면 카운트가 감소하고, 잠긴 상태에서 제거를 시도하면 내부적으로 방지된다.

---

<a name="concepts-asc-rm"></a>
### 4.1.1 Replication Mode

`ASC`는 `GameplayEffect`, `GameplayTag`, `GameplayCue`를 복제하는 세 가지 모드를 정의한다.
`Attribute`의 복제는 `AttributeSet`이 담당한다.

| Replication Mode | 사용 상황 | 설명 |
| ---------------- | --------- | ---- |
| `Full` | 싱글플레이어 | 모든 `GameplayEffect`를 모든 클라이언트에 복제한다. |
| `Mixed` | 멀티플레이어, 플레이어 제어 `Actor` | `GameplayEffect`는 소유 클라이언트에만 복제된다. `GameplayTag`와 `GameplayCue`만 모두에게 복제된다. |
| `Minimal` | 멀티플레이어, AI 제어 `Actor` | `GameplayEffect`는 누구에게도 복제되지 않는다. `GameplayTag`와 `GameplayCue`만 모두에게 복제된다. |

> **참고**  
> `Mixed` 복제 모드는 `OwnerActor`의 `Owner`가 `Controller`여야 한다.
> `PlayerState`의 `Owner`는 기본적으로 `Controller`이지만 `Character`의 경우는 그렇지 않다.
> `OwnerActor`가 `PlayerState`가 아닌 상태에서 `Mixed` 모드를 사용할 경우,
> `SetOwner(Controller)`를 `OwnerActor`에 수동으로 호출해야 한다.
>
> 4.24부터 `PossessedBy()`가 `Pawn`의 Owner를 새 `Controller`로 자동 설정한다.

---

## 내 분석

### OwnerActor vs SetOwner의 Owner — 완전히 다른 개념

문서 하단 주석("Mixed 모드는 OwnerActor의 Owner가 Controller여야 한다")을 보고 헷갈릴 수 있는 부분.

| | 개념 | 설정 방법 | 용도 |
|---|---|---|---|
| `OwnerActor` | GAS 용어 | `InitAbilityActorInfo()` | ASC가 누구 소속인지 |
| `Owner` | UE Actor 용어 | `SetOwner()` | 네트워크 복제 대상 클라이언트 결정 |

**ASC의 `OwnerActor`**: GAS가 "이 ASC가 어느 Actor에 붙어있냐"를 기록하는 용도.

```cpp
// Lyra에서
ASC->InitAbilityActorInfo(PlayerState, Character);
//                         ^^^^^^^^^^^  ← GAS의 OwnerActor
//                                       ^^^^^^^^^ ← GAS의 AvatarActor
```

**`SetOwner()`의 Owner**: 언리얼 네트워킹 개념.
`GetNetOwner()`로 Owner 체인을 타고 올라가 PlayerController를 찾아
"이 Actor를 어느 클라이언트에게 복제할지" 결정한다.

**Mixed 모드에서 두 개념이 교차하는 지점**:

```
GE를 "소유 클라이언트에만" 복제하려면
→ GAS가 OwnerActor->GetNetOwner() 호출
→ Owner 체인을 타고 올라가 PlayerController 탐색
→ 그 Controller의 커넥션으로 GE 전송
```

`PlayerState`는 기본적으로 Controller가 `SetOwner()`로 등록되어 있어서 자동 동작.
Character에 직접 ASC를 붙이면 `PossessedBy()` 전에는 Owner가 없어 커넥션을 못 찾음
→ `SetOwner(Controller)` 수동 호출 필요.
