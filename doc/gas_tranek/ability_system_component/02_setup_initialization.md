# Setup & Initialization

> **GASDoc**: 4.1.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-asc-setup"></a>
### ASC는 어디서, 어떻게 초기화해야 하는가?

ASC는 OwnerActor의 생성자에서 생성하고 `SetIsReplicated(true)`로 명시 복제 설정한다. **반드시 C++에서 해야 한다.**

```cpp
AGDPlayerState::AGDPlayerState()
{
    AbilitySystemComponent = CreateDefaultSubobject<UGDAbilitySystemComponent>(TEXT("AbilitySystemComponent"));
    AbilitySystemComponent->SetIsReplicated(true);
}
```

이후 서버·클라이언트 양쪽에서 `InitAbilityActorInfo(OwnerActor, AvatarActor)`를 호출해야 한다. 이 호출은 반드시 Controller 설정(빙의) 이후에 해야 한다.

**ASC 위치별 초기화 시점:**

| ASC 위치 | 서버 | 클라이언트 |
|---|---|---|
| Pawn | `PossessedBy()` | `AcknowledgePossession()` |
| PlayerState | `PossessedBy()` | `OnRep_PlayerState()` |

**ASC가 Pawn에 있는 경우:**

```cpp
// 서버
void APACharacterBase::PossessedBy(AController* NewController)
{
    Super::PossessedBy(NewController);
    AbilitySystemComponent->InitAbilityActorInfo(this, this);
    SetOwner(NewController);  // Mixed 모드 필수
}

// 클라이언트
void APAPlayerControllerBase::AcknowledgePossession(APawn* P)
{
    Super::AcknowledgePossession(P);
    Cast<APACharacterBase>(P)->GetAbilitySystemComponent()->InitAbilityActorInfo(P, P);
}
```

**ASC가 PlayerState에 있는 경우:**

```cpp
// 서버
void AGDHeroCharacter::PossessedBy(AController* NewController)
{
    Super::PossessedBy(NewController);
    AGDPlayerState* PS = GetPlayerState<AGDPlayerState>();
    AbilitySystemComponent = Cast<UGDAbilitySystemComponent>(PS->GetAbilitySystemComponent());
    PS->GetAbilitySystemComponent()->InitAbilityActorInfo(PS, this);
}

// 클라이언트
void AGDHeroCharacter::OnRep_PlayerState()
{
    Super::OnRep_PlayerState();
    AGDPlayerState* PS = GetPlayerState<AGDPlayerState>();
    AbilitySystemComponent = Cast<UGDAbilitySystemComponent>(PS->GetAbilitySystemComponent());
    AbilitySystemComponent->InitAbilityActorInfo(PS, this);
}
```

> `LogAbilitySystem: Warning: Can't activate LocalOnly or LocalPredicted ability %s when not local!` 에러가 나면 클라이언트에서 `InitAbilityActorInfo()`를 호출하지 않은 것이다.

---

## InitAbilityActorInfo()를 서버와 클라이언트 양쪽에서 각각 호출해야 하는 이유는?

`InitAbilityActorInfo()`는 복제 함수가 아니다. 서버에서 호출해도 클라이언트에 전파되지 않고, 로컬 메모리에 OwnerActor·AvatarActor 포인터를 세팅할 뿐이다. 따라서 서버와 클라이언트가 각자 독립적으로 호출해야 한다.

---

## InitAbilityActorInfo()를 반드시 Controller 설정(빙의) 이후에 호출해야 하는 이유는?

내부적으로 `InitFromActor()`를 호출해 **PlayerController 포인터를 `AbilityActorInfo`에 캐싱**하기 때문이다.

```cpp
// GameplayAbilityTypes.cpp — InitFromActor 내부
if (APawn* Pawn = Cast<APawn>(TestActor))
{
    PlayerController = Cast<APlayerController>(Pawn->GetController());  // ← 여기서 캐싱
}
```

`PossessedBy()` 이전에 호출하면 `GetController()`가 `nullptr`를 반환하므로 `AbilityActorInfo.PlayerController`가 `nullptr`로 캐시된다. 이 캐시는 GAS 전반에서 사용된다.

```cpp
bool FGameplayAbilityActorInfo::IsLocallyControlled() const
{
    if (const APlayerController* PC = PlayerController.Get())  // ← 캐시를 봄
        return PC->IsLocalController();
}
```

`IsLocallyControlled()`가 틀리면 클라이언트 예측 여부, GA 실행 주체 결정 등 GAS 전체 흐름이 잘못된다. 또한 `InitAbilityActorInfo()` 직후 `TryActivateAbilitiesOnSpawn()`이 실행되므로, OnSpawn GA 발동 시점에도 PlayerController 캐시가 정확해야 한다.

---

## ASC 초기화에 PossessedBy, AcknowledgePossession, OnRep_PlayerState를 각각 사용하는 이유는?

**서버 — `PossessedBy()`**
Controller가 Pawn을 소유하는 순간 호출되며, 이때 `GetController()`가 새 Controller를 반환한다. 서버 측에서 Controller가 유효함을 보장할 수 있는 가장 이른 시점이다.

**클라이언트 (ASC가 Pawn에 있는 경우) — `AcknowledgePossession()`**
클라이언트 PlayerController가 빙의를 확인한 시점에 호출된다. 이때 클라이언트의 `GetController()`가 PlayerController를 반환하므로, 서버의 `PossessedBy()`와 대칭되는 클라이언트 측 초기화 지점이다.

**클라이언트 (ASC가 PlayerState에 있는 경우) — `OnRep_PlayerState()`**
`AcknowledgePossession()` 시점에는 PlayerState가 아직 클라이언트에 복제되지 않았을 수 있다. `OnRep_PlayerState()`는 PlayerState 복제 완료 시점에 호출되므로, PlayerState 포인터가 반드시 존재함을 보장할 수 있다.

클라이언트 접속 시 생성 순서상 PlayerController는 PlayerState보다 훨씬 먼저 생성된다.

```
1. 서버: GameMode::Login() → 서버 측 PlayerController 생성
2. 클라이언트: 로컬 PlayerController 생성
3. (한참 뒤) 서버: PlayerState 생성 → 전체 클라이언트에 복제
4. 서버: Pawn 생성 → 복제
```

`OnRep_PlayerState()`가 발동하는 시점에 PlayerController는 이미 존재하므로, 이 시점에 초기화하면 PlayerController·PlayerState 두 조건이 자동으로 모두 충족된다.
