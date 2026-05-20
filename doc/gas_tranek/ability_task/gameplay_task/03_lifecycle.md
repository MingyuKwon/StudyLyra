# GameplayTask 생명주기

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTask.h`, `Private/GameplayTask.cpp`

---

## GameplayTask의 생성부터 소멸까지 전체 흐름은 어떻게 되는가?

```
NewTask<T>(TaskOwner)
    └─ NewObject<T>()
    └─ InitTask(TaskOwner, Priority)
           ├─ TaskState = AwaitingActivation
           └─ TaskOwner.OnGameplayTaskInitialized(*this)

ReadyForActivation()
    ├─ [리소스/우선순위 불필요] → PerformActivation()
    └─ [리소스/우선순위 필요]  → TasksComponent->AddTaskReadyForActivation()
                                    └─ TaskPriorityQueue에 삽입
                                    └─ UpdateTaskActivations() → PerformActivation() (조건 충족 시)

PerformActivation()
    ├─ TaskState = Active
    ├─ Activate()              ← 개발자 구현 진입점
    └─ TasksComponent->OnGameplayTaskActivated(*this)
           ├─ KnownTasks에 추가
           ├─ bTickingTask → TickingTasks에 추가
           └─ bSimulatedTask → SimulatedTasks에 추가 + 복제

[실행 중]
    ├─ TickTask(DeltaTime)     ← bTickingTask = true일 때 매 틱 호출
    ├─ PauseTask() / ResumeTask()
    └─ 비동기 델리게이트 대기

EndTask()                      ← 태스크 스스로 종료
    └─ OnDestroy(false)

TaskOwnerEnded()               ← 소유자(GA 등)가 종료되며 태스크 정리
    └─ OnDestroy(true)

OnDestroy(bOwnerFinished)
    ├─ TaskState = Finished
    ├─ TasksComponent->OnGameplayTaskDeactivated(*this)
    │      ├─ KnownTasks에서 제거
    │      ├─ TickingTasks에서 제거
    │      └─ SimulatedTasks에서 제거
    └─ MarkAsGarbage()
```

---

## 태스크 생성 시 NewTask\<T\>()와 InitTask()는 각각 무슨 역할을 하는가?

### NewTask\<T\>()의 내부 구현은 어떻게 되는가?
> `GameplayTask.h` — 정적 템플릿 헬퍼

```cpp
template <class T>
static T* NewTask(IGameplayTaskOwnerInterface& TaskOwner, uint8 Priority = FGameplayTasks::DefaultPriority)
{
    T* MyTask = NewObject<T>();
    MyTask->InitTask(TaskOwner, Priority);
    return MyTask;
}
```

`UAbilityTask`에서는 이 대신 `NewAbilityTask<T>()`를 사용한다. 동일한 패턴이지만 GA 컨텍스트를 추가로 설정한다.

### InitTask()는 어떤 상태로 태스크를 초기화하는가?
> `GameplayTask.cpp`

```cpp
void UGameplayTask::InitTask(IGameplayTaskOwnerInterface& InTaskOwner, uint8 InPriority)
{
    Priority  = InPriority;
    TaskOwner = &InTaskOwner;
    TaskState = EGameplayTaskState::AwaitingActivation;

    if (UGameplayTasksComponent* TasksComp = InTaskOwner.GetGameplayTasksComponent(*this))
    {
        TasksComponent = TasksComp;
    }

    InTaskOwner.OnGameplayTaskInitialized(*this);
}
```

이 시점에서 태스크는 `AwaitingActivation` 상태다. 아직 실행되지 않는다.

### RF_StrongRefOnFrame 플래그는 왜 필요하며 태스크를 언제까지 GC로부터 보호하는가?
> `GameplayTask.h` 생성자

`NewObject<T>()`로 생성된 태스크는 강한 참조가 없으면 다음 GC 사이클에서 수집될 수 있다. 생성자에서 `RF_StrongRefOnFrame` 플래그를 설정해 `ReadyForActivation()`으로 `TasksComponent`가 소유하기 전까지 현재 프레임 동안 GC로부터 보호한다.

```cpp
UGameplayTask::UGameplayTask(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
    SetFlags(RF_StrongRefOnFrame);
}
```

---

## ReadyForActivation() 호출 후 태스크 활성화는 어떤 두 경로로 분기되는가?

### 즉시 실행 경로와 큐 대기 경로는 각각 어떤 조건에서 선택되는가?

**경로 A — 즉시 실행** (`RequiresPriorityOrResourceManagement() == false`):
```
ReadyForActivation() → PerformActivation() → Activate()
```

**경로 B — 큐 대기** (우선순위/리소스 충돌 가능):
```
ReadyForActivation() → TasksComponent->AddTaskReadyForActivation()
                           → TaskPriorityQueue 삽입
                           → UpdateTaskActivations()
                               → 조건 충족 시 PerformActivation() → Activate()
```

`PerformActivation()` 안에서 `TaskState`가 `Active`로 바뀐 뒤 `Activate()`가 호출된다.

---

## 태스크 실행 중에 틱과 일시 중단은 어떻게 동작하는가?

### TickTask()는 어떤 경로로 호출되며 순회 중 자기 파괴 문제를 어떻게 방어하는가?

`bTickingTask = true`인 태스크는 `TasksComponent->TickComponent()`에서 매 프레임 `TickTask(DeltaTime)`을 받는다. 틱 중에 태스크가 자신을 파괴할 수 있으므로 `TasksComponent`는 `TickingTasks`를 **로컬 배열로 복사한 뒤** 순회한다.

### PauseTask()와 ResumeTask()는 어떻게 작동하는가?

`PauseTask()` — `Active → Paused`
`ResumeTask()` — `Paused → Active`

일시 중단 중에는 `TickTask()` 호출이 없다.

---

## 태스크는 어떤 두 경로로 종료되며 각 경우 OnDestroy()의 bOwnerFinished 값은 무엇인가?

### EndTask()와 TaskOwnerEnded()의 차이를 bOwnerFinished 파라미터로 어떻게 구분하는가?

| 경로 | 호출자 | `bOwnerFinished` | 의미 |
|---|---|---|---|
| `EndTask()` | 태스크 자신 | `false` | 태스크가 스스로 완료됨 |
| `TaskOwnerEnded()` | GA 등 소유자 | `true` | 소유자가 종료되며 태스크도 정리 |

### OnDestroy() 내부에서 어떤 정리 작업이 일어나는가?

```cpp
void UGameplayTask::OnDestroy(bool bInOwnerFinished)
{
    TaskState = EGameplayTaskState::Finished;
    TasksComponent->OnGameplayTaskDeactivated(*this);
    MarkAsGarbage();
}
```

`Super::OnDestroy()`는 항상 **마지막**에 호출한다.

### MarkAsGarbage() 호출 후 태스크 포인터를 사용하면 왜 위험한가?

`MarkAsGarbage()` 직후 객체가 즉시 파괴되는 것이 아니라 GC가 다음 사이클에 수집한다. 그 사이에 포인터를 사용하면 dangling pointer가 될 수 있으므로, `OnDestroy()` 이후에는 태스크 포인터를 사용하면 안 된다.
