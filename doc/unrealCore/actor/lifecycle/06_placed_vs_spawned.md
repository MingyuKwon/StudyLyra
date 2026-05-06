# 배치 Actor vs 동적 스폰 Actor 생명주기

> 출처:  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Private/Level.cpp`  
> `Engine/Source/Runtime/Engine/Private/World.cpp`

---

## 두 경로의 차이

Actor가 게임 세계에 진입하는 경로는 두 가지다.

| | 배치 Actor | 동적 스폰 Actor |
|---|---|---|
| 진입 방식 | 레벨 패키지를 직렬화로 복원 | `UWorld::SpawnActor()` 호출 |
| 로드 훅 | `PostLoad()` | `PostActorCreated()` |
| Construction Script | **조건부** (아래 설명) | 항상 실행 |
| `PostInitializeComponents` 이후 | **동일** | **동일** |

---

## 배치 Actor 전체 흐름

```
[레벨 패키지 로드]
  PostInitProperties()         ← UObject 할당 직후, World 없음
  PostLoad()                   ← 직렬화 완료 직후. 역직렬화 데이터 보정
                                  (SpawnActor 경로엔 없음)

[UWorld::InitializeActorsForPlay]
  UpdateWorldComponents()
    Level->IncrementalUpdateComponents()
      [각 Actor] RegisterAllComponents()    ← 컴포넌트 World 연결
      (에디터에서만) RerunConstructionScripts()  ← 조건부 (아래 설명)

  Level->RouteActorInitialize()
    [Phase 1 — Preinitialize]
      [각 Actor] PreInitializeComponents()

    [Phase 2 — Initialize]
      [각 Actor] InitializeComponents()     ← bWantsInitializeComponent=true 것만
      [각 Actor] PostInitializeComponents() ← bActorInitialized = true ★

    [Phase 3 — BeginPlay]
      [각 Actor] DispatchBeginPlay()
        BeginPlay()                         ← ★
```

---

## 동적 스폰 Actor 전체 흐름

```
[UWorld::SpawnActor() 호출]
  PostInitProperties()         ← UObject 할당 직후

  PostSpawnInitialize()
    ExchangeNetRoles()
    DispatchOnComponentsCreated()
    RegisterAllComponents()    ← 컴포넌트 World 연결

    PostActorCreated()         ← "스폰 완료" 훅 (배치 Actor엔 없음)

    ExecuteConstruction()
      OnConstruction()         ← C++ 훅
      [Blueprint SCS 실행]     ← Construction Script 항상 실행

    PostActorConstruction()
      PreInitializeComponents()
      InitializeComponents()
      PostInitializeComponents() ← bActorInitialized = true ★

    (World->HasBegunPlay() 이면) DispatchBeginPlay()
      BeginPlay()              ← ★
```

---

## Construction Script — 배치 Actor는 조건부 실행

가장 헷갈리는 부분이다.

```cpp
// World.cpp:5878
const bool bRerunConstructionScript =
    !(FPlatformProperties::RequiresCookedData()          // 쿠킹된 빌드면 스킵
    || (IsGameWorld() && (
        PersistentLevel->bHasRerunConstructionScripts    // 이미 실행했으면 스킵
        || PersistentLevel->bWasDuplicatedForPIE)));     // PIE 복제본이면 스킵
```

| 상황 | Construction Script 실행 여부 |
|------|:---:|
| 에디터에서 Actor 이동/프로퍼티 변경 | O (매번) |
| PIE 시작 (에디터에서 플레이) | X — 에디터 레벨을 복제하므로 이미 적용된 상태 |
| 패키징된 게임 (쿠킹 빌드) | X — 쿠킹 시 이미 결과가 베이크됨 |
| 패키징되지 않은 게임 (에디터 빌드) | O — 레벨 로드 시 재실행 |

**핵심**: 쿠킹 빌드에서는 배치 Actor의 Construction Script 결과가 직렬화에 포함된 채로 로드된다. `OnConstruction`은 런타임에 불리지 않는다.

---

## RouteActorInitialize — 3단계 Phase 구조

배치 Actor 초기화는 `Level::RouteActorInitialize()`가 담당한다.  
레벨 내 모든 Actor를 Phase 순서로 순회한다.

```cpp
// Level.cpp:3817
// Phase 1: 전체 Actor PreInitializeComponents 먼저
for (Actor : Level->Actors)
    Actor->PreInitializeComponents();

// Phase 2: 전체 Actor InitializeComponents + PostInitializeComponents
for (Actor : Level->Actors)
{
    Actor->InitializeComponents();
    Actor->PostInitializeComponents();
}

// Phase 3: 전체 Actor BeginPlay
for (Actor : Level->Actors)
    Actor->DispatchBeginPlay();
```

Actor별로 생성→초기화→BeginPlay를 완결짓지 않는다.  
**모든 Actor의 PreInit 완료 → 모든 Actor의 PostInit 완료 → 모든 Actor의 BeginPlay** 순이다.

동적 스폰은 이와 다르다 — 하나의 Actor를 스폰→초기화→BeginPlay까지 연속으로 처리한다.

---

## 주의해야 할 내용

### 1. `PostActorCreated`에 초기화 코드를 넣으면 배치 Actor는 실행되지 않는다

```cpp
// ❌ 이렇게 하면 배치 Actor는 초기화가 안 됨
void AMyActor::PostActorCreated()
{
    Super::PostActorCreated();
    InitializeSomething(); // SpawnActor 경로에서만 불린다
}

// ✅ 양쪽 모두 안전한 위치
void AMyActor::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    InitializeSomething(); // 배치/스폰 모두 여기서 만난다
}
```

### 2. `OnConstruction`은 에디터에서 여러 번 불린다

배치 Actor를 이동하거나 프로퍼티를 바꿀 때마다 재실행된다.  
상태 누적형 코드(배열 Add 등)를 여기에 두면 중복된다.

```cpp
// ❌ 이동할 때마다 중복 추가됨
void AMyActor::OnConstruction(const FTransform& Transform)
{
    MyArray.Add(NewObject<UMyObject>(this));
}

// ✅ 상태 누적 코드는 PostInitializeComponents에
```

### 3. 배치 Actor의 BeginPlay 타이밍 — 레벨 내 모든 Actor의 PostInit 이후다

```
[배치 Actor A] PostInitializeComponents
[배치 Actor B] PostInitializeComponents   ← A의 BeginPlay 전에 B의 PostInit이 끝남
[배치 Actor A] BeginPlay                  ← 여기서 B는 이미 초기화된 상태
[배치 Actor B] BeginPlay
```

`BeginPlay`에서 다른 배치 Actor를 `GetActorOfClass`로 찾으면 이미 `PostInitializeComponents`는 완료된 상태임이 보장된다.

### 4. 동적 스폰 후 `BeginPlay`가 즉시 불리는 조건

```cpp
// Actor.cpp — PostActorConstruction 내부
if (World->HasBegunPlay())
    DispatchBeginPlay(); // 이미 게임이 시작된 상태면 즉시 BeginPlay
```

게임 시작 전 스폰하면 `BeginPlay`는 `World->BeginPlay()` 때 불린다.  
게임 시작 후 스폰하면 `SpawnActor` 반환 전에 이미 `BeginPlay`가 불린 상태다.

### 5. `PostLoad`는 게임플레이와 무관한 보정 작업에만 쓴다

`PostLoad` 시점은 World가 게임 상태가 아니다.  
다른 Actor 참조, ASC 접근, GAS 호출은 절대 여기서 하면 안 된다.  
`PostLoad`의 용도: 구버전 데이터 마이그레이션, 내부 프로퍼티 보정.

---

## 흐름 요약 비교

```
배치 Actor:
  PostLoad → RegisterAllComponents → PreInitializeComponents
           → PostInitializeComponents ★ → BeginPlay ★

동적 스폰 Actor:
  PostActorCreated → OnConstruction → PreInitializeComponents
                  → PostInitializeComponents ★ → BeginPlay ★

공통 진입점: PostInitializeComponents
```
