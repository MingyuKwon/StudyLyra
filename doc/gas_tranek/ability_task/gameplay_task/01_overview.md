# GameplayTask 개요

> 소스: `Engine/Source/Runtime/GameplayTasks/Classes/GameplayTask.h`, `Private/GameplayTask.cpp`

---

## GameplayTask 플러그인이 GAS와 분리된 이유는 무엇인가?

비동기 태스크 패턴은 GAS만의 문제가 아니다. AI, 인터랙션, 퀘스트 등 게임 여러 곳에서 동일한 패턴이 필요하다. 언리얼은 이 패턴을 **`GameplayTasks` 플러그인**으로 분리했고, GAS는 그 위에 GAS 전용 레이어(`UAbilityTask`)만 얹는다.

```
GameplayTasks 플러그인      비동기 태스크 실행·관리  (범용)
      ↑
GameplayAbilities 플러그인  GAS 어빌리티에서의 비동기 태스크  (특화)
```

이점:
- GAS 없는 시스템(BehaviorTree의 `UBTTaskNode_GameplayTaskBase` 등)도 동일한 패턴 사용 가능
- `UAbilityTask`는 "GA 수명 연동·ASC 접근·예측 시스템"이라는 GAS 고유 문제만 추가하면 됨

---

## UGameplayTask, UAbilityTask, UGameplayTasksComponent, UAbilitySystemComponent의 계층 관계는?

```
UObject
  └─ UGameplayTask                  (GameplayTasks 플러그인)
        └─ UAbilityTask             (GameplayAbilities 플러그인 — GAS 전용)

UActorComponent
  └─ UGameplayTasksComponent        (태스크 소유·관리)
        └─ UAbilitySystemComponent  (GAS 핵심 컴포넌트)
```

`UAbilitySystemComponent`가 `UGameplayTasksComponent`를 상속하므로, ASC는 곧 태스크 컴포넌트다.

---

## GameplayTask의 상태 머신은 어떻게 구성되며 각 상태는 언제 진입하는가?

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

## UGameplayTask를 GAS 없이도 쓸 수 있는가? GAS 프로젝트에서는 언제 직접 쓰는가?

`UGameplayTask`는 GAS 없이도 사용할 수 있다. BehaviorTree의 `UBTTaskNode_GameplayTaskBase`가 대표 예시다.

GAS 프로젝트에서는 거의 항상 `UAbilityTask`를 사용한다. `UGameplayTask`를 직접 쓰는 경우는 GAS 없이 순수 `UGameplayTasksComponent` 위에서 태스크를 돌릴 때뿐이다.
