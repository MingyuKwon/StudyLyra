# AbilityTask 정의

> **GASDoc**: 4.7.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-at-definition"></a>
### AbilityTask란 무엇이고, GameplayAbility 단일 프레임 한계를 어떻게 극복하는가?

`GameplayAbility`는 단일 프레임에서만 실행된다. 시간에 걸쳐 진행되거나 나중에 발생하는 델리게이트에 응답해야 하는 동작은 **AbilityTask**를 사용한다.

GAS가 기본 제공하는 AbilityTask:
- `RootMotionSource`로 캐릭터 이동
- 애니메이션 몽타주 재생
- `Attribute` / `GameplayEffect` 변경 감지
- 플레이어 입력 감지

`UAbilityTask` 생성자는 게임 전체 동시 실행 AbilityTask 수를 **최대 1000개**로 하드코딩한다. RTS처럼 캐릭터가 많은 게임에서는 반드시 고려해야 한다.

---

### UAbilityTask는 UGameplayTask 위에 무엇을 추가하는가?

`UAbilityTask`는 범용 비동기 태스크 시스템 `UGameplayTask`를 GAS에 통합한 클래스다. 추가하는 것은 세 가지다.

**① GA 수명 연동** — GA가 `EndAbility()`로 종료되면 해당 GA의 모든 AbilityTask가 자동 파괴된다.

**② GAS 컨텍스트 접근** — 자신을 만든 `UGameplayAbility` 포인터를 보유하므로 ASC, AvatarActor, ActorInfo에 바로 접근할 수 있다.

```cpp
Ability->GetAbilitySystemComponent()    // ASC
Ability->GetAvatarActorFromActorInfo()  // AvatarActor
Ability->GetActorInfo()                 // FGameplayAbilityActorInfo 전체
```

**③ GAS 예측 시스템 연동** — `PredictionKey` 시스템에 참여할 수 있다.

---

### UGameplayTask와 UAbilityTask의 차이는 무엇이고, 언제 어느 것을 써야 하는가?

| | `UGameplayTask` | `UAbilityTask` |
|---|---|---|
| 위치 | `GameplayTasks` 플러그인 | `GameplayAbilities` 플러그인 |
| 생성 | `NewTask<T>(TaskOwner)` | `NewAbilityTask<T>(Ability)` |
| 소유자 타입 | `IGameplayTaskOwnerInterface` | `UGameplayAbility` |
| 수명 | 독립적 (명시적 종료 필요) | GA 종료 시 자동 파괴 |
| ASC 접근 | 불가 | `Ability->GetAbilitySystemComponent()` |
| 예측 시스템 | 없음 | `PredictionKey` 참여 가능 |
| 동시 실행 제한 | 없음 | 전체 1000개 하드코딩 |
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

#### AbilityTask는 GA 종료 시 어떻게 자동으로 정리되는가?

`EndAbility()` 호출 시 GA가 소유한 모든 AbilityTask에 `TaskOwnerEnded()`를 보내 전부 정리한다. `OnDestroy()` 내부에서 `Ability->TaskEnded(this)`를 호출해 GA에 알린다.

#### AbilityTask에서 델리게이트를 브로드캐스트하기 전 왜 ShouldBroadcastAbilityTaskDelegates()를 체크해야 하는가?

```cpp
void UMyAbilityTask::OnSomethingHappened()
{
    if (ShouldBroadcastAbilityTaskDelegates())  // GA가 살아있을 때만 true
    {
        OnCompleted.Broadcast(...);
    }
    EndTask();
}
```

GA가 이미 종료됐으면 `false`를 반환한다. 이 체크 없이 브로드캐스트하면 종료된 GA를 향한 콜백이 실행될 수 있다.

#### SetWaitingOnAvatar()는 언제, 왜 호출해야 하는가?

```cpp
void UMyAbilityTask::Activate()
{
    SetWaitingOnAvatar();  // AvatarActor가 아직 준비되지 않았으면 대기 상태로 전환
}
```

서버에서 GA가 먼저 활성화됐을 때 AvatarActor가 아직 없는 엣지케이스를 방어한다. Lyra의 Interaction 태스크가 `Activate()` 첫 줄에 이 호출을 사용한다.

---

### GA 안에서 비동기 작업이 필요할 때 UGameplayTask와 UAbilityTask 중 무엇을 써야 하는가?

| 상황 | 선택 |
|---|---|
| GA 안에서 비동기 작업 | `UAbilityTask` |
| AI BehaviorTree에서 비동기 작업 | `UGameplayTask` (GAS 없이) |
| GA 수명과 무관하게 독립 실행 | `UGameplayTask` |
| ASC/AvatarActor/PredictionKey 접근 필요 | `UAbilityTask` |

GA 안이라면 항상 `UAbilityTask`를 쓰는 게 맞다.
