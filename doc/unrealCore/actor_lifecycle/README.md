# Actor 생명주기

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/Actor.h`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Classes/Components/ActorComponent.h`  
> `Engine/Source/Runtime/Engine/Private/Components/ActorComponent.cpp`

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_creation.md](01_creation.md) | 생성 단계 — PostInitProperties → PostInitializeComponents |
| [02_gameplay.md](02_gameplay.md) | 게임플레이 단계 — BeginPlay / Tick / EndPlay / Destroyed |
| [03_component.md](03_component.md) | 컴포넌트 생명주기 — OnRegister / InitializeComponent / BeginPlay / EndPlay |
| [04_replication.md](04_replication.md) | 복제 훅 — GetLifetimeReplicatedProps / PreReplication / OnRep_ |

---

## 전체 타임라인

```
─────────────────── 생성 단계 ───────────────────
UObject 할당
  PostInitProperties()              ← 프로퍼티 초기화 직후. RemoteRole 결정
  PostLoad()                        ← 에셋 로드 시만 (스폰이면 호출 안 됨)

SpawnActor() 호출
  ExchangeNetRoles()                ← 서버/클라이언트 Role 교환
  DispatchOnComponentsCreated()     ← 모든 native 컴포넌트 OnComponentCreated
  RegisterAllComponents()
    PreRegisterAllComponents()      ← 컴포넌트 등록 직전 훅
    [각 컴포넌트] OnRegister()      ← bRegistered = true, World에 연결
    PostRegisterAllComponents()     ← 컴포넌트 등록 완료 훅
  PostActorCreated()                ← "스폰 완료" (기본 구현 비어있음)
  ExecuteConstruction()
    OnConstruction(Transform)       ← Blueprint Construction Script 직전 C++ 훅
    [Blueprint SCS 실행]
  PostActorConstruction()
    PreInitializeComponents()       ← AutoReceiveInput 처리
    [각 컴포넌트] InitializeComponent()  ← bWantsInitializeComponent=true인 것만
    PostInitializeComponents()      ← bActorInitialized = true ★

─────────────────── 게임플레이 단계 ───────────────────
World->HasBegunPlay() 가 true가 되는 시점
  DispatchBeginPlay()
    BuildReplicatedComponentsInfo()
    StartReplicatingActor()
    BeginPlay()                     ← ★ 게임 로직 시작점
      SetLifeSpan()
      RegisterAllActorTickFunctions()
      [각 컴포넌트] BeginPlay()
      ReceiveBeginPlay()            ← BP Event BeginPlay

  [매 프레임]
  Tick(DeltaSeconds)
  [각 컴포넌트] TickComponent()

─────────────────── 소멸 단계 ───────────────────
DestroyActor() 또는 레벨 언로드
  RouteEndPlay(EndPlayReason)
    EndPlay(EndPlayReason)          ← ★ 소멸 직전 정리
      StopReplicatingActor()
      ReceiveEndPlay()
      [각 컴포넌트] EndPlay()
    UninitializeComponents()
      [각 컴포넌트] UninitializeComponent()
  Destroyed()
    RouteEndPlay(Destroyed)
    ReceiveDestroyed()
    OnDestroyed.Broadcast()
  [각 컴포넌트] OnUnregister()
  GC에 의해 메모리 해제
```

---

## 핵심 구분

| 함수 | 에디터에서도 불리나 | 게임플레이 보장 | 컴포넌트 등록 보장 |
|------|:---:|:---:|:---:|
| `PostInitProperties` | O | X | X |
| `OnRegister` (컴포넌트) | O | X | - |
| `PostInitializeComponents` | X (게임월드만) | X | O |
| `BeginPlay` | X (게임월드만) | O | O |
| `Tick` | X (기본값) | O | O |
| `EndPlay` | X | O | O |
