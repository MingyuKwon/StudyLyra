# GameplayTask

> 소스: `Engine/Plugins/GameplayTasks/Source/GameplayTasks/`

GAS와 무관한 **범용 비동기 태스크 시스템**이다.
`UGameplayTasksComponent`를 가진 어떤 Actor에서든 사용할 수 있으며, `UAbilityTask`의 베이스 클래스이기도 하다.

---

## 왜 존재하는가

"특정 조건까지 기다리거나, 시간에 걸쳐 작업을 수행하는" 비동기 태스크 패턴은 GAS만의 문제가 아니다.
AI 에이전트, 인터랙션 시스템, 퀘스트 시스템 등 게임의 여러 곳에서 동일한 패턴이 필요하다.

언리얼은 이 패턴을 **`GameplayTasks` 플러그인**으로 분리했다.
GAS(`GameplayAbilities` 플러그인)는 그 위에 GAS 전용 레이어(`UAbilityTask`)만 얹는 구조다.

```
GameplayTasks 플러그인      비동기 태스크를 어떻게 실행·관리하는가  (범용)
      ↑
GameplayAbilities 플러그인  GAS 어빌리티에서 비동기 태스크를 어떻게 쓰는가  (특화)
```

이 분리 덕분에 두 가지 이점이 생긴다.

**① GAS 없는 시스템도 동일한 패턴 사용**
BehaviorTree의 `UBTTaskNode_GameplayTaskBase`가 대표적이다.
AI 에이전트가 "목표 지점까지 이동 완료를 기다린다"는 비동기 태스크를 GAS 없이도 `UGameplayTask` 위에서 표현할 수 있다.

**② GAS는 핵심 문제에만 집중**
`UAbilityTask`는 "GA 수명 연동, ASC 접근, 예측 시스템 연동"이라는 GAS 고유 문제만 추가하면 된다.
비동기 실행 인프라는 `UGameplayTask`에 위임한다.

---

## 클래스 구조

```
UObject
  └─ UGameplayTask                  (GameplayTasks 플러그인)
        └─ UAbilityTask             (GameplayAbilities 플러그인 — GAS 전용)
```

`UGameplayTasksComponent`가 태스크를 소유하고 실행·종료를 관리한다.
`UAbilitySystemComponent`는 `UGameplayTasksComponent`를 상속하므로, ASC는 곧 태스크 컴포넌트이기도 하다.

```
UActorComponent
  └─ UGameplayTasksComponent        (태스크 소유·관리)
        └─ UAbilitySystemComponent  (GAS 핵심 컴포넌트)
```

---

## 태스크 상태 머신

태스크는 항상 아래 상태 중 하나다. (`EGameplayTaskState`, `GameplayTask.h:24`)

```
Uninitialized → AwaitingActivation → Active ↔ Paused → Finished
                     (InitTask)      (Activate)           (OnDestroy)
```

---

## 핵심 API 상세

### ReadyForActivation()
> `GameplayTask.cpp:56`

외부에서 태스크를 "시작시켜달라"고 요청하는 공개 진입점이다.
C++에서는 태스크 생성 후 반드시 수동으로 호출해야 한다.
Blueprint에서는 `K2Node_LatentGameplayTaskCall`이 자동으로 호출한다.

```cpp
void UGameplayTask::ReadyForActivation()
{
    if (UGameplayTasksComponent* TasksPtr = TasksComponent.Get())
    {
        if (RequiresPriorityOrResourceManagement() == false)
        {
            PerformActivation();               // 우선순위/리소스 관리 불필요 → 즉시 실행
        }
        else
        {
            TasksPtr->AddTaskReadyForActivation(*this); // 큐에 등록 → TasksComponent가 때를 결정
        }
    }
    else
    {
        EndTask(); // TasksComponent 없으면 즉시 종료
    }
}
```

`RequiredResources`나 `Priority` 관리가 필요한 태스크는 `TasksComponent`가 순서를 결정한다.
그렇지 않으면 곧바로 `PerformActivation()`으로 넘어간다.

---

### Activate()
> `GameplayTask.cpp:298`, `GameplayTask.h:162`

`PerformActivation()` 내부에서 호출되는 가상 함수다.
개발자가 오버라이드해서 실제 태스크 로직을 구현하는 곳이다.

```cpp
// 베이스 구현 — VLOG 출력만 하고 아무것도 하지 않는다
void UGameplayTask::Activate()
{
    UE_VLOG(...);
}
```

```cpp
// PerformActivation() 내부 흐름 (GameplayTask.cpp:275)
void UGameplayTask::PerformActivation()
{
    TaskState = EGameplayTaskState::Active;  // 상태 먼저 Active로
    Activate();                              // 개발자 로직 실행

    // Activate() 안에서 즉시 EndTask()가 불렸을 수 있음
    // 그 경우 TasksComponent에 알릴 필요 없음
    if (IsFinished() == false)
    {
        TasksComponent->OnGameplayTaskActivated(*this);
    }
}
```

`Activate()`는 `PerformActivation()`에서 `TaskState`가 `Active`로 바뀐 **뒤에** 호출된다.
`Activate()` 안에서 바로 `EndTask()`를 호출하는 동기 완료 패턴도 유효하다.

---

### EndTask()
> `GameplayTask.cpp:165`

태스크가 **스스로** 종료할 때 호출한다.

```cpp
void UGameplayTask::EndTask()
{
    if (TaskState != EGameplayTaskState::Finished)  // 이미 끝난 태스크 중복 호출 방지
    {
        if (IsValidChecked(this))
        {
            OnDestroy(false);  // false = "소유자가 끝난 게 아니라 태스크 자신이 끝냄"
        }
        else
        {
            TaskState = EGameplayTaskState::Finished; // 안전장치
        }
    }
}
```

`TaskOwnerEnded()`는 GA 같은 소유자가 끝날 때 태스크를 정리하는 경로다.
이 경우 `OnDestroy(true)`를 호출한다. `bOwnerFinished` 파라미터로 두 경로를 구분할 수 있다.

---

### OnDestroy(bool bOwnerFinished)
> `GameplayTask.cpp:206`

`EndTask()`와 `TaskOwnerEnded()` 양쪽에서 수렴하는 **실제 종료 처리 함수**다.
개발자가 오버라이드해서 정리 로직(델리게이트 언바인딩 등)을 구현한다.

```cpp
void UGameplayTask::OnDestroy(bool bInOwnerFinished)
{
    TaskState = EGameplayTaskState::Finished;

    // TasksComponent에 "이 태스크 비활성화됨" 통보
    if (UGameplayTasksComponent* TasksPtr = TasksComponent.Get())
    {
        TasksPtr->OnGameplayTaskDeactivated(*this);
    }

    MarkAsGarbage(); // GC 대상으로 표시
}
```

> **주의**  
> 오버라이드 시 `Super::OnDestroy()`를 **마지막**에 호출해야 한다.  
> `MarkAsGarbage()`가 내부 BP 메커니즘을 방해할 수 있기 때문이다. (`GameplayTask.h:294` 주석)

---

### TickTask(float DeltaTime)
> `GameplayTask.h:171`

매 틱 실행이 필요한 태스크를 위한 훅이다.
기본 구현은 빈 함수(`{}`)이며, 아래 두 가지를 생성자에서 설정해야 활성화된다.

```cpp
// 생성자에서
bTickingTask = true;   // TasksComponent가 매 틱 TickTask() 호출하도록 등록
```

`bTickingTask`는 `uint32` 비트 필드(`GameplayTask.h:342`)로, 생성자에서 기본값 `false`다.

---

### 두 플래그: bSimulatedTask vs bIsSimulating
> `GameplayTask.h:344~348`

이름이 비슷하지만 역할이 다르다.

```cpp
// 설정값 — "이 태스크를 simulated proxy에 복제할 것인가"
uint32 bSimulatedTask : 1;

// 런타임 상태 — "나는 지금 simulated proxy에서 실행 중인가"
uint32 bIsSimulating : 1;
```

`bSimulatedTask = true`이면 `IsSupportedForNetworking()`이 `true`를 반환해 복제가 허용된다.
`bIsSimulating`은 `InitSimulatedTask()` 내부에서 `true`로 세팅된다.

```cpp
// GameplayTask.cpp:100
void UGameplayTask::InitSimulatedTask(UGameplayTasksComponent& InGameplayTasksComponent)
{
    TasksComponent = &InGameplayTasksComponent;
    bIsSimulating = true; // "나는 simulated proxy에서 돌고 있다"
}
```

---

## Simulated Proxy 복제 — bSimulatedTask

기본적으로 태스크는 자신이 생성된 곳(서버 또는 소유 클라이언트)에서만 실행된다.
`bSimulatedTask = true`로 설정하면 simulated proxy에도 태스크가 복제된다.

### 왜 simulated proxy만인가

| 주체 | 태스크 실행 여부 | 이유 |
|---|---|---|
| Server | 직접 실행 (`Activate()`) | GA가 서버에서 실행됨 |
| Owning Client | 직접 실행 (`Activate()`) | NetExecutionPolicy에 따라 GA가 owning client에서도 실행됨 |
| Simulated Proxy | 실행 안 됨 | GA 자체가 simulated proxy에서 실행되지 않음 |

서버와 owning client는 이미 `Activate()`를 통해 태스크를 직접 돌리고 있다.
`bSimulatedTask`는 GA가 아예 실행되지 않는 simulated proxy에게만 필요한 메커니즘이다.

### bSimulatedTask 복제 흐름

```
[Server]
태스크 생성 + bSimulatedTask = true
  → UGameplayTasksComponent::SimulatedTasks[] 에 추가
      → 배열 복제 → Simulated Proxy 전송
          → OnRep_SimulatedTasks()
              → Task->InitSimulatedTask(*TasksComponent)
```

### 개발자가 챙겨야 하는 것

```cpp
class UMyTask : public UGameplayTask
{
    UMyTask(const FObjectInitializer& OI) : Super(OI)
    {
        bSimulatedTask = true;   // 복제 신호
    }

    // simulated proxy에 전달할 파라미터
    UPROPERTY(Replicated)
    float Duration;

    UPROPERTY(Replicated)
    FVector Direction;

    void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

    // 엔진이 simulated proxy에서 호출해줌 — 개발자가 구현
    void InitSimulatedTask(UGameplayTasksComponent& InTasksComponent) override
    {
        Super::InitSimulatedTask(InTasksComponent);
        // 복제된 Duration, Direction으로 시뮬레이션 시작
    }
};
```

엔진이 자동으로 해주는 것: `SimulatedTasks` 배열 복제, 인스턴스 생성, `InitSimulatedTask()` 호출.
개발자가 챙겨야 하는 것: `bSimulatedTask = true`, `UPROPERTY(Replicated)` 파라미터 선언, `InitSimulatedTask()` 구현.

---

## GAS 밖에서의 사용

`UGameplayTask`는 GAS 없이도 사용할 수 있다.
언리얼 AI 시스템의 `UBTTaskNode_GameplayTaskBase`가 대표적인 예로, BehaviorTree Task가 내부적으로 GameplayTask를 활용한다.

GAS를 쓰는 프로젝트에서는 거의 항상 `UAbilityTask`를 사용하게 된다.
`UGameplayTask`를 직접 사용하는 경우는 GAS 없이 순수 `UGameplayTasksComponent` 위에서 태스크를 돌릴 때다.
