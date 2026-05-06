# 게임 월드와 Actor 생명주기

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/World.h`  
> `Engine/Source/Runtime/Engine/Private/World.cpp`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`

---

## 왜 "게임 월드"가 중요한가

Actor 생명주기 함수들이 "게임 월드에서만 호출된다"는 조건이 반복해서 등장한다.  
이유는 단순하다: **언리얼에서 `UWorld`는 단 한 종류가 아니기 때문이다.**

---

## EWorldType — World의 종류

```cpp
// Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h
namespace EWorldType
{
    enum Type
    {
        None,           // 타입 미지정 (스트리밍 서브레벨의 잔재 등)
        Game,           // 실제 게임 런타임 (패키징된 빌드)
        Editor,         // 레벨 에디터에서 편집 중인 World
        PIE,            // 에디터에서 Play 버튼을 누른 World
        EditorPreview,  // BP 에디터 뷰포트, 썸네일 렌더 등
        GamePreview,    // 게임용 프리뷰 World
        GameRPC,        // 최소 RPC 전용 World
        Inactive        // 로드는 됐지만 에디터에서 편집 중이 아닌 상태
    };
}
```

Actor는 **레벨 에디터에 배치되는 순간부터 존재**한다 — `Editor` World 안에서.  
`PostInitProperties`, `OnRegister`는 그 시점에도 불린다.

---

## IsGameWorld() — 경계를 가르는 함수

```cpp
// Engine/Source/Runtime/Engine/Private/World.cpp:9177
bool UWorld::IsGameWorld() const
{
    return WorldType == EWorldType::Game
        || WorldType == EWorldType::PIE
        || WorldType == EWorldType::GamePreview
        || WorldType == EWorldType::GameRPC;
}
```

`Editor`와 `EditorPreview`는 여기에 포함되지 않는다.  
`PIE`는 포함된다 — 에디터 내에서 Play를 누른 순간부터는 게임 월드다.

---

## AreActorsInitialized() — PostInitializeComponents의 실제 조건

`PostInitializeComponents`는 단순히 "게임 월드이면" 호출되는 게 아니다.  
`World->AreActorsInitialized()`가 `true`일 때만 호출된다.

```cpp
// Engine/Source/Runtime/Engine/Private/Actor.cpp:4409 — PostActorConstruction()
bool const bActorsInitialized = World && World->AreActorsInitialized();

if (bActorsInitialized)
{
    PreInitializeComponents();
}

if (bActorsInitialized)
{
    InitializeComponents();
    // ...
    PostInitializeComponents();
}
```

```cpp
// Engine/Source/Runtime/Engine/Private/World.cpp:6690
bool UWorld::AreActorsInitialized() const
{
    return bActorsInitialized && PersistentLevel && PersistentLevel->Actors.Num();
}
```

`bActorsInitialized` 플래그는 `UWorld::InitializeActorsForPlay()` 안에서 설정된다.

```cpp
// Engine/Source/Runtime/Engine/Private/World.cpp:5912
// (UWorld::InitializeActorsForPlay 내부)
bStartup = true;
bActorsInitialized = true;
```

이 함수는 **게임플레이 시작 직전** — PIE에서 Play 버튼을 누르거나, 패키징된 게임이 레벨을 로드할 때 — 호출된다.

---

## BeginPlay의 조건

```cpp
// Engine/Source/Runtime/Engine/Private/Actor.cpp:4482
bool bRunBeginPlay = !bDeferBeginPlayAndUpdateOverlaps
    && (BeginPlayCallDepth > 0 || World->HasBegunPlay());
```

`World->HasBegunPlay()`가 `true`여야 한다.  
`AreActorsInitialized()`와는 별개의 플래그다. `World::BeginPlay()`가 호출된 이후에야 `true`가 된다.

```
InitializeActorsForPlay()     → bActorsInitialized = true → PostInitializeComponents 가능
World::BeginPlay()            → HasBegunPlay = true       → BeginPlay 가능
```

---

## 게임 월드 없이 Actor가 생성되는 케이스

### 1. CDO (Class Default Object)

모든 `UClass`는 엔진 시작 시 인스턴스를 하나 만들어 기본값 저장에 사용한다.  
이 시점엔 World가 전혀 없다.

```cpp
// Actor.cpp:535
void AActor::PostInitProperties()
{
    if (!HasAnyFlags(RF_ClassDefaultObject))
        ResetOwnedComponents();   // CDO면 이 블록 건너뜀
}
```

`RF_ClassDefaultObject` 플래그로 CDO인지 구분하는 코드가 곳곳에 있다.

### 2. 에디터 배치 Actor (Editor World)

레벨에 끌어다 놓은 Actor는 `EWorldType::Editor` World에 존재한다.  
`GetWorld()`는 유효하지만 `IsGameWorld() == false`.

- `PostInitProperties` — 호출됨
- `OnRegister` — 호출됨 (Editor World에 등록)
- `PostInitializeComponents` — **호출 안 됨** (`AreActorsInitialized() == false`)
- `BeginPlay` — **호출 안 됨**

### 3. 에셋 로드 (`PostLoad` 경로)

저장된 패키지를 불러올 때 `PostLoad`가 호출된다.  
`SpawnActor` 경로를 타지 않으므로 `PostActorCreated`, `PostInitializeComponents`, `BeginPlay` 모두 호출되지 않는다.

---

## World 타입별 호출 함수 정리

| 함수 | CDO (World 없음) | Editor World | PIE / Game World |
|------|:---:|:---:|:---:|
| `PostInitProperties` | O | O | O |
| `PostLoad` (로드 경로만) | — | O | O |
| `OnRegister` (컴포넌트) | X | O | O |
| `PostInitializeComponents` | X | X | **O** |
| `BeginPlay` | X | X | **O** |
| `Tick` | X | X (기본 비활성) | **O** |
| `EndPlay` | X | X | **O** |

---

## 실전에서 왜 중요한가

```cpp
// 위험 — CDO나 에디터 배치 시 GetWorld()가 nullptr
void AMyActor::PostInitProperties()
{
    Super::PostInitProperties();
    GetWorld()->GetGameInstance();  // ← null 역참조
}

// 안전 — 게임 World 보장 이후
void AMyActor::BeginPlay()
{
    Super::BeginPlay();
    GetWorld()->GetGameInstance();  // ← 항상 유효
}
```

GAS에서 ASC 초기화를 `PostInitializeComponents`나 `BeginPlay` 안에서 처리하는 이유가 여기 있다.  
그 이전엔 `AreActorsInitialized() == false`이므로 네트워크 Role 판단, 복제 등록 등이 불가능하다.

---

## 흐름 요약

```
엔진 시작
  └─ CDO 생성 → PostInitProperties (World 없음)

에디터 레벨 열기
  └─ Actor 로드 → PostLoad
  └─ RegisterAllComponents → OnRegister  (Editor World)
     [PostInitializeComponents, BeginPlay는 없음]

PIE Play 버튼 / 게임 시작
  └─ InitializeActorsForPlay()
       bActorsInitialized = true
       → PostInitializeComponents 호출 가능
  └─ World::BeginPlay()
       HasBegunPlay = true
       → BeginPlay 호출
```
