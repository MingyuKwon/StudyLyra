# Actor 생성 단계

> 출처: `Engine/Source/Runtime/Engine/Private/Actor.cpp`

---

## PostInitProperties

```cpp
// Actor.cpp:535
void AActor::PostInitProperties()
{
    Super::PostInitProperties();
    RemoteRole = (bReplicates ? ROLE_SimulatedProxy : ROLE_None);
    if (!HasAnyFlags(RF_ClassDefaultObject))
        ResetOwnedComponents();
}
```

**호출 시점**: UObject 메모리 할당 직후, CDO에서 프로퍼티 복사가 끝난 뒤 바로.  
**게임 월드 불필요**. 에디터, 로드, 스폰 모두 호출됨.

여기서 하는 일:
- `bReplicates` 값에 따라 `RemoteRole` 초기화 (`SimulatedProxy` or `None`)
- `OwnedComponents` 목록 리셋 (CDO에서 복사된 bogus 엔트리 제거)

> 이 시점엔 World가 없다. `GetWorld()`가 null일 수 있음.

---

## PostLoad

```cpp
void AActor::PostLoad()  // Actor.cpp:1103
```

**호출 시점**: 에셋에서 **로드**될 때만. `SpawnActor`로 스폰된 경우엔 호출되지 않는다.  
주로 에디터에서 레벨을 열거나 패키지를 로드할 때 발생한다.

---

## SpawnActor → PostSpawnInitialize

`UWorld::SpawnActor()` 내부에서 `PostSpawnInitialize()`를 호출한다.

```cpp
// Actor.cpp:4249 — PostSpawnInitialize 주석
// General flow here is like so
// - Actor sets up the basics.
// - Actor gets PreInitializeComponents()
// - Actor constructs itself, after which its components should be fully assembled
// - Actor components get OnComponentCreated
// - Actor components get InitializeComponent
// - Actor gets PostInitializeComponents() once everything is set up
```

`PostSpawnInitialize()` 내부 순서:

```
ExchangeNetRoles(bRemoteOwned)    ← 서버/클라이언트 Role 교환
SetOwner(InOwner)
SetInstigator(InInstigator)
FixupNativeActorComponents()      ← RootComponent 정비
DispatchOnComponentsCreated()     ← 모든 native 컴포넌트 OnComponentCreated 호출
RegisterAllComponents()           ← 컴포넌트 등록 (아래 참조)
PostActorCreated()
FinishSpawning()
  ExecuteConstruction()           ← OnConstruction + BP SCS
  PostActorConstruction()         ← PreInitializeComponents ~ PostInitializeComponents
```

---

## RegisterAllComponents → OnRegister (컴포넌트)

```
PreRegisterAllComponents()           ← Actor 훅 (엔진 기본 구현: 거의 비어있음)
  [각 native 컴포넌트]
    RegisterComponentWithWorld()
      OnRegister()                   ← ★ 컴포넌트에서 가장 먼저 불리는 게임 훅
PostRegisterAllComponents()          ← Actor 훅
```

`OnRegister()`가 하는 일 (ActorComponent.cpp:1542):
- `bRegistered = true` 설정
- `WorldPrivate` 연결 (World 없으면 check 실패)
- `bAutoActivate = true`이면 `Activate()` 호출
- `UpdateComponentToWorld()` (SceneComponent의 월드 트랜스폼 갱신)

**중요**: `OnRegister`는 **게임 월드 여부와 무관**하게 호출된다. 에디터에서 레벨을 열 때도 불린다. `GetWorld()`는 유효하지만 게임플레이는 아직 시작되지 않은 상태다.

---

## PostActorCreated

```cpp
void AActor::PostActorCreated()  // Actor.cpp:2094
{
    // nothing at the moment
}
```

**호출 시점**: 컴포넌트 등록 완료 후, Construction Script 실행 전.  
코드 주석: *"We've fully spawned"*

기본 구현이 비어있어 override 포인트로 사용한다. `PostLoad()`와 상호 배타적이다 — 스폰이면 `PostActorCreated`, 로드이면 `PostLoad`.

---

## OnConstruction

```cpp
virtual void OnConstruction(const FTransform& Transform) {}  // Actor.h:3448
```

**호출 시점**: `ExecuteConstruction()` 내부, Blueprint의 Construction Script가 실행되기 직전 C++ 훅.

사용 시 주의: Construction Script는 에디터에서 Actor를 이동/회전할 때마다 재실행되므로, 이 함수도 여러 번 불릴 수 있다.

---

## PreInitializeComponents

```cpp
void AActor::PreInitializeComponents()  // Actor.cpp:6556
{
    if (AutoReceiveInput != EAutoReceiveInput::Disabled)
    {
        // PlayerController를 찾아 EnableInput() 호출
    }
}
```

**호출 시점**: `PostActorConstruction()` 진입 시. 컴포넌트 `InitializeComponent` 호출 전.  
**게임 월드에서만** 호출된다 (`bActorsInitialized` 확인).

override 시 `Super::PreInitializeComponents()` 반드시 호출 (AutoReceiveInput 처리 누락 방지).

---

## InitializeComponent (컴포넌트)

```cpp
void UActorComponent::InitializeComponent()  // ActorComponent.cpp:1589
{
    check(bRegistered);           // OnRegister 이후여야 함
    check(!bHasBeenInitialized);
    bHasBeenInitialized = true;
}
```

**호출 조건**: `bWantsInitializeComponent == true`인 컴포넌트만 호출된다.  
기본값은 `false`. ASC(`UAbilitySystemComponent`)처럼 초기화 작업이 필요한 컴포넌트가 생성자에서 `bWantsInitializeComponent = true`로 설정한다.

`OnRegister` 이후, `BeginPlay` 이전이다.

---

## PostInitializeComponents ★

```cpp
void AActor::PostInitializeComponents()  // Actor.cpp:6544
{
    if (IsValidChecked(this))
    {
        bActorInitialized = true;        // ← 핵심
        UpdateAllReplicatedComponents();
    }
}
```

**호출 시점**: 모든 컴포넌트의 `InitializeComponent`가 완료된 직후.  
**게임 월드에서만** 호출.

`bActorInitialized = true`가 설정되는 시점. 이 플래그는:
- `IsActorInitialized()` 반환값
- `GameFrameworkComponentManager::AddReceiver` 등에서 Actor 준비 여부 확인에 사용

> `PostInitializeComponents`에서 `Super::PostInitializeComponents()`를 호출하지 않으면 **Fatal 오류**가 발생한다.  
> `bActorInitialized`가 false인 채로 다음 단계로 넘어가기 때문.

```
// Actor.cpp:4479
UE_LOG(LogActor, Fatal, TEXT("%s failed to route PostInitializeComponents.
    Please call Super::PostInitializeComponents()..."));
```

---

## 생성 단계 흐름 요약

```
PostInitProperties          World 없음, 프로퍼티 초기화
     │
PostActorCreated            컴포넌트 등록 완료, Construction Script 직전
     │
[각 컴포넌트 OnRegister]    World 연결, bRegistered=true. 에디터에서도 호출
     │
OnConstruction              BP SCS 직전 C++ 훅
     │
PreInitializeComponents     AutoReceiveInput 처리. 게임월드만
     │
[각 컴포넌트 InitializeComponent]  bWantsInitializeComponent=true인 것만
     │
PostInitializeComponents ★  bActorInitialized=true. 게임월드만. Super 필수
     │
(BeginPlay로 이어짐)
```
