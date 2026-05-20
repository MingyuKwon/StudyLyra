# GameplayTasksComponent

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTasksComponent.h`, `Private/GameplayTasksComponent.cpp`

태스크의 소유자이자 실행 관리자다. 태스크 생성·활성화·종료·복제를 모두 이 컴포넌트가 조율한다.

---

## GameplayTasksComponent가 태스크를 관리하는 4개의 내부 배열은 각각 어떤 역할인가?

컴포넌트는 실행 중인 태스크를 4개의 배열로 분류해 관리한다.

```cpp
// 우선순위 큐 — ReadyForActivation() 대기 중인 태스크
UPROPERTY()
TArray<TWeakObjectPtr<UGameplayTask>> TaskPriorityQueue;

// 틱 태스크 — bTickingTask=true, 매 프레임 TickTask() 받는 태스크
UPROPERTY()
TArray<TObjectPtr<UGameplayTask>> TickingTasks;

// 알려진 태스크 — 현재 Active/Paused 상태의 모든 태스크
UPROPERTY(Transient)
TArray<TObjectPtr<UGameplayTask>> KnownTasks;

// 복제 태스크 — bSimulatedTask=true, simulated proxy에 복제되는 태스크
UPROPERTY(Transient, ReplicatedUsing=OnRep_SimulatedTasks)
TArray<TObjectPtr<UGameplayTask>> SimulatedTasks;
```

각 태스크는 해당되는 배열에 **중복 등록**된다.
예를 들어 `bTickingTask=true`이고 `bSimulatedTask=true`인 태스크는 `KnownTasks` + `TickingTasks` + `SimulatedTasks` 모두에 들어간다.

---

## GameplayTasksComponent는 기본적으로 틱이 비활성화되어 있는가, 그리고 언제 켜지는가?

```cpp
UGameplayTasksComponent::UGameplayTasksComponent(const FObjectInitializer& OI)
    : Super(OI)
{
    PrimaryComponentTick.bStartWithTickEnabled = false; // 기본 틱 비활성
    SetIsReplicatedByDefault(true);                     // 복제 기본 활성
}
```

틱은 `TickingTasks`에 태스크가 들어올 때 `UpdateShouldTick()`에 의해 동적으로 켜진다.

---

## 태스크 활성화 시 OnGameplayTaskActivated()는 어떤 배열에 등록하는가?

`PerformActivation()` 내부에서 호출된다. 태스크를 적절한 배열에 등록한다.

```cpp
void UGameplayTasksComponent::OnGameplayTaskActivated(UGameplayTask& Task)
{
    KnownTasks.Add(&Task);

    if (Task.IsTickingTask())
    {
        TickingTasks.Add(&Task);
        UpdateShouldTick(); // 틱 활성화 여부 재평가
    }

    if (Task.IsSimulatedTask())
    {
        AddSimulatedTask(Task); // SimulatedTasks + 복제 서브오브젝트 등록
    }
}
```

### UpdateShouldTick()은 언제 호출되며 어떤 조건에서 컴포넌트 틱을 켜는가?

```cpp
void UGameplayTasksComponent::UpdateShouldTick()
{
    // TickingTasks가 하나라도 있으면 컴포넌트 틱 활성
    SetActive(TickingTasks.Num() > 0);
}
```

TickingTask가 없으면 컴포넌트 틱이 꺼진다. 성능 최적화다.

---

## 태스크 종료 시 OnGameplayTaskDeactivated()는 어떤 정리를 수행하는가?

`OnDestroy()` 내부에서 호출된다. 태스크를 배열에서 제거한다.

```cpp
void UGameplayTasksComponent::OnGameplayTaskDeactivated(UGameplayTask& Task)
{
    KnownTasks.Remove(&Task);

    if (Task.IsTickingTask())
    {
        TickingTasks.Remove(&Task);
        UpdateShouldTick();
    }

    if (Task.IsSimulatedTask())
    {
        SimulatedTasks.Remove(&Task);
        RemoveReplicatedSubObject(&Task);
    }
}
```

---

## TickComponent()에서 틱 도중 태스크가 자기 자신을 종료할 때 배열 변경 문제를 어떻게 방어하는가?

```cpp
void UGameplayTasksComponent::TickComponent(float DeltaTime, ...)
{
    // 틱 중에 태스크가 자기 자신을 종료해 배열이 변경될 수 있다
    // 로컬 복사본으로 순회해서 방어
    TArray<TObjectPtr<UGameplayTask>> LocalTickingTasks = TickingTasks;

    for (UGameplayTask* Task : LocalTickingTasks)
    {
        if (Task && !Task->IsFinished())
        {
            Task->TickTask(DeltaTime);
        }
    }
}
```

틱 도중 `EndTask()`가 호출돼 `TickingTasks`가 변해도, 로컬 복사본으로 순회하므로 안전하다.

---

## 태스크 우선순위 큐는 어떻게 작동하며 리소스 충돌 시 스케줄링은 어떻게 결정되는가?

### AddTaskReadyForActivation()은 어떤 경로로 태스크를 큐에 등록하는가?

`ReadyForActivation()`에서 리소스/우선순위 관리가 필요한 태스크를 호출한다.

```cpp
void UGameplayTasksComponent::AddTaskReadyForActivation(UGameplayTask& NewTask)
{
    AddTaskToPriorityQueue(NewTask);
    UpdateTaskActivations();
}
```

### 같은 우선순위의 태스크 삽입 순서는 ETaskResourceOverlapPolicy로 어떻게 결정되는가?

우선순위 내림차순으로 삽입한다. 같은 우선순위 내 순서는 `ETaskResourceOverlapPolicy`로 결정된다.

```cpp
enum class ETaskResourceOverlapPolicy : uint8
{
    StartOnTop,       // 같은 우선순위에서 앞으로
    StartAtEnd,       // 같은 우선순위에서 뒤로
    RequestCancel,    // 현재 실행 중인 태스크를 취소 요청
    // ...
};
```

### UpdateTaskActivations()는 큐에서 어떤 기준으로 태스크를 실행 또는 대기 상태로 남기는가?

큐 앞에서부터 실행 가능 여부를 평가한다.
RequiredResources가 이미 점유된 리소스와 충돌하면 해당 태스크는 대기 상태로 남는다.

```
for each task in TaskPriorityQueue (high priority first):
    if task's RequiredResources overlap with claimed resources:
        block (task stays in queue)
    else:
        PerformActivation(task)
        claim task's RequiredResources
```

---

## ProcessTaskEvents()에서 무한 루프를 막기 위해 어떤 안전장치를 사용하는가?

태스크 활성화/비활성화 중에 새 이벤트가 발생할 수 있다.
무한 루프를 막기 위해 `MaxIterations = 16` 제한과 `FEventLock` 재진입 방지 장치가 있다.

```cpp
void UGameplayTasksComponent::ProcessTaskEvents()
{
    static const int32 MaxIterations = 16;
    int32 Iter = 0;
    FEventLock EventLock(this); // 재진입 차단

    while (TaskEvents.Num() > 0 && Iter++ < MaxIterations)
    {
        // 이벤트 처리...
    }
}
```

---

## SimulatedTasks 배열은 어떻게 복제되며 Owning Client는 왜 제외되는가?

### AddSimulatedTask()에서 COND_SkipOwner를 사용하는 이유는 무엇인가?

`bSimulatedTask=true`인 태스크가 활성화될 때 호출된다.

```cpp
void UGameplayTasksComponent::AddSimulatedTask(UGameplayTask& NewTask)
{
    SimulatedTasks.Add(&NewTask);
    // COND_SkipOwner — owning client에는 복제하지 않음
    AddReplicatedSubObject(&NewTask, COND_SkipOwner);
}
```

### Simulated Proxy가 SimulatedTasks를 받았을 때 OnRep_SimulatedTasks()는 어떻게 초기화하는가?

Simulated proxy에서 배열이 복제됐을 때 호출된다.

```cpp
void UGameplayTasksComponent::OnRep_SimulatedTasks()
{
    for (UGameplayTask* Task : SimulatedTasks)
    {
        if (Task && !Task->IsActive())
        {
            Task->InitSimulatedTask(*this); // bIsSimulating = true 세팅

            if (Task->IsTickingTask())
            {
                TickingTasks.Add(Task);
                UpdateShouldTick();
            }
        }
    }
}
```

### ReplicateSubobjects()에서 Owning Client에게 SimulatedTasks를 복제하지 않는 이유는?

`NetOwner`(owning client)에게는 SimulatedTasks를 복제하지 않는다.
owning client는 자신이 직접 태스크를 실행하기 때문이다.

```cpp
bool UGameplayTasksComponent::ReplicateSubobjects(UActorChannel* Channel, FOutBunch* Bunch, FReplicationFlags* RepFlags)
{
    bool WroteSomething = Super::ReplicateSubobjects(Channel, Bunch, RepFlags);

    if (!RepFlags->bNetOwner) // owning client가 아닌 경우에만
    {
        for (UGameplayTask* Task : SimulatedTasks)
        {
            if (Task)
            {
                WroteSomething |= Channel->ReplicateSubobject(Task, *Bunch, *RepFlags);
            }
        }
    }

    return WroteSomething;
}
```

---

## ASC가 GameplayTasksComponent를 상속하면 어떤 이점이 생기는가?

`UAbilitySystemComponent`는 `UGameplayTasksComponent`를 상속한다.

```
UActorComponent
  └─ UGameplayTasksComponent    (태스크 소유·관리)
        └─ UAbilitySystemComponent
```

따라서 ASC는 태스크 컴포넌트이기도 하다.
`UAbilityTask`가 `UGameplayTasksComponent`를 찾을 때 ASC가 반환된다.
