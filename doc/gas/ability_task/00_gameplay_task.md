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

## 핵심 API

| 요소 | 설명 |
|---|---|
| `Activate()` | 태스크 시작 진입점. 외부 델리게이트 바인딩 등 실제 작업 시작 |
| `OnDestroy(bool bOwnerFinished)` | 태스크 종료 시 정리. 델리게이트 언바인딩 등 |
| `ReadyForActivation()` | 태스크를 큐에 등록하고 `Activate()` 호출 트리거. C++에서는 수동 호출 필요 |
| `TickTask(float DeltaTime)` | 매 틱 실행. 생성자에서 `bTickingTask = true` 설정 시 활성화 |
| `EndTask()` | 태스크를 명시적으로 종료 |

Blueprint에서는 `K2Node_LatentGameplayTaskCall`이 `ReadyForActivation()`을 자동으로 호출한다.
C++에서는 직접 호출해야 한다.

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
