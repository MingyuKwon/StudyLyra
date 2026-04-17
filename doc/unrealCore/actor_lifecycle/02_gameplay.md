# BeginPlay / Tick / EndPlay / Destroyed

> 출처: `Engine/Source/Runtime/Engine/Private/Actor.cpp`

---

## BeginPlay

### 호출 경로

```
World->BeginPlay()
  또는
PostActorConstruction() → (World->HasBegunPlay() 이면) DispatchBeginPlay()

DispatchBeginPlay()                     ← Actor.cpp:4690
  BuildReplicatedComponentsInfo()       ← 복제 대상 컴포넌트 목록 구성
  ActorHasBegunPlay = BeginningPlay
  StartReplicatingActor()               ← 복제 시스템 등록
  BeginPlay()                           ← ★
  UpdateInitialOverlaps()               ← BeginPlay 이후 오버랩 초기화
```

### BeginPlay() 내부

```cpp
void AActor::BeginPlay()  // Actor.cpp:4753
{
    SetLifeSpan(InitialLifeSpan);               // LifeSpan 타이머 시작
    RegisterAllActorTickFunctions(true, false); // Actor 틱 함수 등록
    
    for (UActorComponent* Component : Components)
    {
        if (Component->IsRegistered() && !Component->HasBegunPlay())
        {
            Component->RegisterAllComponentTickFunctions(true);
            Component->BeginPlay();     // ★ 컴포넌트 BeginPlay
        }
    }
    
    ReceiveBeginPlay();   // Blueprint Event BeginPlay
    ActorHasBegunPlay = EActorBeginPlayState::HasBegunPlay;
}
```

**호출 조건**:
- 게임 월드에서만 (`World->IsGameWorld()`)
- `PostInitializeComponents` 이후
- 네트워크: 복제된 Actor는 초기 상태가 적용된 후 (`bActorIsPendingPostNetInit == false`)

**BeginPlay 중 DestroyActor 호출 시**:  
즉시 파괴하지 않고 `bActorWantsDestroyDuringBeginPlay = true`를 설정, BeginPlay 완료 후 파괴.

---

## Tick

```cpp
virtual void Tick(float DeltaSeconds);  // Actor.h:3059
```

**등록 조건**: `RegisterAllActorTickFunctions()`에서 틱 함수가 등록돼야 한다.  
기본값: `PrimaryActorTick.bCanEverTick = false`.

틱을 원하는 Actor는 생성자에서:
```cpp
PrimaryActorTick.bCanEverTick = true;
```

**게임 월드에서만** 실행된다 (에디터 Tick은 기본 비활성화).

틱 그룹(`ETickingGroup`):
| 그룹 | 설명 |
|------|------|
| `TG_PrePhysics` | 물리 시뮬레이션 전 |
| `TG_DuringPhysics` | 물리 중 (비동기) |
| `TG_PostPhysics` | 물리 후 |
| `TG_PostUpdateWork` | 모든 틱 후 마무리 작업 |

---

## EndPlay

### 호출 시점

`EndPlay`는 **BeginPlay를 거친 Actor에게만** 호출된다.

```cpp
// Actor.cpp:3194 — RouteEndPlay
void AActor::RouteEndPlay(const EEndPlayReason::Type EndPlayReason)
{
    if (bActorInitialized)
    {
        if (ActorHasBegunPlay == EActorBeginPlayState::HasBegunPlay)
        {
            EndPlay(EndPlayReason);  // ← BeginPlay를 거친 경우만
        }
        UninitializeComponents();    // ← 항상 실행
    }
}
```

**`EEndPlayReason` 종류**:
| 값 | 발생 상황 |
|----|----------|
| `Destroyed` | `DestroyActor()` 호출 |
| `LevelTransition` | 레벨 전환 |
| `EndPlayInEditor` | 에디터 PIE 종료 |
| `RemovedFromWorld` | 스트리밍 레벨 언로드 |
| `Quit` | 게임 종료 |

### EndPlay() 내부

```cpp
void AActor::EndPlay(const EEndPlayReason::Type EndPlayReason)  // Actor.cpp:3232
{
    ActorHasBegunPlay = EActorBeginPlayState::HasNotBegunPlay;
    StopReplicatingActor();       // 복제 중단
    ReceiveEndPlay(EndPlayReason); // BP Event EndPlay
    OnEndPlay.Broadcast(this, EndPlayReason);

    for (UActorComponent* Component : Components)
    {
        if (Component->HasBegunPlay())
            Component->EndPlay(EndPlayReason);  // 각 컴포넌트 EndPlay
    }
}
```

> `Super::EndPlay()`를 호출하지 않으면 `ensureMsgf` 실패 — `ActorHasBegunPlay`가 `HasNotBegunPlay`로 전환되지 않아 다음 단계에서 문제가 생긴다.

---

## Destroyed

```cpp
void AActor::Destroyed()  // Actor.cpp:3284
{
    RouteEndPlay(EEndPlayReason::Destroyed);  // EndPlay + UninitializeComponents
    ReceiveDestroyed();                        // BP Event Destroyed
    OnDestroyed.Broadcast(this);
}
```

**호출 시점**: `DestroyActor()`가 실제로 Actor를 제거할 때.  
`EndPlay(Destroyed)`와 다르다 — `EndPlay`는 살아있지만 게임플레이를 끝낼 때도 불리지만, `Destroyed`는 메모리에서 제거될 때만 불린다.

---

## EndPlay vs Destroyed 차이

| | `EndPlay` | `Destroyed` |
|---|---|---|
| 호출 조건 | BeginPlay를 거친 경우만 | DestroyActor 시 항상 |
| 복제 중단 | O (StopReplicatingActor) | X (Destroyed 안에서 RouteEndPlay가 함) |
| 리소스 정리 | 여기서 해야 함 | EndPlay 이후라 보통 추가 작업 없음 |
| 여러 번 불릴 수 있나 | Reason별로 다양 | 항상 Destroyed reason 하나 |

---

## 소멸 단계 흐름 요약

```
DestroyActor() 또는 레벨 언로드
  │
  RouteEndPlay(reason)
    ├─ (BeginPlay 거쳤으면) EndPlay(reason)
    │     ActorHasBegunPlay = HasNotBegunPlay
    │     StopReplicatingActor()
    │     ReceiveEndPlay(reason)
    │     [각 컴포넌트] EndPlay(reason)
    │
    └─ UninitializeComponents()
          [각 컴포넌트] UninitializeComponent()
  │
  Destroyed()   (DestroyActor인 경우)
    ReceiveDestroyed()
    OnDestroyed.Broadcast()
  │
  [각 컴포넌트] OnUnregister()
  │
  GC → BeginDestroy() → FinishDestroy()
```
