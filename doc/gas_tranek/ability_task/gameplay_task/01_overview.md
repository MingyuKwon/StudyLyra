# GameplayTask 개요

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTask.h`, `Private/GameplayTask.cpp`

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

| 상태 | 진입 시점 |
|---|---|
| `Uninitialized` | 객체 생성 직후 |
| `AwaitingActivation` | `InitTask()` 호출 후 |
| `Active` | `PerformActivation()` → `Activate()` 호출 시 |
| `Paused` | `PauseTask()` 호출 시 (Active ↔ Paused 전환) |
| `Finished` | `OnDestroy()` 호출 시 |

---

## GAS 밖에서의 사용

`UGameplayTask`는 GAS 없이도 사용할 수 있다.
언리얼 AI 시스템의 `UBTTaskNode_GameplayTaskBase`가 대표적인 예로, BehaviorTree Task가 내부적으로 GameplayTask를 활용한다.

GAS를 쓰는 프로젝트에서는 거의 항상 `UAbilityTask`를 사용하게 된다.
`UGameplayTask`를 직접 사용하는 경우는 GAS 없이 순수 `UGameplayTasksComponent` 위에서 태스크를 돌릴 때다.
