# Replication Mode

> **GASDoc**: 4.1.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-asc"></a>
### ASC란 무엇이며, 어떤 역할을 하는가?

`UAbilitySystemComponent`(`ASC`)는 GAS의 중심 컴포넌트로, `UActorComponent`를 상속한다. GA 사용, Attribute 보유, GE 수신이 필요한 Actor는 반드시 ASC를 하나 부착해야 한다. GA, GE, Attribute는 모두 ASC 안에서 관리되고 복제된다(Attribute 복제는 AttributeSet이 담당).

| 용어 | 의미 |
|---|---|
| `OwnerActor` | ASC가 부착된 Actor (GAS의 소유자 개념) |
| `AvatarActor` | ASC의 물리적 표현 Actor (보통 캐릭터) |

둘이 같을 수도 있고(AI 미니언), 다를 수도 있다(OwnerActor = PlayerState, AvatarActor = Character). 리스폰 후 Attribute·GE를 유지해야 한다면 ASC를 PlayerState에 두는 것이 적합하다.

> **참고** — ASC가 PlayerState에 있으면 PlayerState의 `NetUpdateFrequency`를 높여야 한다. 기본값이 낮아 Attribute·Tag 변경이 클라이언트에서 지연될 수 있다. Adaptive Network Update Frequency를 활성화할 것 (Fortnite도 사용).

OwnerActor와 AvatarActor가 서로 다른 Actor면 둘 다 `IAbilitySystemInterface`를 구현해야 한다. ASC 내부에서 이 인터페이스를 통해 서로 참조하기 때문이다.

ASC는 현재 활성 GE를 `FActiveGameplayEffectsContainer ActiveGameplayEffects`에, 부여된 GA를 `FGameplayAbilitySpecContainer ActivatableAbilities`에 보관한다. `ActivatableAbilities.Items`를 순회할 때는 반드시 `ABILITYLIST_SCOPE_LOCK();`을 사용해야 순회 중 목록 변경을 막을 수 있다.

> ASC가 보관하는 전체 복제 컨테이너 목록: [`reference/asc_replicated_containers.md`](../reference/asc_replicated_containers.md)

---

<a name="concepts-asc-rm"></a>
### ASC의 세 가지 Replication Mode는 각각 언제 사용해야 하는가?

GE·GameplayTag·GameplayCue의 복제 범위를 결정한다. Attribute 복제는 AttributeSet이 별도로 담당한다.

| Replication Mode | 사용 상황 | GE 복제 대상 | Tag·Cue 복제 대상 |
|---|---|---|---|
| `Full` | 싱글플레이어 | 모든 클라이언트 | 모든 클라이언트 |
| `Mixed` | 멀티플레이어, 플레이어 제어 Actor | 소유 클라이언트만 | 모든 클라이언트 |
| `Minimal` | 멀티플레이어, AI 제어 Actor | 없음 | 모든 클라이언트 |

> **참고** — `Mixed` 모드는 OwnerActor의 `Owner`(UE Actor 용어)가 Controller여야 한다. PlayerState는 기본적으로 Controller가 Owner로 설정되어 있어 자동 동작한다. Character에 직접 ASC를 붙이는 경우 `PossessedBy()` 안에서 `SetOwner(NewController)`를 수동 호출해야 한다. 4.24부터는 `PossessedBy()`가 Pawn의 Owner를 자동 설정한다.

---

### GAS의 OwnerActor와 언리얼의 SetOwner() Owner는 어떻게 다른가?

두 "Owner" 개념은 서로 독립적이다.

| | 개념 | 설정 방법 | 용도 |
|---|---|---|---|
| `OwnerActor` | GAS 용어 | `InitAbilityActorInfo()` | ASC가 어느 Actor 소속인지 기록 |
| `Owner` | UE Actor 용어 | `SetOwner()` | 네트워크 복제 대상 클라이언트 결정 |

Mixed 모드에서 GE를 "소유 클라이언트에만" 복제하려면 GAS가 `OwnerActor->GetNetOwner()`로 Owner 체인을 타고 올라가 PlayerController를 찾아야 한다. PlayerState는 Controller가 이미 `SetOwner()`로 등록되어 있어 자동 동작하지만, Character에 ASC를 붙이면 `PossessedBy()` 전까지 Owner가 없으므로 커넥션을 찾지 못한다.

```cpp
// Lyra에서
ASC->InitAbilityActorInfo(PlayerState, Character);
//                         ^^^^^^^^^^^  ← GAS의 OwnerActor
//                                       ^^^^^^^^^ ← GAS의 AvatarActor
```
