# 컴포넌트 생명주기

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Components/ActorComponent.h`  
> `Engine/Source/Runtime/Engine/Private/Components/ActorComponent.cpp`

---

## 컴포넌트 생명주기 전체 순서

```
[Actor 스폰 시]
  OnRegister()               ← bRegistered=true. World 연결. 에디터에서도 호출
  InitializeComponent()      ← bWantsInitializeComponent=true인 것만
  BeginPlay()                ← 게임 월드만. bHasBegunPlay=true
  TickComponent()            ← 매 프레임 (bCanEverTick=true인 것만)

[Actor 소멸 시]
  EndPlay(reason)            ← bHasBegunPlay=false
  UninitializeComponent()    ← bHasBeenInitialized=false
  OnUnregister()             ← bRegistered=false

[런타임 동적 추가 시]
  OnRegister()
  InitializeComponent()      ← bWantsInitializeComponent면
  BeginPlay()                ← Actor가 이미 BeginPlay 중이면 즉시

[런타임 동적 제거 시]
  EndPlay()
  UninitializeComponent()
  OnUnregister()
  DestroyComponent()
```

---

## OnRegister

```cpp
void UActorComponent::OnRegister()  // ActorComponent.cpp:1542
{
    // WorldPrivate가 null이면 check 실패 — 반드시 World에 소속돼야 함
    checkf(WorldPrivate, ...);
    checkf(!bRegistered, ...);

    bRegistered = true;
    UpdateComponentToWorld();    // SceneComponent: 월드 트랜스폼 갱신

    if (bAutoActivate)
    {
        // 에디터 월드이거나, Owner가 없거나, Owner가 초기화됐으면 Activate
        if (!WorldPrivate->IsGameWorld() || Owner == nullptr || Owner->IsActorInitialized())
            Activate(true);
    }
}
```

**핵심 특징**:
- 게임 월드, 에디터 월드 모두 호출됨
- `GetWorld()`는 유효하지만 **게임플레이는 보장되지 않음**
- `IsActorInitialized()` (PostInitializeComponents 이후)도 보장되지 않음
- 따라서 다른 컴포넌트를 찾거나 ASC에 접근하는 코드는 OnRegister에 두면 안 됨

**언제 OnRegister를 사용하나?**
- Manager 시스템에 등록 (GameFrameworkComponentManager::AddReceiver가 여기서 호출됨)
- 컴포넌트 자체 초기화 (다른 컴포넌트 참조 없이 self-contained한 것)

---

## OnUnregister

```cpp
void UActorComponent::OnUnregister()  // ActorComponent.cpp:1577
{
    check(bRegistered);
    bRegistered = false;
    RegistrationState = EComponentRegistrationState::None;
    ClearNeedEndOfFrameUpdate();
}
```

`OnRegister`의 역방향. `bRegistered = false` 설정.  
`EndPlay` 이후, `UninitializeComponent` 이후에 호출된다.

---

## InitializeComponent

```cpp
void UActorComponent::InitializeComponent()  // ActorComponent.cpp:1589
{
    check(bRegistered);          // OnRegister 이후여야 함
    check(!bHasBeenInitialized);
    bHasBeenInitialized = true;
}
```

**호출 조건**: `bWantsInitializeComponent == true`인 컴포넌트만.  
기본값은 `false`. 사용하려면 생성자에서 명시적으로 설정:

```cpp
MyComponent::MyComponent()
{
    bWantsInitializeComponent = true;
}
```

**OnRegister와의 차이**:

| | `OnRegister` | `InitializeComponent` |
|---|---|---|
| 호출 시점 | 컴포넌트가 World에 등록될 때 | PostInitializeComponents 직전 |
| 에디터에서 | O | X (게임 월드만) |
| Actor 준비 상태 | 미보장 | Actor 컴포넌트 전부 OnRegister 완료 |
| 기본 호출 | 항상 | bWantsInitializeComponent=true만 |

**UAbilitySystemComponent**는 `bWantsInitializeComponent = true`를 설정해 이 함수로 초기화한다.

---

## UninitializeComponent

```cpp
void UActorComponent::UninitializeComponent()  // ActorComponent.cpp:1597
{
    check(bHasBeenInitialized);
    bHasBeenInitialized = false;
}
```

`InitializeComponent`의 역방향. `RouteEndPlay` 내부에서 `EndPlay` 이후 호출된다.

---

## BeginPlay (컴포넌트)

```cpp
void UActorComponent::BeginPlay()  // ActorComponent.cpp:1609
{
    check(bRegistered);
    check(!bHasBegunPlay);
    checkSlow(bTickFunctionsRegistered);  // RegisterAllComponentTickFunctions 이후여야 함

    if (GetClass()->HasAnyClassFlags(CLASS_CompiledFromBlueprint) || ...)
        ReceiveBeginPlay();   // Blueprint Event BeginPlay

    bHasBegunPlay = true;
}
```

Actor의 `BeginPlay()`에서 등록된 컴포넌트들을 순회하며 호출한다.

**Actor보다 먼저 불리지 않는다** — Actor.cpp:4769:
```cpp
// Actor BeginPlay 내부
Component->RegisterAllComponentTickFunctions(true);
Component->BeginPlay();
// ...모든 컴포넌트 완료 후
ReceiveBeginPlay();  // ← Actor Blueprint BeginPlay는 마지막
```

즉 순서: **컴포넌트 BeginPlay 먼저 → Actor Blueprint BeginPlay 나중**.

---

## EndPlay (컴포넌트)

```cpp
void UActorComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)  // ActorComponent.cpp:1625
{
    check(bHasBegunPlay);

    if (EndPlayReason != EEndPlayReason::EndPlayInEditor && EndPlayReason != EEndPlayReason::Quit)
        UE::Net::FReplicationSystemUtil::StopReplicatingActorComponent(this);

    if (!HasAnyFlags(RF_BeginDestroyed) && !IsUnreachable() && ...)
        ReceiveEndPlay(EndPlayReason);

    bIsReadyForReplication = false;
    bHasBegunPlay = false;
}
```

Actor의 `EndPlay()`에서 `HasBegunPlay()`인 컴포넌트를 순회하며 호출한다.

---

## 런타임에 컴포넌트를 동적으로 추가할 때

Actor가 이미 BeginPlay를 거친 상태에서 컴포넌트를 추가하면:

```cpp
// Actor.cpp:6366 (HandleRegisterComponentWithWorld)
const bool bOwnerBeginPlayStarted = HasActorBegunPlay() || IsActorBeginningPlay();

if (bOwnerBeginPlayStarted && Component->GetIsReplicated())
    ReadyForReplication();  // 복제 준비

if (bOwnerBeginPlayStarted)
{
    Component->RegisterAllComponentTickFunctions(true);
    Component->BeginPlay();  // 즉시 BeginPlay 호출
}
```

`NewObject` + `RegisterComponent()`로 컴포넌트를 추가하면:
1. `OnRegister` 즉시 호출
2. `bWantsInitializeComponent`이면 `InitializeComponent` 즉시 호출
3. Actor가 이미 BeginPlay 상태이면 `BeginPlay` 즉시 호출

---

## 플래그 상태 요약

| 플래그 | true가 되는 시점 | false가 되는 시점 |
|--------|-----------------|------------------|
| `bRegistered` | `OnRegister()` | `OnUnregister()` |
| `bHasBeenInitialized` | `InitializeComponent()` | `UninitializeComponent()` |
| `bHasBegunPlay` | `BeginPlay()` (컴포넌트) | `EndPlay()` (컴포넌트) |
| `bIsReadyForReplication` | `ReadyForReplication()` | `EndPlay()` |
