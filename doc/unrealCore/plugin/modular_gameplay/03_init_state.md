# InitState 시스템

> 출처:  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkInitStateInterface.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Private/Components/GameFrameworkInitStateInterface.cpp`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponentManager.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Private/Components/GameFrameworkComponentManager.cpp`

---

## 개요

같은 Actor 위에 있는 여러 Feature(컴포넌트)가 **서로를 직접 참조하지 않고** 초기화 순서를 조율하는 시스템.

- **Feature**: `IGameFrameworkInitStateInterface`를 구현한 컴포넌트 하나
- **State**: GameplayTag로 표현하는 초기화 단계. 순서는 `UGameFrameworkComponentManager`에 전역 등록
- **Manager**: 각 Feature의 현재 상태를 저장하고 상태 변경 시 구독자에게 알림

---

## 전역 상태 순서 등록

상태 순서는 게임 시작 시 Manager에 명시적으로 등록해야 한다.

```cpp
Manager->RegisterInitState(TAG_InitState_Spawned,         true,  FGameplayTag());  // 맨 앞
Manager->RegisterInitState(TAG_InitState_DataAvailable,   false, TAG_InitState_Spawned);
Manager->RegisterInitState(TAG_InitState_DataInitialized, false, TAG_InitState_DataAvailable);
Manager->RegisterInitState(TAG_InitState_GameplayReady,   false, TAG_InitState_DataInitialized);
```

내부적으로 `TArray<FGameplayTag> InitStateOrder`에 순서대로 저장된다.  
중복 등록은 조용히 무시된다 (이미 있으면 return).

**`IsInitStateAfterOrEqual(A, B)`**: `InitStateOrder` 배열을 선형 스캔하며 A가 B보다 뒤에 있는지 확인한다.

---

## IGameFrameworkInitStateInterface

### 구현 대상

Actor 또는 ActorComponent 모두 구현할 수 있다.

```cpp
// GetOwningActor() 내부 구현
AActor* FoundActor = Cast<AActor>(this);           // Actor 자신이면 바로 사용
if (!FoundActor)
    FoundActor = Cast<UActorComponent>(this)->GetOwner();  // 아니면 Owner 가져옴
```

### 생명주기

```cpp
// OnRegister()에서
RegisterInitStateFeature();
// → Manager->RegisterFeatureImplementer(Actor, FeatureName, this)
// → ActorFeatureMap에 Feature 등록 (상태는 아직 없음)

BindOnActorInitStateChanged(FeatureName, RequiredState, bCallIfReached);
// → WeakLambda로 OnActorInitStateChanged 바인딩
// → ActorInitStateChangedHandle에 핸들 저장

// EndPlay()에서
UnregisterInitStateFeature();
// → this == Actor이면: Manager->RemoveActorFeatureData(Actor) — 모든 Feature 제거
// → this != Actor이면: Manager->RemoveFeatureImplementer(Actor, this) — 이 Feature만 제거
// → ActorInitStateChangedHandle이 유효하면 delegate도 해제
```

---

### TryToChangeInitState(DesiredState)

```
현재 상태 조회 (Manager->GetInitStateForFeature)
  │
  ├─ 이미 DesiredState → return false (변화 없음)
  │
  ├─ CanChangeInitState(Manager, Current, Desired) → false
  │     → 로그("Cannot transition") + return false
  │
  └─ CanChange true
        → HandleChangeInitState(Manager, Current, Desired)   ← 로컬 로직 먼저
        → Manager->ChangeFeatureInitState(Actor, Name, this, Desired)  ← Manager에 통보
        → return true
```

> **순서가 중요하다**: `HandleChangeInitState`(로컬)가 먼저 실행되고 나서 Manager가 구독자에게 알린다. 덕분에 `OnActorInitStateChanged` 콜백이 불릴 때 이미 로컬 상태 변경은 완료돼 있다.

---

### ContinueInitStateChain(ChainArray)

상태 순서 배열을 받아 현재 위치에서 가능한 만큼 앞으로 전진하는 루프.

```cpp
FGameplayTag ContinueInitStateChain(const TArray<FGameplayTag>& InitStateChain)
{
    int32 ChainIndex = 0;
    FGameplayTag CurrentState = Manager->GetInitStateForFeature(...);

    while (ChainIndex < ChainArray.Num() - 1)
    {
        if (CurrentState == ChainArray[ChainIndex])
        {
            FGameplayTag DesiredState = ChainArray[ChainIndex + 1];
            if (CanChangeInitState(Manager, CurrentState, DesiredState))
            {
                HandleChangeInitState(...);
                Manager->ChangeFeatureInitState(...);
                CurrentState = Manager->GetInitStateForFeature(...);  // 재조회
                // ChainIndex는 증가 안 함 → 같은 위치에서 다음 전이 재시도
            }
            // CanChange 실패해도 ChainIndex는 증가 → 막힌 곳에서 멈춤
        }
        ChainIndex++;
    }

    return CurrentState;  // 도달한 최종 상태
}
```

`CheckDefaultInitialization()`은 이 함수를 매번 호출해 "지금 조건이 됐다면 다음 단계로"를 반복한다.

---

### CheckDefaultInitializationForImplementers()

자기 자신을 제외한 같은 Actor의 모든 Feature 구현체에게 `CheckDefaultInitialization()`을 호출한다.

```cpp
Manager->GetAllFeatureImplementers(Implementers, MyActor, FGameplayTag(), MyFeatureName /*exclude*/);
for (UObject* Implementer : Implementers)
    Cast<IGameFrameworkInitStateInterface>(Implementer)->CheckDefaultInitialization();
```

한 Feature의 상태 변경이 다른 Feature의 초기화를 유발할 수 있도록 연쇄 촉발하는 역할이다.

---

## Manager — InitState 파트

### 내부 자료구조

```cpp
// 전역 상태 순서 배열
TArray<FGameplayTag> InitStateOrder;

// Actor별 Feature 데이터
TMap<FObjectKey, FActorFeatureData> ActorFeatureMap;

struct FActorFeatureData
{
    TWeakObjectPtr<UClass> ActorClass;
    TArray<FActorFeatureState> RegisteredStates;  // Feature별 현재 상태
    FActorFeatureDelegates RegisteredDelegates;   // 이 Actor에 등록된 구독 델리게이트
};

struct FActorFeatureState
{
    FName FeatureName;
    FGameplayTag CurrentState;
    TWeakObjectPtr<UObject> Implementer;  // IGameFrameworkInitStateInterface 구현체
};

// 클래스 단위 구독 (특정 Actor 인스턴스가 아닌 클래스 전체)
TMap<FComponentRequestReceiverClassPath, FActorFeatureDelegateList> ClassFeatureChangeDelegates;

// 재귀 방지용 큐
TArray<TPair<AActor*, FActorFeatureState>> StateChangeQueue;
int32 CurrentStateChange;  // INDEX_NONE이면 처리 중 아님
```

---

### ChangeFeatureInitState() + ProcessFeatureStateChange() — 재귀 방지 큐

상태 변경이 콜백을 부르고 그 콜백이 또 상태를 변경하는 재귀 호출을 막기 위해 큐 방식을 사용한다.

```cpp
void ProcessFeatureStateChange(AActor* Actor, const FActorFeatureState* StateChange)
{
    StateChangeQueue.Emplace(Actor, *StateChange);  // 항상 큐에 추가

    if (CurrentStateChange == INDEX_NONE)  // 현재 처리 중이 아니면
    {
        CurrentStateChange = 0;

        while (CurrentStateChange < StateChangeQueue.Num())  // 큐가 비워질 때까지
        {
            CallFeatureStateDelegates(...);  // 콜백 실행 (내부에서 새 변경이 큐에 추가될 수 있음)
            CurrentStateChange++;
        }

        StateChangeQueue.Empty();
        CurrentStateChange = INDEX_NONE;
    }
    // 이미 처리 중(CurrentStateChange != INDEX_NONE)이면
    // 큐에 추가만 하고 즉시 리턴 → 현재 처리 루프가 나중에 처리함
}
```

예시:
```
A 상태 변경 → 큐: [A]  CurrentStateChange=0
  A 콜백 실행 → B 상태 변경 → 큐: [A, B]
    B는 재귀 실행 안 함, 큐에만 추가
  A 처리 완료 → CurrentStateChange=1
  B 콜백 실행 → ...
큐 비워짐 → CurrentStateChange=INDEX_NONE
```

---

### CallFeatureStateDelegates() — 델리게이트 필터링

```cpp
// 조건 1: RequiredFeatureName이 지정됐으면 해당 Feature만
(RegisteredDelegate.RequiredFeatureName.IsNone() || RequiredFeatureName == StateChange.FeatureName)

// 조건 2: RequiredInitState가 지정됐으면 그 상태 이상에 도달했을 때만
(!RegisteredDelegate.RequiredInitState.IsValid() || IsInitStateAfterOrEqual(StateChange.CurrentState, RequiredInitState))
```

구독 범위가 두 가지다:
- **Actor 인스턴스 단위**: `ActorFeatureData::RegisteredDelegates` — 특정 Actor 인스턴스에만 반응
- **클래스 단위**: `ClassFeatureChangeDelegates` — 해당 클래스의 모든 Actor 인스턴스에 반응 (클래스 계층 포함)

**안전한 실행 순서**:
1. 먼저 조건에 맞는 delegate를 `QueuedDelegates`에 복사
2. 복사본을 순회하며 실행 (실행 중 원본 목록이 변경돼도 안전)
3. `bRemoved == true`인 delegate는 `Execute()` 내부에서 조용히 스킵

---

### HaveAllFeaturesReachedInitState()

```cpp
bool HaveAllFeaturesReachedInitState(AActor* Actor, FGameplayTag RequiredState, FName ExcludingFeature)
{
    for (const FActorFeatureState& State : ActorStruct->RegisteredStates)
    {
        if (State.FeatureName != ExcludingFeature)
        {
            if (!IsInitStateAfterOrEqual(State.CurrentState, RequiredState))
                return false;  // 하나라도 미달이면 false
        }
    }
    return true;  // 주의: Feature가 0개여도 true 반환 (TODO 주석 있음)
}
```

`LyraPawnExtensionComponent`가 `DataInitialized`로 전이할 조건을 체크할 때 이 함수를 사용한다.

---

## 흐름 다이어그램

```
[OnRegister]
  RegisterInitStateFeature()      → Manager: ActorFeatureMap에 Feature 등록
  BindOnActorInitStateChanged()   → Manager: 다른 Feature 상태 변경 시 콜백 등록

[BeginPlay → CheckDefaultInitialization]
  ContinueInitStateChain([S0, S1, S2, S3])
    CanChange(S0 → S1)? → HandleChange + Manager->ChangeFeatureInitState
      ProcessFeatureStateChange → 큐에 추가
        (처리 중 아니면) 큐 처리 시작
          CallFeatureStateDelegates → OnActorInitStateChanged 콜백
            다른 Feature: CheckDefaultInitialization() 재호출 → 연쇄 전이
    CanChange(S1 → S2)? → ...

[EndPlay]
  UnregisterInitStateFeature()    → Manager: Feature 등록 해제 + delegate 해제
```
