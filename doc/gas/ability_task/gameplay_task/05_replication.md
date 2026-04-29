# GameplayTask 복제

> 소스: `Engine/Source/Runtime/GameplayTasks/`, `Engine/Plugins/Runtime/GameplayAbilities/`

---

## 기본 원칙: 각 머신이 코드를 직접 실행한다

태스크 코드는 복제되지 않는다. 네트워크를 통해 "이 태스크를 실행해"라는 명령이 오는 것이 아니라, **각 머신이 자기 로컬에서 태스크를 직접 생성하고 실행**한다.

```
서버         GA 활성화 → NewAbilityTask<T>() → Activate() — 권위 있는 실행
Owning Client  GA 활성화 → NewAbilityTask<T>() → Activate() — 예측 실행 (LocalPredicted)
Simulated Proxy  GA가 실행되지 않음 → 기본적으로 태스크도 없음
```

Simulated proxy에 GA가 실행되지 않는 이유는 **권위(authority)** 때문이다.
Simulated proxy는 "남의 캐릭터"를 보고 있는 머신이다. 게임 스테이트를 직접 변경할 권한이 없고, PlayerController도 없다.
모든 판단은 서버가 하고, simulated proxy는 그 결과를 받아서 보여줄 뿐이다.

---

## "Simulated proxy에서도 태스크를 돌리고 싶다면?"

가능하다. 그것이 `bSimulatedTask`다. 단, 역할이 다르다.

| 주체 | 실행 종류 | 게임 스테이트 변경 가능 여부 |
|---|---|---|
| Server | 권위 있는 실행 (`Activate()`) | 가능 |
| Owning Client | 예측 실행 (`Activate()`) | 가능 (서버와 조율) |
| Simulated Proxy | **로컬 시뮬레이션** (`InitSimulatedTask()`) | 불가 — 비주얼 전용 |

Simulated proxy가 받는 것은 "태스크를 실행하라"는 명령이 아니라 **파라미터 데이터**다.
그 파라미터로 "서버와 같아 보이는 효과"를 자기 로컬에서 재현한다.

예: 넉백 태스크
- 서버: `WorldDirection=FVector(1,0,0), Duration=0.5` 로 RootMotionSource 적용 → 위치 권위 있게 변경
- Owning Client: 동일한 파라미터로 Activate() → 본인 화면에서 즉시 반응
- Simulated Proxy: 복제된 `WorldDirection`, `Duration`을 받아 `InitSimulatedTask()` → 로컬에서 동일한 RootMotionSource 적용 → 다른 플레이어 화면에서 끊기지 않고 보임

서버가 종료를 결정하면 `SimulatedTasks[]`에서 제거되어 복제되고, simulated proxy 쪽은 `PreDestroyFromReplication()`으로 정리된다. Simulated proxy가 `EndTask()`를 직접 호출하지 않는 이유도 이것이다 — 종료 권한도 서버에 있다.

---

## 복제가 필요한 두 가지 상황

### 상황 A — simulated proxy에도 태스크 효과가 필요할 때

`bSimulatedTask = true` 패턴. 파라미터를 복제해서 simulated proxy가 로컬 시뮬레이션을 돌린다.

### 상황 B — 서버와 클라이언트의 실행 타이밍을 맞춰야 할 때

`AbilityTask_NetworkSyncPoint` 패턴. 파라미터 복제가 아니라 RPC 신호로 양쪽 실행 흐름을 동기화한다.

---

## bSimulatedTask 패턴

### 개념

`bSimulatedTask = true`로 설정하면 `GameplayTasksComponent::SimulatedTasks[]` 배열에 등록되어 simulated proxy로 복제된다.

```
[Server]
태스크 생성 + bSimulatedTask = true
  → SimulatedTasks[] 추가
      → COND_SkipOwner 조건으로 복제 (owning client 제외)
          → Simulated Proxy의 OnRep_SimulatedTasks()
              → Task->InitSimulatedTask(*TasksComponent)
                  → bIsSimulating = true
                  → SharedInitAndApply() 등 시뮬레이션 시작
```

`COND_SkipOwner`: owning client는 이미 직접 태스크를 실행하고 있으므로 복제 불필요.

---

### InitSimulatedTask 호출 시점 — 코드 추적

#### 서버 측 (태스크 활성화 시점)

태스크가 `PerformActivation()`을 통해 Active 상태가 되면 `OnGameplayTaskActivated()`가 호출된다.

```cpp
// GameplayTasksComponent.cpp:80
void UGameplayTasksComponent::OnGameplayTaskActivated(UGameplayTask& Task)
{
    KnownTasks.Add(&Task);

    if (Task.IsTickingTask())
    {
        TickingTasks.Add(&Task);
    }

    if (Task.IsSimulatedTask())          // bSimulatedTask == true 인 경우
    {
        AddSimulatedTask(&Task);         // ← 여기서 SimulatedTasks 배열에 등록
    }
}
```

```cpp
// GameplayTasksComponent.cpp:786
bool UGameplayTasksComponent::AddSimulatedTask(UGameplayTask* NewTask)
{
    SimulatedTasks.Add(NewTask);
    SetSimulatedTasksNetDirty();         // ← MARK_PROPERTY_DIRTY: 다음 net update에서 복제 예약
    AddReplicatedSubObject(NewTask, COND_SkipOwner);  // 태스크 객체 자체도 서브오브젝트로 등록
    return true;
}
```

`SetSimulatedTasksNetDirty()`는 Push Model 복제 마킹이다. 실제 전송은 다음 net update 틱에서 일어난다.

#### 클라이언트 측 (복제 수신 시점)

`SimulatedTasks` 배열이 simulated proxy에 도착하면 `OnRep_SimulatedTasks()`가 자동 호출된다.

```cpp
// GameplayTasksComponent.cpp:205
void UGameplayTasksComponent::OnRep_SimulatedTasks()
{
    for (UGameplayTask* SimulatedTask : GetSimulatedTasks())
    {
        if (SimulatedTask)
        {
            // 핵심 조건: bTickingTask == true 인 태스크만 InitSimulatedTask 호출
            if (SimulatedTask->IsTickingTask() && TickingTasks.Contains(SimulatedTask) == false)
            {
                SimulatedTask->InitSimulatedTask(*this);  // ← 실제 호출 지점

                TickingTasks.Add(SimulatedTask);
                UpdateShouldTick();
            }
        }
    }

    // 다음 OnRep에서 추가/제거 감지용 스냅샷 갱신
    PreviousOnRepSimulatedTasks.Empty();
    PreviousOnRepSimulatedTasks.Append(SimulatedTasks);
}
```

#### 중요: bTickingTask가 없으면 InitSimulatedTask가 호출되지 않는다

`OnRep_SimulatedTasks`의 조건은 `IsTickingTask()`다.
`bSimulatedTask = true`만 설정하고 `bTickingTask = false`이면 태스크 객체는 복제되지만 `InitSimulatedTask()`는 호출되지 않는다.

`UAbilityTask_ApplyRootMotion_Base`가 두 플래그를 모두 켜는 이유가 이것이다.

```cpp
// AbilityTask_ApplyRootMotion_Base.cpp:14
UAbilityTask_ApplyRootMotion_Base::UAbilityTask_ApplyRootMotion_Base(...)
{
    bTickingTask   = true;   // ← OnRep_SimulatedTasks의 IsTickingTask() 조건을 충족
    bSimulatedTask = true;   // ← SimulatedTasks 배열 등록
}
```

#### 전체 호출 체인 요약

```
[Server] PerformActivation()
  → OnGameplayTaskActivated()
      → AddSimulatedTask()
          → SimulatedTasks.Add(task)
          → SetSimulatedTasksNetDirty()   ← 복제 예약

[Net Update Tick] SimulatedTasks 배열 → simulated proxy 전송

[Simulated Proxy] OnRep_SimulatedTasks()
  → IsTickingTask() && not in TickingTasks?
      → YES: InitSimulatedTask(*this)    ← bIsSimulating = true + 시뮬레이션 시작
             TickingTasks.Add(task)
      → NO:  태스크 객체만 복제, InitSimulatedTask 호출 없음
```

### 두 플래그 구분

```cpp
// GameplayTask.h:344~348

uint32 bSimulatedTask : 1;   // 설계 시 설정 — "simulated proxy에 복제할 것인가"
uint32 bIsSimulating : 1;    // 런타임 상태 — "나는 지금 simulated proxy에서 실행 중인가"
```

`bIsSimulating`은 `InitSimulatedTask()` 내부에서만 `true`로 세팅된다.
태스크 로직 안에서 `if (!bIsSimulating)` 분기로 서버/owning client 전용 코드를 가드할 수 있다.

### 개발자 체크리스트

```cpp
class UMySimulatedTask : public UAbilityTask
{
    UMySimulatedTask(const FObjectInitializer& OI) : Super(OI)
    {
        bSimulatedTask = true;   // ① 복제 플래그
        bTickingTask   = true;   // (필요 시)
    }

    // ② simulated proxy에 전달할 파라미터 — UPROPERTY(Replicated) 필수
    UPROPERTY(Replicated)
    FVector Direction;

    UPROPERTY(Replicated)
    float Duration;

    // ③ GetLifetimeReplicatedProps 등록
    void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override
    {
        Super::GetLifetimeReplicatedProps(OutLifetimeProps);
        DOREPLIFETIME(UMySimulatedTask, Direction);
        DOREPLIFETIME(UMySimulatedTask, Duration);
    }

    // ④ simulated proxy 측 초기화 — 엔진이 자동 호출
    void InitSimulatedTask(UGameplayTasksComponent& InTasksComponent) override
    {
        Super::InitSimulatedTask(InTasksComponent);  // bIsSimulating = true 세팅
        // 복제된 Direction, Duration으로 시뮬레이션 시작
    }
};
```

엔진이 자동으로 처리: `SimulatedTasks` 배열 복제, 인스턴스 생성, `InitSimulatedTask()` 호출.

---

## 엔진 예시: AbilityTask_ApplyRootMotion_Base

RootMotion AbilityTask는 `bSimulatedTask` 패턴의 교과서적 구현이다.

### 왜 simulated proxy에도 RootMotion이 필요한가

RootMotion은 CharacterMovementComponent의 `ApplyRootMotionSource()`를 통해 물리를 직접 구동한다.
서버에서만 적용하면 simulated proxy는 복제된 위치·속도만 받게 되어 움직임이 끊겨 보인다.
Simulated proxy에서도 동일한 `FRootMotionSource`를 적용해야 부드러운 시각적 일관성이 유지된다.

### AbilityTask_ApplyRootMotion_Base 구조

```cpp
// AbilityTask_ApplyRootMotion_Base.cpp:14
UAbilityTask_ApplyRootMotion_Base::UAbilityTask_ApplyRootMotion_Base(...)
{
    bTickingTask   = true;   // 매 틱 타임아웃 체크
    bSimulatedTask = true;   // simulated proxy 복제 활성
}

// 복제 파라미터 — simulated proxy에서 RootMotionSource를 재현하는 데 필요한 값들
UPROPERTY(Replicated) FName ForceName;
UPROPERTY(Replicated) ERootMotionFinishVelocityMode FinishVelocityMode;
UPROPERTY(Replicated) FVector FinishSetVelocity;
UPROPERTY(Replicated) float  FinishClampVelocity;

// simulated proxy 측 초기화
void UAbilityTask_ApplyRootMotion_Base::InitSimulatedTask(UGameplayTasksComponent& InTasksComponent)
{
    Super::InitSimulatedTask(InTasksComponent);
    SharedInitAndApply();  // 복제된 파라미터로 RootMotionSource 생성·적용
}
```

### AbilityTask_ApplyRootMotionConstantForce 상세

`AbilityTask_ApplyRootMotion_Base`를 상속한 구체 태스크. 방향과 세기로 캐릭터를 밀어낸다.

```cpp
// AbilityTask_ApplyRootMotionConstantForce.h
UPROPERTY(Replicated) FVector WorldDirection;  // 밀어내는 방향
UPROPERTY(Replicated) float   Strength;        // 세기
UPROPERTY(Replicated) float   Duration;        // 지속 시간
UPROPERTY(Replicated) bool    bIsAdditive;
UPROPERTY(Replicated) bool    bEnableGravity;
UPROPERTY(Replicated) UCurveFloat* StrengthOverTime;
```

```cpp
// SharedInitAndApply() — 서버/owning client에서 Activate() 때, simulated proxy에서 InitSimulatedTask() 때 모두 호출
void UAbilityTask_ApplyRootMotionConstantForce::SharedInitAndApply()
{
    MovementComponent = Cast<UCharacterMovementComponent>(...);
    StartTime = GetWorld()->GetTimeSeconds();
    EndTime   = StartTime + Duration;

    // 복제된 파라미터로 FRootMotionSource 생성 → CharacterMovementComponent에 등록
    TSharedPtr<FRootMotionSource_ConstantForce> ConstantForce = MakeShared<FRootMotionSource_ConstantForce>();
    ConstantForce->Force    = WorldDirection * Strength;
    ConstantForce->Duration = Duration;
    // ...
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
        if (!bIsSimulating)  // simulated proxy에서는 EndTask/델리게이트 브로드캐스트 하지 않음
        {
            MyActor->ForceNetUpdate();
            OnFinish.Broadcast();
            EndTask();
        }
    }
}
```

**핵심**: simulated proxy는 `EndTask()`를 직접 호출하지 않는다.
서버가 태스크를 종료하면 `SimulatedTasks` 배열에서 제거되어 복제되고, `PreDestroyFromReplication()`이 호출된다.

```cpp
void UAbilityTask_ApplyRootMotionConstantForce::PreDestroyFromReplication()
{
    bIsFinished = true;
    EndTask();  // simulated proxy 측 정리
}
```

---

## Lyra 예시: AbilityTask_GrantNearbyInteraction

Lyra의 AbilityTask는 대부분 **서버 전용** 또는 **owning client 전용**으로 동작하며 `bSimulatedTask`를 사용하지 않는다.
Simulated proxy에 태스크 효과를 전달해야 할 경우 **GameplayCue** 또는 **복제된 컴포넌트 속성**으로 처리한다.

```cpp
// AbilityTask_GrantNearbyInteraction.h
class UAbilityTask_GrantNearbyInteraction : public UAbilityTask
{
    // bSimulatedTask 없음 → 서버에서만 실행
    // bTickingTask 없음 → 타이머로 주기 실행

    virtual void Activate() override;
    virtual void OnDestroy(bool AbilityEnded) override;

    float InteractionScanRange;
    float InteractionScanRate;
    FTimerHandle QueryTimerHandle;

    TMap<FObjectKey, FGameplayAbilitySpecHandle> InteractionAbilityCache;
};
```

```cpp
// AbilityTask_GrantNearbyInteraction.cpp:31
void UAbilityTask_GrantNearbyInteraction::Activate()
{
    SetWaitingOnAvatar();  // AvatarActor가 준비될 때까지 대기

    // 타이머로 주기적 Overlap 쿼리 → 범위 안 오브젝트에 Ability 부여
    World->GetTimerManager().SetTimer(QueryTimerHandle, this,
        &ThisClass::QueryInteractables, InteractionScanRate, true);
}

void UAbilityTask_GrantNearbyInteraction::OnDestroy(bool AbilityEnded)
{
    World->GetTimerManager().ClearTimer(QueryTimerHandle);  // 타이머 정리
    Super::OnDestroy(AbilityEnded);  // Super 마지막 호출
}
```

이 태스크가 simulated proxy 복제 없이도 동작하는 이유:
- 인터랙션 로직(Ability 부여·해제)은 **서버 권한** 작업이므로 서버에서만 처리하면 충분하다.
- 인터랙션 UI 힌트는 `InteractableObjectsChanged` 델리게이트를 통해 owning client 쪽에서 별도 처리한다.
- Simulated proxy(다른 플레이어)는 인터랙션 상태를 알 필요가 없다.

---

## NetworkSyncPoint 패턴

`AbilityTask_NetworkSyncPoint`는 복제 데이터가 아닌 **RPC 신호**로 서버-클라 실행 타이밍을 동기화한다.

```
BothWait:      서버 ──┐             클라 ──┐
                      ├─ 서로 신호 대기 ──┘
                      └── 동시에 계속 진행

OnlyServerWait: 서버만 대기, 클라는 신호 보내고 즉시 진행
OnlyClientWait: 클라만 대기, 서버는 신호 보내고 즉시 진행
```

태스크 데이터를 복제하는 것이 아니라 "여기까지 왔다"는 신호를 주고받는 개념이다.
GAS의 `GenericReplicatedEvent`(서버↔클라 양방향 RPC)를 내부적으로 사용한다.

---

## 패턴 정리

| 상황 | 방법 | 예시 |
|---|---|---|
| Simulated proxy에 물리/이동 효과 필요 | `bSimulatedTask = true` + 파라미터 복제 + `InitSimulatedTask()` | `AbilityTask_ApplyRootMotion_*` |
| 서버-클라 실행 타이밍 동기화 | `AbilityTask_NetworkSyncPoint` | `WaitNetSync` BP 노드 |
| 서버 전용 로직 (권한 작업) | `bSimulatedTask` 없이 서버 실행 | Lyra `AbilityTask_GrantNearbyInteraction` |
| 시각적 효과 전파 | GameplayCue (복제된 큐 태그) | `UGameplayCueManager::ExecuteGameplayCue` |
