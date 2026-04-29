# GameplayTask 핵심 API

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTask.h`, `Private/GameplayTask.cpp`

---

## ReadyForActivation()
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

## Activate()
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

## EndTask()
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

## OnDestroy(bool bOwnerFinished)
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

## TickTask(float DeltaTime)
> `GameplayTask.h:171`

매 틱 실행이 필요한 태스크를 위한 훅이다.
기본 구현은 빈 함수(`{}`)이며, 생성자에서 아래 플래그를 설정해야 활성화된다.

```cpp
// 생성자에서
bTickingTask = true;   // TasksComponent가 매 틱 TickTask() 호출하도록 등록
```

`bTickingTask`는 `uint32` 비트 필드(`GameplayTask.h:342`)로, 기본값 `false`다.


> 복제 관련 내용(`bSimulatedTask`, Simulated Proxy 복제 흐름, 엔진/Lyra 예시)은 → [05 복제](05_replication.md) 참조.
