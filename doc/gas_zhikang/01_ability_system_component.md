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

---

## IAbilitySystemInterface는 무엇이며, 반드시 구현해야 하나?

필수는 아니지만 **구현을 권장**한다.

GAS가 제공하는 블루프린트 호출 가능 정적 함수들은 Actor 레퍼런스만 받아서 내부적으로 ASC를 찾는다. 이 탐색은 `UAbilitySystemGlobals::GetAbilitySystemComponentFromActor()`를 통해 이루어지며, 엔진 코드 여러 곳에서 호출된다. 예시: `ExecuteGameplayCueOnActor`(GameplayCueFunctionLibrary), `GetFloatAttribute`(AbilitySystemBlueprintLibrary).

`GetAbilitySystemComponentFromActor()` 내부 동작:
- Actor 클래스가 `IAbilitySystemInterface`를 구현한 경우 → 해당 함수를 직접 호출해 ASC를 반환 (**O(1)**)
- 구현하지 않은 경우 → `FindComponentByClass`로 모든 컴포넌트를 순회해 탐색 (**O(n)**)

성능상 ASC를 직접 반환하는 인터페이스 구현이 훨씬 유리하다.

`IAbilitySystemInterface`는 블루프린트에서 구현할 수 없다. BlueprintNativeEvent는 C++ 가상 함수보다 호출 비용이 높기 때문에 성능을 최대화하려면 **C++ 클래스에서 ASC를 추가하고 인터페이스도 C++로 구현**하는 것을 권장한다.

---

## 플레이어 관련 Actor 중 어디에 ASC를 붙여야 하나?

대부분의 경우 **PlayerState**가 최선이다. PlayerController와 Pawn도 게임 설계에 따라 유효한 선택지다.

### 리스폰 시 유지 여부

ASC를 어느 Actor에 붙일지는 원하는 지속성(persistence)에 따라 결정한다.

- Attribute, 버프/디버프, 쿨다운을 **리스폰 후에도 유지**하고 싶다면 → 리스폰 시 교체되지 않는 Actor(PlayerState)에 붙인다.
- 리스폰 시 **초기화**해야 한다면 → Pawn에 붙는다.
- 일부는 유지, 일부는 초기화가 섞여 있다면 → PlayerState(지속 옵션)를 선택하고, 리스폰 시 일부 Effect만 제거하는 편이 ASC 간 마이그레이션보다 훨씬 간단하다.

### PlayerState가 없는 경우

싱글플레이어 게임에서 커스텀 PlayerState가 없다면:
- 리스폰 시 유지 원함 → **PlayerController**에 붙인다.
- 리스폰 시 초기화 원함 → **Pawn**에 붙인다.

PlayerController는 멀티플레이어에서 모든 클라이언트에 존재하지 않으므로 멀티플레이어 게임에선 ASC OwnerActor로 적합하지 않다.

### AI 제어 Pawn

AI Pawn에 ASC를 붙이는 방법은 두 가지다.

**방법 1 — Pawn에 직접 붙이기**

```cpp
// Pawn 생성자
AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("ASC"));
AbilitySystemComponent->SetIsReplicated(true);
AbilitySystemComponent->SetReplicationMode(EGameplayEffectReplicationMode::Minimal);
```

- Pawn은 서버/클라 모두 존재하므로 ASC가 정상 복제된다.
- Pawn이 죽고 삭제되면 ASC도 함께 사라진다 → 상태 유지 불필요한 AI에 적합.
- AI가 많은 경우(RTS 유닛, 몹 대규모 스폰)에 적합. PlayerState 복제 오버헤드 없음.

**방법 2 — PlayerState에 붙이기 (`bWantsPlayerState = true`)**

```cpp
// AIController 생성자
bWantsPlayerState = true;
// PlayerState 클래스에서 ASC를 플레이어와 동일하게 생성
```

- `GameMode`가 AIController에도 PlayerState를 자동 생성해 붙여준다.
- PlayerState는 모든 클라이언트에 복제되며 `GameState::PlayerArray`에 포함된다.
- Pawn이 죽어도 PlayerState는 유지되므로 버프/쿨다운 지속이 필요한 AI에 적합.
- 플레이어와 봇이 동일한 ASC 구조를 가지므로 코드 일관성이 높다.
- AI 수가 많으면 PlayerState 복제 비용이 증가하므로 소수의 봇(팀 기반 슈터 등)에 적합.

| | Pawn에 직접 | PlayerState 경유 |
|---|---|---|
| AI 수 | 많아도 OK | 소수 권장 |
| 상태 유지 | Pawn 삭제 시 소멸 | Pawn 교체 후에도 유지 |
| 코드 일관성 | 플레이어와 구조 다름 | 플레이어와 동일 구조 |
| 복제 오버헤드 | 낮음 | 높음 |

---

## OwnerActor와 AvatarActor란?

- **OwnerActor**: 플레이어, 봇, 엔티티를 지속적으로 대표하는 Actor.
- **AvatarActor**: 월드에서 물리적으로 표현하는 Actor.

`InitAbilityActorInfo(OwnerActor, AvatarActor)`를 호출해 ASC에 두 Actor를 설정한다. ASC 수명 중 여러 번 호출 가능하다(예: 다른 Pawn 빙의 시 AvatarActor 교체).

어빌리티 블루프린트 작업 중 Owner와 Avatar에 접근할 수 있다. 일부 어빌리티(회피 이동 등)는 Avatar가 필요하고, 일부(RTS 유닛 배치 등)는 필요하지 않다.

**OwnerActor 선택 기준:**
- 플레이어 → Pawn, PlayerController, PlayerState 중 하나. 단, `GetOwner()`를 재귀 호출했을 때 플레이어의 PC/PS/Pawn으로 이어질 수 있어야 한다. `FGameplayAbilityActorInfo::InitFromActor`가 PlayerController를 캐싱해야 로컬 예측 어빌리티를 활성화할 수 있다.
- 비플레이어(예: 루팅 상자) → 자기 자신을 OwnerActor와 AvatarActor 모두로 사용 가능.

**AvatarActor:** 월드에 물리적 위치가 있는 Character/Pawn 또는 다른 Actor. Pawn이 없는 경우 null일 수 있으며, 이 경우 GameplayAbility 블루프린트에서 null 처리를 해야 한다.

---

## InitAbilityActorInfo / RefreshAbilityActorInfo는 언제 호출해야 하나?

`InitAbilityActorInfo`는 **서버와 클라이언트 각자 독립적으로** 호출해야 한다. Owner 또는 Avatar가 클라이언트 측에서 생성되거나 변경될 때마다 호출한다. OnRep 함수나 BeginPlay/PostInitializeComponents를 활용하면 편리하다.

**멀티플레이어에서 PlayerController 의존성 주의:**

`InitAbilityActorInfo` → `FGameplayAbilityActorInfo::InitFromActor()` → PlayerController를 캐싱한다. 클라이언트 측에서 Actor 스폰 순서가 보장되지 않으므로, ASC가 BeginPlay를 시작할 때 아직 PlayerController가 복제되지 않았을 수 있다.

따라서 PlayerController가 나중에 사용 가능해지면 `InitAbilityActorInfo`를 재호출하거나 `RefreshAbilityActorInfo`를 호출해야 한다. `RefreshAbilityActorInfo`는 현재 Owner/Avatar를 유지하면서 PlayerController만 재탐색한다.

PC 존재를 보장하는 가장 확실한 방법은 **PC의 OnRep 함수에서 호출**하는 것이다. 예: PlayerState가 ASC를 소유한 경우, `PlayerController::OnRep_PlayerState()`에서 호출하면 PC 존재가 보장된다. Lyra UE 5.6 수정 사항에서 이 패턴이 적용되었다:

```cpp
void ALyraPlayerController::OnRep_PlayerState()
{
    Super::OnRep_PlayerState();
    BroadcastOnPlayerStateChanged();

    // 클라이언트에서 PC가 PlayerState/ASC보다 늦게 복제될 수 있으므로
    if (GetWorld()->IsNetMode(NM_Client))
    {
        if (ALyraPlayerState* LyraPS = GetPlayerState<ALyraPlayerState>())
        {
            // RefreshAbilityActorInfo 또는 InitAbilityActorInfo 재호출
        }
    }
}
```

---

## 어떤 Replication Mode를 사용해야 하나?

세 가지 모드가 있다: `Full`, `Mixed`, `Minimal`. 활성 GameplayEffect의 복제 상세 수준을 결정한다.

| 복제 상세 | 내용 |
|---|---|
| 전체(Full detail) | 활성 GE의 지속 시간, GameplayTag 카운트 등 모든 정보 |
| 최소(Minimal) | GameplayTag 집합만 (카운트 없음) |

| 모드 | 소유 클라이언트 | 다른 클라이언트 |
|---|---|---|
| `Full` | 전체 | 전체 |
| `Mixed` | 전체 | 최소 |
| `Minimal` | 최소 | 최소 |

**권장:** `Minimal`은 소유 클라이언트도 최소 정보만 받아 대부분 프로젝트에서 부적합하다. **`Full` 또는 `Mixed`를 사용**하라.

- **Mixed**: 기본 권장. 다른 플레이어/봇의 GE 상세 정보가 필요 없는 경우.
- **Full**: 다른 플레이어/봇의 GE 지속 시간 등을 UI에 표시해야 하는 경우. 단, 추가 네트워크 비용을 프로파일링해야 한다.

Replication Mode에 관계없이 **AttributeSet에서 replicated로 표시된 Attribute 값은 항상 복제**된다.

---

## GameplayTag 카운트를 게임 코드의 카운터로 사용해도 되나?

**사용하지 말 것.** GameplayTag 카운트는 GA/GE 등 여러 소스가 동일 태그를 기여할 때 내부 추적용으로만 설계됐다. 게임 코드에서는 카운트 값이 아닌 **태그의 존재 여부(있음/없음)**만 사용해야 한다.

또한 ASC의 Replication Mode가 `Full`이 아닌 경우, simulated proxy Actor의 ASC에서는 태그 카운트를 사용할 수 없다.
