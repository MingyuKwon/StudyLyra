# 복제 훅

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/Actor.h`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Classes/Components/ActorComponent.h`

---

## GetLifetimeReplicatedProps

```cpp
void AActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
```

**역할**: 이 클래스에서 복제할 프로퍼티 목록을 선언하는 함수.  
**호출 시점**: 복제 시스템이 초기화될 때 한 번 — 매 틱 호출이 아니다.

```cpp
void AMyActor::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);

    DOREPLIFETIME(AMyActor, Health);                         // 항상 복제
    DOREPLIFETIME_CONDITION(AMyActor, Speed, COND_OwnerOnly); // Owner에게만
}
```

**`COND_` 조건 종류**:
| 조건 | 복제 대상 |
|------|----------|
| `COND_None` | 모든 클라이언트 |
| `COND_OwnerOnly` | Owner 클라이언트만 |
| `COND_SkipOwner` | Owner 제외 |
| `COND_SimulatedOnly` | SimulatedProxy만 |
| `COND_AutonomousOnly` | AutonomousProxy만 |
| `COND_InitialOnly` | 최초 1회만 |
| `COND_Custom` | PreReplication에서 수동 제어 |

---

## PreReplication

```cpp
void AActor::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker);  // Actor.h:961
void UActorComponent::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker) {}  // ActorComponent.h:643
```

**역할**: 복제 패킷을 구성하기 직전, 매 복제 주기마다 호출되는 훅.  
`COND_Custom` 프로퍼티의 복제 여부를 동적으로 결정하는 데 사용한다.

```cpp
void AMyActor::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
{
    Super::PreReplication(ChangedPropertyTracker);

    // 조건부 복제 — 게임 중에만 Speed를 복제
    DOREPLIFETIME_ACTIVE_OVERRIDE(AMyActor, Speed, bIsInGame);
}
```

**호출 조건**: `ShouldCallPreReplication()` 반환값이 true일 때.

```cpp
// Actor.cpp:3297
bool AActor::ShouldCallPreReplication() const
{
    return bCallPreReplication
        || bReplicateMovement
        || (RootComponent && !RootComponent->GetIsReplicated());
}
```

기본적으로 이동 복제(`bReplicateMovement`)가 있으면 항상 호출된다.  
`SetCallPreReplication(true)`로 강제 활성화도 가능.

---

## OnRep_XXX

```cpp
UPROPERTY(ReplicatedUsing = OnRep_Health)
float Health;

UFUNCTION()
void OnRep_Health();  // 함수 시그니처는 void() 또는 void(OldValue) 형태
```

**역할**: 복제된 프로퍼티 값이 클라이언트에서 변경됐을 때 호출되는 콜백.  
**서버에서는 호출되지 않는다** — 클라이언트 전용.

```cpp
void AMyActor::OnRep_Health()
{
    // 클라이언트에서 Health 값이 복제됐을 때
    // 예: HUD 업데이트, 파티클 재생
    UpdateHealthUI();
}

// 이전 값이 필요하면 파라미터 추가
void AMyActor::OnRep_Health(float OldHealth)
{
    if (Health < OldHealth)
        PlayDamageEffect();
}
```

**호출 시점 주의**: 초기 복제(스폰 직후 최초 동기화)에서도 호출된다.  
레벨에 배치된 Actor가 처음 클라이언트에 복제될 때 기본값에서 실제값으로 변경되는 것도 OnRep가 감지한다.

---

## 네트워크 Role과 생명주기 교차점

Actor 스폰 시 네트워크 Role이 결정된다.

```cpp
// PostSpawnInitialize 내부
ExchangeNetRoles(bRemoteOwned);
```

| 상황 | LocalRole | RemoteRole |
|------|----------|-----------|
| 서버에서 스폰 | Authority | SimulatedProxy |
| 클라이언트에서 복제 수신 | SimulatedProxy | Authority |
| 로컬 플레이어 Pawn | AutonomousProxy | Authority |

**복제된 Actor의 BeginPlay 지연**:

```cpp
// PostActorConstruction 내부 (Actor.cpp:4417)
// 클라이언트에서 Role이 바뀐 복제 Actor는 초기 상태 수신 전까지 BeginPlay를 미룸
const bool bDeferBeginPlayAndUpdateOverlaps = 
    (bExchangedRoles && RemoteRole == ROLE_Authority) && !GIsReinstancing;
```

즉, 클라이언트에서 복제로 받은 Actor는 **초기 복제 프로퍼티(OnRep_ 포함)가 모두 적용된 후** `BeginPlay`가 호출된다.  
이 덕분에 `BeginPlay`에서 복제된 값을 안전하게 읽을 수 있다.

---

## 복제 관련 훅 호출 순서 (클라이언트 기준)

```
서버에서 Actor 스폰
  → 클라이언트로 복제 패킷 전송
      (각 UPROPERTY 값 포함)

클라이언트 수신
  PostInitProperties()           ← 기본값으로 오브젝트 생성
  [각 OnRep_ 호출]               ← 복제된 초기값 적용
  PostNetInit() / DispatchBeginPlay()  ← 초기값 적용 완료 후 BeginPlay

게임플레이 중 서버가 값 변경
  PreReplication() 호출          ← 서버 측, 복제 패킷 구성 전
  패킷 전송
  클라이언트: OnRep_XXX() 호출   ← 변경된 값으로 업데이트
```

---

## 자주 하는 실수

**1. OnRep를 서버에서 직접 호출하면 안 된다**  
서버는 값을 바꾸면 자동으로 복제가 일어난다. `OnRep_XXX()`를 직접 호출하면 클라이언트와 로직이 이중 실행되거나 서버-클라이언트 상태 불일치가 생긴다.

**2. GetLifetimeReplicatedProps에서 Super 누락**  
엔진과 부모 클래스가 등록하는 프로퍼티가 빠진다.

**3. OnRep에서 다른 복제 프로퍼티를 읽을 때 순서 미보장**  
같은 패킷으로 복제된 여러 프로퍼티의 OnRep 호출 순서는 보장되지 않는다.  
다른 프로퍼티에 의존하는 로직은 `PostRepNotifies()` 같은 후처리 함수를 활용한다.
