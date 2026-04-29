# AbilityTask 정의

> **GASDoc**: 4.7.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-definition"></a>
### 4.7.1 AbilityTask 정의

`GameplayAbility`는 단일 프레임에서만 실행된다. 이것만으로는 유연성이 크게 부족하다. 시간에 걸쳐 진행되는 동작이나, 나중에 발생하는 델리게이트에 응답해야 하는 동작을 처리하려면 **잠재적(latent) 액션**인 `AbilityTask`를 사용한다.

GAS는 다음과 같은 `AbilityTask`를 기본으로 제공한다:
* `RootMotionSource`를 이용해 캐릭터를 이동시키는 태스크
* 애니메이션 몽타주를 재생하는 태스크
* `Attribute` 변경에 응답하는 태스크
* `GameplayEffect` 변경에 응답하는 태스크
* 플레이어 입력에 응답하는 태스크
* 그 외 다수

`UAbilityTask` 생성자는 게임 전체에서 동시에 실행되는 `AbilityTask` 수를 **최대 1000개**로 하드코딩하여 제한한다. RTS 게임처럼 수백 명의 캐릭터가 월드에 동시에 존재할 수 있는 게임의 `GameplayAbility`를 설계할 때 반드시 이 점을 고려해야 한다.

---

## 내 분석

### UGameplayTask — AbilityTask의 베이스

`UAbilityTask`는 `UGameplayTask`를 상속한다. 클래스 계층은 다음과 같다.

```
UObject
  └─ UGameplayTask          (GameplayTasks 플러그인 — GAS 무관)
        └─ UAbilityTask     (GameplayAbilities 플러그인 — GAS 전용)
```

`UGameplayTask`는 GAS와 무관한 **범용 비동기 태스크 시스템**이다. `UGameplayTasksComponent`를 가진 어떤 Actor에서든 사용할 수 있고, AI(`UBTTaskNode_GameplayTaskBase`) 등 GAS가 없는 시스템에서도 활용된다.

`UAbilitySystemComponent`는 `UGameplayTasksComponent`를 상속하기 때문에, AbilityTask는 ASC를 태스크 컴포넌트로 사용하는 구조다.

#### UGameplayTask의 핵심 구성

| 요소 | 설명 |
|---|---|
| `UGameplayTasksComponent` | 태스크를 소유하고 실행·종료를 관리하는 컴포넌트. ASC가 이를 상속 |
| `Activate()` | 태스크 시작 진입점. 외부 델리게이트 바인딩 등 실제 작업 시작 |
| `OnDestroy(bool bOwnerFinished)` | 태스크 종료 시 정리. 델리게이트 언바인딩 등 |
| `TickTask(float DeltaTime)` | 틱 지원. 생성자에서 `bTickingTask = true` 설정 시 활성화 |
| `bSimulatedTask` | `true`로 설정하면 ASC가 simulated proxy에 이 태스크를 복제 |
| `InitSimulatedTask()` | simulated proxy에서 복제 수신 후 호출되는 진입점. 개발자가 구현 |
| `ReadyForActivation()` | 태스크를 큐에 등록하고 `Activate()` 호출 트리거. C++에서는 수동 호출 필요 |

#### AbilityTask가 GameplayTask에 추가하는 것

`UAbilityTask`는 `UGameplayTask` 위에 GAS 전용 레이어를 세 가지 더한다.

**① GA 수명 연동**
`UGameplayTask`는 독립적인 수명을 갖는다. 반면 `UAbilityTask`는 자신을 만든 GA와 수명이 묶여 있다. GA가 `EndAbility()`로 종료되면 해당 GA가 만든 모든 AbilityTask가 자동으로 파괴된다.

**② GAS 컨텍스트 접근**
`UGameplayTask`는 ASC, AvatarActor, AbilityActorInfo를 모른다. `UAbilityTask`는 자신을 만든 `UGameplayAbility` 포인터를 보유하므로, 태스크 내부에서 GAS 전체 컨텍스트에 접근할 수 있다.

```cpp
Ability->GetAbilitySystemComponent()    // ASC
Ability->GetAvatarActorFromActorInfo()  // AvatarActor
Ability->GetActorInfo()                 // FGameplayAbilityActorInfo 전체
```

**③ GAS 예측 시스템 연동**
`UAbilityTask`는 GAS의 `PredictionKey` 시스템에 참여할 수 있다. `UGameplayTask`는 예측 개념 자체가 없다.
