# GameplayTask 복제

> 소스: `Engine/Source/Runtime/GameplayTasks/`, `Engine/Plugins/Runtime/GameplayAbilities/`

---

## 기본 원칙: 각 머신이 코드를 직접 실행한다

태스크 코드는 복제되지 않는다. 각 머신이 자기 로컬에서 태스크를 직접 생성하고 실행한다.

| 주체 | 실행 방식 | 게임 스테이트 변경 |
|---|---|---|
| Server | `Activate()` 직접 실행 — 권위 있는 실행 | 가능 |
| Owning Client | `Activate()` 직접 실행 — 예측 실행 (GA Policy에 따라) | 가능 (서버와 조율) |
| Simulated Proxy | 기본적으로 없음. `bSimulatedTask`로 로컬 시뮬레이션 가능 | 불가 — 비주얼 전용 |

Simulated proxy에 GA가 실행되지 않는 이유는 **권위(authority)** 때문이다.
Simulated proxy는 남의 캐릭터를 보는 머신이라 게임 스테이트를 변경할 권한도, PlayerController도 없다.

종료 권한도 서버에 있다. Simulated proxy는 `EndTask()`를 직접 호출하지 않고, 서버가 종료하면 `SimulatedTasks[]`에서 제거가 복제되어 `PreDestroyFromReplication()`으로 정리된다.

---

## bSimulatedTask 패턴

### 흐름

`bSimulatedTask = true`로 설정하면 태스크가 `SimulatedTasks[]` 배열에 등록되고 simulated proxy로 복제된다.
Simulated proxy가 받는 것은 "태스크를 실행해"라는 명령이 아니라 **파라미터 데이터**다.
그 파라미터로 서버와 같아 보이는 효과를 로컬에서 재현한다.

#### 서버 측 — 태스크 활성화 시

```cpp
// GameplayTasksComponent.cpp:80
void UGameplayTasksComponent::OnGameplayTaskActivated(UGameplayTask& Task)
{
    KnownTasks.Add(&Task);
    if (Task.IsTickingTask())   { TickingTasks.Add(&Task); }
    if (Task.IsSimulatedTask()) { AddSimulatedTask(&Task); }  // bSimulatedTask=true 경우
}

// GameplayTasksComponent.cpp:786
bool UGameplayTasksComponent::AddSimulatedTask(UGameplayTask* NewTask)
{
    SimulatedTasks.Add(NewTask);
    SetSimulatedTasksNetDirty();                           // Push Model: 다음 net update에서 복제 예약
    AddReplicatedSubObject(NewTask, COND_SkipOwner);       // 태스크 객체도 서브오브젝트로 등록
    return true;
}
```

`COND_SkipOwner` — owning client는 이미 `Activate()`로 직접 돌리고 있으므로 복제 불필요.

#### 클라이언트 측 — 복제 수신 시

```cpp
// GameplayTasksComponent.cpp:205
void UGameplayTasksComponent::OnRep_SimulatedTasks()
{
    for (UGameplayTask* SimulatedTask : GetSimulatedTasks())
    {
        // bTickingTask=true 이고 아직 TickingTasks에 없는(= 새로 도착한) 태스크만
        if (SimulatedTask->IsTickingTask() && TickingTasks.Contains(SimulatedTask) == false)
        {
            SimulatedTask->InitSimulatedTask(*this);   // ← 유일한 호출 지점
            TickingTasks.Add(SimulatedTask);
            UpdateShouldTick();
        }
    }
    PreviousOnRepSimulatedTasks.Empty();
    PreviousOnRepSimulatedTasks.Append(SimulatedTasks);
}
```

#### 전체 체인

```
[Server] PerformActivation()
  → OnGameplayTaskActivated() → AddSimulatedTask()
      → SimulatedTasks.Add() + SetSimulatedTasksNetDirty()

[Next Net Update] SimulatedTasks 배열 → simulated proxy 전송

[Simulated Proxy] OnRep_SimulatedTasks()
  → IsTickingTask() && 신규?
      YES → InitSimulatedTask()   (bIsSimulating=true + 시뮬레이션 시작)
      NO  → 객체만 복제됨, InitSimulatedTask 호출 없음
```

### InitSimulatedTask는 한 번만 호출된다 — 괜찮은가?

`InitSimulatedTask`는 태스크가 처음 도착할 때 한 번만 호출된다.
하지만 태스크 객체의 `UPROPERTY(Replicated)` 필드는 `AddReplicatedSubObject`로 등록된 서브오브젝트로서 **서버에서 값이 바뀔 때마다 계속 복제**된다.

**파라미터가 태스크 시작 시 한 번 확정되는 경우** — 문제없다.
`AbilityTask_ApplyRootMotionConstantForce`가 이 케이스다. `WorldDirection`, `Strength`, `Duration`은 팩토리 함수에서 세팅 후 변경되지 않는다.

**파라미터가 실행 중 변하는 경우** — `InitSimulatedTask` 한 번으로는 부족하다.
변경되는 프로퍼티에 `ReplicatedUsing=OnRep_XXX`를 달아 값이 바뀔 때마다 simulated proxy 쪽에서 반응하게 만들어야 한다.

```cpp
UPROPERTY(ReplicatedUsing=OnRep_Strength)
float Strength;

void OnRep_Strength() { /* 새 Strength로 RootMotionSource 업데이트 */ }
```

**타이밍 문제는 없나?** — 없다.
언리얼의 복제 순서상 서브오브젝트 프로퍼티가 먼저 처리되고 이후 배열 OnRep이 발동한다.
`InitSimulatedTask`가 호출될 때 `UPROPERTY(Replicated)` 필드는 이미 세팅된 상태다.

### bSimulatedTask vs bIsSimulating

```cpp
// GameplayTask.h:344~348
uint32 bSimulatedTask : 1;   // 설계 시 설정 — "simulated proxy에 복제할 것인가"
uint32 bIsSimulating  : 1;   // 런타임 상태 — "나는 지금 simulated proxy에서 실행 중인가"
```

`bIsSimulating`은 `InitSimulatedTask()` 내부(`Super::InitSimulatedTask()`)에서만 `true`로 세팅된다.
태스크 로직에서 `if (!bIsSimulating)` 분기로 서버/owning client 전용 코드를 가드할 수 있다.

### bTickingTask 없이는 InitSimulatedTask가 호출되지 않는다

`OnRep_SimulatedTasks`의 조건이 `IsTickingTask()`이기 때문이다.
`bSimulatedTask = true`만 설정하면 태스크 객체는 복제되지만 `InitSimulatedTask()`는 호출되지 않는다.
두 플래그를 함께 설정해야 시뮬레이션이 시작된다.

### 개발자 체크리스트

```cpp
class UMySimulatedTask : public UAbilityTask
{
    UMySimulatedTask(const FObjectInitializer& OI) : Super(OI)
    {
        bSimulatedTask = true;  // ① simulated proxy 복제 활성
        bTickingTask   = true;  // ② InitSimulatedTask 호출 조건 충족
    }

    UPROPERTY(Replicated) FVector Direction;  // ③ 전달할 파라미터
    UPROPERTY(Replicated) float   Duration;

    void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override
    {
        Super::GetLifetimeReplicatedProps(OutLifetimeProps);
        DOREPLIFETIME(UMySimulatedTask, Direction);   // ④ 복제 등록
        DOREPLIFETIME(UMySimulatedTask, Duration);
    }

    void InitSimulatedTask(UGameplayTasksComponent& InTasksComponent) override
    {
        Super::InitSimulatedTask(InTasksComponent);  // ⑤ bIsSimulating = true
        // 복제된 파라미터로 시뮬레이션 시작
    }
};
```

---

## 엔진 예시: AbilityTask_ApplyRootMotionConstantForce

RootMotion AbilityTask는 `bSimulatedTask` 패턴의 교과서적 구현이다.

### 왜 simulated proxy에도 RootMotion이 필요한가

RootMotion은 `CharacterMovementComponent::ApplyRootMotionSource()`로 물리를 직접 구동한다.
서버에서만 적용하면 simulated proxy는 복제된 위치·속도만 받아 움직임이 끊겨 보인다.
Simulated proxy에서도 동일한 `FRootMotionSource`를 적용해야 부드러운 시각적 일관성이 유지된다.

### 구조

```cpp
// AbilityTask_ApplyRootMotion_Base.cpp:14
UAbilityTask_ApplyRootMotion_Base::UAbilityTask_ApplyRootMotion_Base(...)
{
    bTickingTask   = true;   // 매 틱 타임아웃 체크 + OnRep_SimulatedTasks 조건 충족
    bSimulatedTask = true;   // simulated proxy 복제 활성
}

// 베이스 복제 파라미터
UPROPERTY(Replicated) FName ForceName;
UPROPERTY(Replicated) ERootMotionFinishVelocityMode FinishVelocityMode;
UPROPERTY(Replicated) FVector FinishSetVelocity;
UPROPERTY(Replicated) float  FinishClampVelocity;

// simulated proxy 측 초기화 — SharedInitAndApply()로 RootMotionSource 생성·적용
void UAbilityTask_ApplyRootMotion_Base::InitSimulatedTask(UGameplayTasksComponent& InTasksComponent)
{
    Super::InitSimulatedTask(InTasksComponent);
    SharedInitAndApply();
}
```

```cpp
// AbilityTask_ApplyRootMotionConstantForce 추가 파라미터
UPROPERTY(Replicated) FVector WorldDirection;
UPROPERTY(Replicated) float   Strength;
UPROPERTY(Replicated) float   Duration;
UPROPERTY(Replicated) bool    bIsAdditive;
UPROPERTY(Replicated) bool    bEnableGravity;
UPROPERTY(Replicated) UCurveFloat* StrengthOverTime;
```

```cpp
// SharedInitAndApply() — 서버·owning client(Activate 시)와 simulated proxy(InitSimulatedTask 시) 모두 호출
void UAbilityTask_ApplyRootMotionConstantForce::SharedInitAndApply()
{
    MovementComponent = Cast<UCharacterMovementComponent>(...);
    StartTime = GetWorld()->GetTimeSeconds();
    EndTime   = StartTime + Duration;

    TSharedPtr<FRootMotionSource_ConstantForce> ConstantForce = MakeShared<FRootMotionSource_ConstantForce>();
    ConstantForce->Force    = WorldDirection * Strength;
    ConstantForce->Duration = Duration;
    RootMotionSourceID = MovementComponent->ApplyRootMotionSource(ConstantForce);
}
```

```cpp
// TickTask() — bIsSimulating 분기로 서버/owning client 전용 처리 가드
void UAbilityTask_ApplyRootMotionConstantForce::TickTask(float DeltaTime)
{
    if (HasTimedOut())
    {
        bIsFinished = true;
        if (!bIsSimulating)   // simulated proxy는 EndTask/델리게이트 브로드캐스트 하지 않음
        {
            MyActor->ForceNetUpdate();
            OnFinish.Broadcast();
            EndTask();
        }
    }
}

// simulated proxy 측 종료 — 서버가 SimulatedTasks[]에서 제거 → 복제 → 이 함수 호출
void UAbilityTask_ApplyRootMotionConstantForce::PreDestroyFromReplication()
{
    bIsFinished = true;
    EndTask();
}
```

---

## Lyra 예시: AbilityTask_GrantNearbyInteraction

Lyra의 AbilityTask는 대부분 서버 전용으로 동작하며 `bSimulatedTask`를 사용하지 않는다.
Simulated proxy에 효과를 전달할 필요가 있을 때는 **GameplayCue** 또는 **복제된 컴포넌트 속성**으로 처리한다.

```cpp
void UAbilityTask_GrantNearbyInteraction::Activate()
{
    SetWaitingOnAvatar();
    // 타이머로 주기적 Overlap 쿼리 → 범위 안 오브젝트에 Ability 부여
    World->GetTimerManager().SetTimer(QueryTimerHandle, this,
        &ThisClass::QueryInteractables, InteractionScanRate, true);
}

void UAbilityTask_GrantNearbyInteraction::OnDestroy(bool AbilityEnded)
{
    World->GetTimerManager().ClearTimer(QueryTimerHandle);
    Super::OnDestroy(AbilityEnded);   // Super 마지막 호출
}
```

이 태스크가 `bSimulatedTask` 없이도 동작하는 이유:
- Ability 부여·해제는 서버 권한 작업 — 서버에서만 처리하면 충분하다.
- 인터랙션 UI는 owning client 쪽에서 `InteractableObjectsChanged` 델리게이트로 별도 처리한다.
- Simulated proxy(다른 플레이어)는 이 캐릭터의 인터랙션 상태를 알 필요가 없다.

---

## NetworkSyncPoint 패턴

`AbilityTask_NetworkSyncPoint`는 파라미터 복제가 아닌 **RPC 신호**로 서버-클라 실행 타이밍을 동기화한다.
GAS의 `GenericReplicatedEvent`(서버↔클라 양방향 RPC)를 내부적으로 사용한다.

```
BothWait:       서버·클라 모두 상대방 신호를 기다린 후 동시에 진행
OnlyServerWait: 서버만 대기, 클라는 신호 보내고 즉시 진행
OnlyClientWait: 클라만 대기, 서버는 신호 보내고 즉시 진행
```

---

## 패턴 정리

| 상황 | 방법 | 예시 |
|---|---|---|
| Simulated proxy에 물리/이동 효과 필요 | `bSimulatedTask` + 파라미터 복제 + `InitSimulatedTask()` | `AbilityTask_ApplyRootMotion_*` |
| 서버-클라 실행 타이밍 동기화 | `AbilityTask_NetworkSyncPoint` | `WaitNetSync` BP 노드 |
| 서버 전용 권한 작업 | `bSimulatedTask` 없이 서버 실행 | Lyra `AbilityTask_GrantNearbyInteraction` |
| 전체 클라이언트에 시각 효과 전파 | GameplayCue | `UGameplayCueManager::ExecuteGameplayCue` |
