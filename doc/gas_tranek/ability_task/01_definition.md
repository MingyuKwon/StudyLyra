# AbilityTask 정의

> **GASDoc**: 4.7.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-at-definition"></a>
### AbilityTask란 무엇이고, GameplayAbility 단일 프레임 한계를 어떻게 극복하는가?

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

### UAbilityTask는 UGameplayTask 위에 무엇을 추가하는가?

`UAbilityTask`는 범용 비동기 태스크 시스템인 `UGameplayTask`를 GAS에 통합한 클래스다.
`UGameplayTask` 자체의 구조와 복제 메커니즘은 → [00 GameplayTask](gameplay_task/README.md) 참조.

`UAbilityTask`가 `UGameplayTask` 위에 추가하는 것은 세 가지다.

**① GA 수명 연동**
`UGameplayTask`는 독립적인 수명을 갖는다.
`UAbilityTask`는 자신을 만든 GA와 수명이 묶여 있어, GA가 `EndAbility()`로 종료되면 해당 GA의 모든 AbilityTask가 자동으로 파괴된다.

**② GAS 컨텍스트 접근**
`UGameplayTask`는 ASC, AvatarActor, AbilityActorInfo를 모른다.
`UAbilityTask`는 자신을 만든 `UGameplayAbility` 포인터를 보유하므로, 태스크 내부에서 GAS 전체 컨텍스트에 바로 접근할 수 있다.

```cpp
Ability->GetAbilitySystemComponent()    // ASC
Ability->GetAvatarActorFromActorInfo()  // AvatarActor
Ability->GetActorInfo()                 // FGameplayAbilityActorInfo 전체
```

**③ GAS 예측 시스템 연동**
`UAbilityTask`는 GAS의 `PredictionKey` 시스템에 참여할 수 있다.
`UGameplayTask`에는 예측 개념 자체가 없다.

---

### UGameplayTask와 UAbilityTask의 차이는 무엇이고, 언제 어느 것을 써야 하는가?

| | `UGameplayTask` | `UAbilityTask` |
|---|---|---|
| 위치 | `GameplayTasks` 플러그인 | `GameplayAbilities` 플러그인 |
| 생성 | `NewTask<T>(TaskOwner)` | `NewAbilityTask<T>(Ability)` |
| 소유자 타입 | `IGameplayTaskOwnerInterface` | `UGameplayAbility` |
| 수명 | 독립적 (명시적 종료 필요) | GA 수명에 종속 — GA 종료 시 자동 파괴 |
| ASC 접근 | 불가 | `Ability->GetAbilitySystemComponent()` |
| AvatarActor 접근 | 불가 | `Ability->GetAvatarActorFromActorInfo()` |
| 예측 시스템 | 없음 | `PredictionKey` 참여 가능 |
| 동시 실행 제한 | 없음 | 전체 1000개 하드코딩 제한 |
| GAS 없이 사용 | 가능 | 불가 (GA 필수) |

---

### 코드로 보면 두 태스크의 생성·수명·델리게이트 처리가 어떻게 다른가?

#### 두 태스크의 생성 방식은 어떻게 다른가?

```cpp
// GameplayTask — TaskOwner 인터페이스를 구현한 누구든 소유 가능
UMyTask* Task = UMyTask::NewTask<UMyTask>(TaskOwner, Priority);
Task->ReadyForActivation();

// AbilityTask — 반드시 UGameplayAbility가 소유자
UMyAbilityTask* Task = UMyAbilityTask::NewAbilityTask<UMyAbilityTask>(this /*GA*/);
Task->ReadyForActivation();
```

`NewAbilityTask<T>()` 내부에서 GA로부터 ASC를 찾아 `TasksComponent`에 연결한다.
연결 대상이 항상 ASC이므로 GAS 컨텍스트 전체를 바로 쓸 수 있다.

#### AbilityTask는 GA 종료 시 어떻게 자동으로 정리되는가?

```cpp
// UAbilityTask::OnDestroy() 내부
void UAbilityTask::OnDestroy(bool bInOwnerFinished)
{
    // GA가 델리게이트 브로드캐스트를 막고 있으면 알리지 않음
    // → GA 종료 후 남은 콜백이 GA를 접근하는 것을 방지
    if (Ability)
    {
        Ability->TaskEnded(this);
    }
    Super::OnDestroy(bInOwnerFinished);
}
```

`EndAbility()`가 호출되면 GA가 소유한 모든 AbilityTask에 `TaskOwnerEnded()`를 보내 전부 정리한다.

#### AbilityTask에서 델리게이트를 브로드캐스트하기 전 왜 ShouldBroadcastAbilityTaskDelegates()를 체크해야 하는가?

```cpp
// AbilityTask에만 있는 패턴
void UMyAbilityTask::OnSomethingHappened()
{
    if (ShouldBroadcastAbilityTaskDelegates())  // GA가 살아있을 때만 true
    {
        OnCompleted.Broadcast(...);
    }
    EndTask();
}
```

`ShouldBroadcastAbilityTaskDelegates()`는 GA가 이미 종료됐으면 `false`를 반환한다.
델리게이트 브로드캐스트 전에 이 체크를 넣지 않으면 종료된 GA를 향한 콜백이 실행될 수 있다.
Lyra의 `AbilityTask_GrantNearbyInteraction`은 완료 델리게이트가 없는 지속형 태스크라 이 패턴이 필요 없지만, 일반적인 태스크에서는 필수다.

#### SetWaitingOnAvatar()는 언제, 왜 호출해야 하는가?

```cpp
// AbilityTask에만 있는 유틸리티
void UMyAbilityTask::Activate()
{
    SetWaitingOnAvatar();  // AvatarActor가 아직 준비되지 않았으면 대기 상태로 전환
    // ...
}
```

Lyra의 두 Interaction 태스크가 모두 `Activate()` 첫 줄에 이 호출을 넣는다.
서버에서 GA가 먼저 활성화됐을 때 AvatarActor가 아직 없는 엣지케이스를 방어한다.

---

### GA 안에서 비동기 작업이 필요할 때 UGameplayTask와 UAbilityTask 중 무엇을 써야 하는가?

| 상황 | 선택 |
|---|---|
| GA 안에서 비동기 작업 | `UAbilityTask` |
| AI BehaviorTree에서 비동기 작업 | `UGameplayTask` (GAS 없이) |
| GA 수명과 무관하게 독립 실행 | `UGameplayTask` |
| ASC/AvatarActor/PredictionKey 접근 필요 | `UAbilityTask` |

GAS 프로젝트에서 `UGameplayTask`를 직접 쓰는 경우는 거의 없다.
GA 안이라면 항상 `UAbilityTask`를 쓰는 게 맞다.
