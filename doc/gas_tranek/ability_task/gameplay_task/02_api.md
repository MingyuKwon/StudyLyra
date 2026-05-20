# GameplayTask 핵심 API

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTask.h`, `Private/GameplayTask.cpp`

---

## ReadyForActivation()은 내부에서 어떻게 분기하며 왜 태스크가 즉시 실행되지 않을 수 있는가?
> `GameplayTask.cpp:56`

태스크를 시작시키는 공개 진입점이다. C++에서는 생성 후 반드시 수동으로 호출해야 하며, Blueprint에서는 `K2Node_LatentGameplayTaskCall`이 자동으로 호출한다.

```cpp
void UGameplayTask::ReadyForActivation()
{
    if (UGameplayTasksComponent* TasksPtr = TasksComponent.Get())
    {
        if (RequiresPriorityOrResourceManagement() == false)
        {
            PerformActivation();                         // 즉시 실행
        }
        else
        {
            TasksPtr->AddTaskReadyForActivation(*this);  // 큐에 등록 → TasksComponent가 때를 결정
        }
    }
    else
    {
        EndTask();  // TasksComponent 없으면 즉시 종료
    }
}
```

`RequiredResources`나 우선순위 관리가 필요한 태스크는 `TasksComponent`가 실행 순서를 결정하므로 즉시 실행되지 않을 수 있다.

---

## Activate()는 어느 시점에 호출되며, 동기 완료 패턴은 어떻게 처리되는가?
> `GameplayTask.cpp:298`

`PerformActivation()` 내부에서 `TaskState`가 `Active`로 바뀐 **뒤에** 호출된다. 개발자가 오버라이드해서 실제 태스크 로직을 구현하는 곳이다.

```cpp
void UGameplayTask::PerformActivation()
{
    TaskState = EGameplayTaskState::Active;  // 상태 먼저 Active로
    Activate();                              // 개발자 로직 실행

    if (IsFinished() == false)
    {
        TasksComponent->OnGameplayTaskActivated(*this);
    }
}
```

`Activate()` 안에서 바로 `EndTask()`를 호출하는 동기 완료 패턴도 유효하다. `IsFinished()` 체크로 이 경우를 처리한다.

---

## EndTask()와 TaskOwnerEnded()는 어떻게 다른가?
> `GameplayTask.cpp:165`

| | `EndTask()` | `TaskOwnerEnded()` |
|---|---|---|
| 호출 주체 | 태스크 자신 | GA 등 소유자 |
| `OnDestroy()` 인자 | `false` | `true` |
| 의미 | 태스크가 스스로 완료 | 소유자가 끝나며 정리 |

두 경로 모두 `OnDestroy(bOwnerFinished)`로 수렴한다.

---

## OnDestroy()를 오버라이드할 때 Super::OnDestroy()를 반드시 마지막에 호출해야 하는 이유는?
> `GameplayTask.cpp:206`

`OnDestroy()` 베이스 구현 마지막에 `MarkAsGarbage()`가 호출된다. `MarkAsGarbage()` 이후에는 BP 내부 메커니즘이 동작하지 않을 수 있으므로, 개발자의 정리 코드(델리게이트 언바인딩 등)가 먼저 실행된 후 `Super::OnDestroy()`를 마지막에 호출해야 한다.

```cpp
void UGameplayTask::OnDestroy(bool bInOwnerFinished)
{
    TaskState = EGameplayTaskState::Finished;
    TasksComponent->OnGameplayTaskDeactivated(*this);
    MarkAsGarbage();
}
```

---

## 태스크에서 매 틱 실행이 필요할 때 어떻게 활성화하는가?
> `GameplayTask.h:171`

생성자에서 `bTickingTask = true`로 설정하고 `TickTask(float DeltaTime)`을 오버라이드한다.

```cpp
// 생성자에서
bTickingTask = true;   // TasksComponent가 매 틱 TickTask()를 호출하도록 등록
```

`bTickingTask`는 기본값 `false`다. 플래그가 설정된 태스크만 `TickingTasks` 배열에 등록되어 틱을 받는다.

> 복제 관련 내용(`bSimulatedTask`, Simulated Proxy 복제 흐름)은 → [05 복제](05_replication.md) 참조.
