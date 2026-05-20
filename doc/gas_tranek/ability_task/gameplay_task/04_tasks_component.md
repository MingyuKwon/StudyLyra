# GameplayTasksComponent

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTasksComponent.h`, `Private/GameplayTasksComponent.cpp`

태스크의 소유자이자 실행 관리자다. 태스크 생성·활성화·종료·복제를 모두 이 컴포넌트가 조율한다.

---

## GameplayTasksComponent가 태스크를 관리하는 4개의 내부 배열은 각각 어떤 역할인가?

| 배열 | 역할 |
|---|---|
| `TaskPriorityQueue` | `ReadyForActivation()` 대기 중인 태스크 (우선순위 큐) |
| `TickingTasks` | `bTickingTask=true`, 매 프레임 `TickTask()` 받는 태스크 |
| `KnownTasks` | 현재 Active/Paused 상태의 모든 태스크 |
| `SimulatedTasks` | `bSimulatedTask=true`, simulated proxy에 복제되는 태스크 |

하나의 태스크가 해당되는 배열에 **중복 등록**된다. `bTickingTask=true`이고 `bSimulatedTask=true`인 태스크는 `KnownTasks` + `TickingTasks` + `SimulatedTasks` 모두에 들어간다.

---

## GameplayTasksComponent는 기본적으로 틱이 비활성화되어 있는가, 그리고 언제 켜지는가?

기본적으로 틱이 꺼져 있다. `TickingTasks`에 태스크가 추가될 때 `UpdateShouldTick()`이 동적으로 켠다.

```cpp
UGameplayTasksComponent::UGameplayTasksComponent(const FObjectInitializer& OI)
{
    PrimaryComponentTick.bStartWithTickEnabled = false;  // 기본 틱 비활성
    SetIsReplicatedByDefault(true);
}
```

---

## 태스크 활성화 시 OnGameplayTaskActivated()는 어떤 배열에 등록하는가?

```cpp
void UGameplayTasksComponent::OnGameplayTaskActivated(UGameplayTask& Task)
{
    KnownTasks.Add(&Task);

    if (Task.IsTickingTask())
    {
        TickingTasks.Add(&Task);
        UpdateShouldTick();
    }

    if (Task.IsSimulatedTask())
    {
        AddSimulatedTask(Task);  // SimulatedTasks + 복제 서브오브젝트 등록
    }
}
```

### UpdateShouldTick()은 언제 호출되며 어떤 조건에서 컴포넌트 틱을 켜는가?

`TickingTasks`가 하나라도 있으면 컴포넌트 틱을 켠다. `TickingTasks`가 비면 자동으로 꺼진다. 불필요한 틱을 막는 성능 최적화다.

---

## 태스크 종료 시 OnGameplayTaskDeactivated()는 어떤 정리를 수행하는가?

`OnDestroy()` 내부에서 호출된다. 태스크를 해당 배열에서 제거하고, `TickingTasks`가 변경되면 `UpdateShouldTick()`을 재평가한다. `SimulatedTask`이면 복제 서브오브젝트 등록도 해제한다.

---

## TickComponent()에서 틱 도중 태스크가 자기 자신을 종료할 때 배열 변경 문제를 어떻게 방어하는가?

```cpp
void UGameplayTasksComponent::TickComponent(float DeltaTime, ...)
{
    TArray<TObjectPtr<UGameplayTask>> LocalTickingTasks = TickingTasks;  // 로컬 복사본으로 순회

    for (UGameplayTask* Task : LocalTickingTasks)
    {
        if (Task && !Task->IsFinished())
        {
            Task->TickTask(DeltaTime);
        }
    }
}
```

틱 도중 `EndTask()`가 호출돼 `TickingTasks`가 변해도 로컬 복사본으로 순회하므로 안전하다.

---

## 태스크 우선순위 큐는 어떻게 작동하며 리소스 충돌 시 스케줄링은 어떻게 결정되는가?

### AddTaskReadyForActivation()은 어떤 경로로 태스크를 큐에 등록하는가?

우선순위 내림차순으로 삽입하고 `UpdateTaskActivations()`를 호출한다.

### 같은 우선순위의 태스크 삽입 순서는 ETaskResourceOverlapPolicy로 어떻게 결정되는가?

```cpp
enum class ETaskResourceOverlapPolicy : uint8
{
    StartOnTop,      // 같은 우선순위에서 앞으로
    StartAtEnd,      // 같은 우선순위에서 뒤로
    RequestCancel,   // 현재 실행 중인 태스크를 취소 요청
};
```

### UpdateTaskActivations()는 큐에서 어떤 기준으로 태스크를 실행 또는 대기 상태로 남기는가?

큐 앞에서부터 평가한다. `RequiredResources`가 이미 점유된 리소스와 충돌하면 대기 상태로 남기고, 충돌하지 않으면 `PerformActivation()`으로 실행한다.

---

## ProcessTaskEvents()에서 무한 루프를 막기 위해 어떤 안전장치를 사용하는가?

태스크 활성화/비활성화 중에 새 이벤트가 발생할 수 있다. `MaxIterations = 16` 제한과 `FEventLock` 재진입 방지 장치로 무한 루프를 막는다.

```cpp
void UGameplayTasksComponent::ProcessTaskEvents()
{
    static const int32 MaxIterations = 16;
    int32 Iter = 0;
    FEventLock EventLock(this);  // 재진입 차단

    while (TaskEvents.Num() > 0 && Iter++ < MaxIterations)
    {
        // 이벤트 처리...
    }
}
```

---

## SimulatedTasks 배열은 어떻게 복제되며 Owning Client는 왜 제외되는가?

### AddSimulatedTask()에서 COND_SkipOwner를 사용하는 이유는 무엇인가?

owning client는 이미 `Activate()`로 직접 태스크를 실행하고 있으므로 복제가 불필요하다.

```cpp
void UGameplayTasksComponent::AddSimulatedTask(UGameplayTask& NewTask)
{
    SimulatedTasks.Add(&NewTask);
    AddReplicatedSubObject(&NewTask, COND_SkipOwner);  // owning client 제외
}
```

### Simulated Proxy가 SimulatedTasks를 받았을 때 OnRep_SimulatedTasks()는 어떻게 초기화하는가?

새로 도착한 태스크(`IsActive() == false`)에 대해 `InitSimulatedTask(*this)`를 호출하고, `bTickingTask=true`이면 `TickingTasks`에 추가한다.

---

## ASC가 GameplayTasksComponent를 상속하면 어떤 이점이 생기는가?

`UAbilitySystemComponent`가 `UGameplayTasksComponent`를 상속하므로, ASC 자체가 태스크 컴포넌트다. `UAbilityTask`가 `UGameplayTasksComponent`를 찾을 때 ASC가 반환되어 별도의 컴포넌트 없이 GAS 컨텍스트 전체를 태스크 관리에 활용할 수 있다.
