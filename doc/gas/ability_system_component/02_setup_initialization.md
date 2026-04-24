# Setup & Initialization

> **GASDoc**: 4.1.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-asc-setup"></a>
### 4.1.2 Setup and Initialization

`ASC`는 일반적으로 `OwnerActor`의 생성자에서 생성하고 명시적으로 복제 대상으로 표시한다. **이 작업은 반드시 C++에서 해야 한다.**

```c++
AGDPlayerState::AGDPlayerState()
{
	// Create ability system component, and set it to be explicitly replicated
	AbilitySystemComponent = CreateDefaultSubobject<UGDAbilitySystemComponent>(TEXT("AbilitySystemComponent"));
	AbilitySystemComponent->SetIsReplicated(true);
	//...
}
```

`ASC`는 서버와 클라이언트 양쪽에서 `OwnerActor`와 `AvatarActor`로 초기화해야 한다. `Pawn`의 `Controller`가 설정된 이후(빙의 이후)에 초기화해야 한다. 싱글플레이어 게임은 서버 경로만 신경 쓰면 된다.

`ASC`가 `Pawn`에 있는 플레이어 제어 캐릭터의 경우, 일반적으로 서버에서는 `Pawn`의 `PossessedBy()` 함수에서, 클라이언트에서는 `PlayerController`의 `AcknowledgePossession()` 함수에서 초기화한다.

```c++
void APACharacterBase::PossessedBy(AController * NewController)
{
	Super::PossessedBy(NewController);

	if (AbilitySystemComponent)
	{
		AbilitySystemComponent->InitAbilityActorInfo(this, this);
	}

	// ASC MixedMode replication requires that the ASC Owner's Owner be the Controller.
	SetOwner(NewController);
}
```

```c++
void APAPlayerControllerBase::AcknowledgePossession(APawn* P)
{
	Super::AcknowledgePossession(P);

	APACharacterBase* CharacterBase = Cast<APACharacterBase>(P);
	if (CharacterBase)
	{
		CharacterBase->GetAbilitySystemComponent()->InitAbilityActorInfo(CharacterBase, CharacterBase);
	}

	//...
}
```

`ASC`가 `PlayerState`에 있는 플레이어 제어 캐릭터의 경우, 일반적으로 서버에서는 `Pawn`의 `PossessedBy()` 함수에서, 클라이언트에서는 `Pawn`의 `OnRep_PlayerState()` 함수에서 초기화한다. `OnRep_PlayerState()`를 사용하면 클라이언트에 `PlayerState`가 존재함을 보장할 수 있다.

```c++
// Server only
void AGDHeroCharacter::PossessedBy(AController * NewController)
{
	Super::PossessedBy(NewController);

	AGDPlayerState* PS = GetPlayerState<AGDPlayerState>();
	if (PS)
	{
		// Set the ASC on the Server. Clients do this in OnRep_PlayerState()
		AbilitySystemComponent = Cast<UGDAbilitySystemComponent>(PS->GetAbilitySystemComponent());

		// AI won't have PlayerControllers so we can init again here just to be sure. No harm in initing twice for heroes that have PlayerControllers.
		PS->GetAbilitySystemComponent()->InitAbilityActorInfo(PS, this);
	}
	
	//...
}
```

```c++
// Client only
void AGDHeroCharacter::OnRep_PlayerState()
{
	Super::OnRep_PlayerState();

	AGDPlayerState* PS = GetPlayerState<AGDPlayerState>();
	if (PS)
	{
		// Set the ASC for clients. Server does this in PossessedBy.
		AbilitySystemComponent = Cast<UGDAbilitySystemComponent>(PS->GetAbilitySystemComponent());

		// Init ASC Actor Info for clients. Server will init its ASC when it possesses a new Actor.
		AbilitySystemComponent->InitAbilityActorInfo(PS, this);
	}

	// ...
}
```

`LogAbilitySystem: Warning: Can't activate LocalOnly or LocalPredicted ability %s when not local!` 에러 메시지가 발생하면 클라이언트에서 `ASC`를 초기화하지 않은 것이다.

---

## 내 분석

### 왜 서버와 클라이언트 양쪽에서 초기화해야 하는가

`InitAbilityActorInfo()`는 복제 함수가 아니다.
서버가 호출해도 클라이언트에 전파되지 않고, 그냥 로컬 메모리에 `OwnerActor`·`AvatarActor` 포인터를 세팅할 뿐이다.
그래서 서버와 클라이언트가 각자 독립적으로 호출해야 한다.

### 왜 Controller 설정 이후에 초기화해야 하는가

두 가지 이유가 있다.

**첫째, Mixed 복제 모드 문제.**
GAS는 GE를 "소유 클라이언트"에게만 보낼 때 `OwnerActor->GetNetOwner()`로 PlayerController를 탐색한다.
`PossessedBy()` 이전에 초기화하면 `SetOwner(Controller)`가 아직 안 된 상태라 GAS가 커넥션을 못 찾는다.

**둘째, OnSpawn GA 발동 타이밍.**
`InitAbilityActorInfo()` 직후 `TryActivateAbilitiesOnSpawn()`이 실행되어 `OnSpawn` 정책 GA들이 즉시 발동된다.
이 시점에 Controller가 없으면 `IsLocallyControlled()`, `IsNetAuthority()` 판단이 틀려서
어느 쪽에서 GA를 실행할지 잘못 결정된다.

### 권장 초기화 시점들이 선택된 이유

**서버 — `PossessedBy()`**
`PossessedBy()`는 서버에서 Controller가 Pawn을 소유하는 바로 그 순간 호출된다.
이 함수 안에서 `GetController()`가 새 Controller를 반환하고, `SetOwner(NewController)`도 여기서 한다.
Controller가 유효함을 보장할 수 있는 서버 측 가장 이른 시점이다.

**클라이언트 (ASC가 Pawn에 있는 경우) — `AcknowledgePossession()`**
`AcknowledgePossession()`은 클라이언트의 PlayerController가 Pawn 빙의를 확인했을 때 호출된다.
이 시점에 클라이언트의 `GetController()`가 PlayerController를 반환하므로,
서버의 `PossessedBy`와 대칭되는 클라이언트 측 초기화 지점이 된다.

**클라이언트 (ASC가 PlayerState에 있는 경우) — `OnRep_PlayerState()`**
ASC가 PlayerState에 있으면 초기화에 PlayerState 포인터가 필요하다.
`AcknowledgePossession()` 시점에는 클라이언트에 PlayerState가 아직 복제되지 않았을 수 있다.
`OnRep_PlayerState()`는 PlayerState가 클라이언트에 복제 완료된 시점에 호출되므로,
이때 초기화하면 PlayerState가 반드시 존재함을 보장할 수 있다.
