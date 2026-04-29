# 커스텀 AbilityTask

> **GASDoc**: 4.7.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-definition"></a>
### 4.7.2 커스텀 AbilityTask

대부분의 경우 C++로 커스텀 `AbilityTask`를 직접 작성하게 된다. 샘플 프로젝트에는 두 가지 커스텀 `AbilityTask`가 포함되어 있다:
1. `PlayMontageAndWaitForEvent` — 기본 `AbilityTask`인 `PlayMontageAndWait`와 `WaitGameplayEvent`를 결합한 태스크다. 이를 통해 애니메이션 몽타주가 `AnimNotify`에서 해당 몽타주를 시작한 `GameplayAbility`로 게임플레이 이벤트를 역으로 전달할 수 있다. 애니메이션 몽타주의 특정 타이밍에 동작을 트리거할 때 활용한다.
2. `WaitReceiveDamage` — `OwnerActor`가 데미지를 받는 것을 감지하는 태스크다. 패시브 아머 스택 `GameplayAbility`에서 영웅이 데미지를 받을 때 아머 스택을 하나씩 제거하는 데 사용된다.

`AbilityTask`는 다음 요소들로 구성된다:
* `AbilityTask`의 새 인스턴스를 생성하는 정적(static) 함수
* 태스크가 목적을 완수했을 때 브로드캐스트되는 델리게이트
* 메인 작업을 시작하고 외부 델리게이트에 바인딩하는 `Activate()` 함수
* 외부 델리게이트 바인딩 해제를 포함한 정리 작업을 수행하는 `OnDestroy()` 함수
* 바인딩된 외부 델리게이트에 대한 콜백 함수
* 멤버 변수 및 내부 헬퍼 함수

> **참고**  
> `AbilityTask`는 출력 델리게이트를 한 가지 타입만 선언할 수 있다. 모든 출력 델리게이트는 파라미터 사용 여부와 관계없이 동일한 타입이어야 하며, 사용하지 않는 파라미터에는 기본값을 전달한다.

`AbilityTask`는 기본적으로 소유 `GameplayAbility`를 실행 중인 클라이언트 또는 서버에서만 동작한다. 단, `AbilityTask` 생성자에서 `bSimulatedTask = true`로 설정하고, `virtual void InitSimulatedTask(UGameplayTasksComponent& InGameplayTasksComponent)`를 오버라이드하며, 필요한 멤버 변수를 복제 설정하면 시뮬레이션 클라이언트에서도 실행할 수 있다. 이 방식은 모든 이동 변경 사항을 복제하는 대신 이동 `AbilityTask` 전체를 시뮬레이션하고 싶은 이동 관련 태스크 같은 드문 상황에서만 유용하다. 모든 `RootMotionSource` `AbilityTask`가 이 방식을 사용한다. 예시로 `AbilityTask_MoveToLocation.h/.cpp`를 참고하라.

`AbilityTask` 생성자에서 `bTickingTask = true`로 설정하고 `virtual void TickTask(float DeltaTime)`를 오버라이드하면 `AbilityTask`가 `Tick`을 수행할 수 있다. 프레임에 걸쳐 값을 부드럽게 보간(lerp)해야 할 때 유용하다. 예시로 `AbilityTask_MoveToLocation.h/.cpp`를 참고하라.

---

## 내 분석

### 커스텀 AbilityTask 기본 골격

GASDoc이 나열한 요소를 코드로 보면 이렇다.

```cpp
UCLASS()
class UMyAbilityTask : public UAbilityTask
{
    GENERATED_UCLASS_BODY()

    // ① 출력 델리게이트 — 태스크가 끝났을 때 GA에 알리는 수단
    UPROPERTY(BlueprintAssignable)
    FMyDelegate OnCompleted;

    // ② 정적 팩토리 함수 — NewAbilityTask<T> + 파라미터 세팅, ReadyForActivation은 호출하지 않음
    UFUNCTION(BlueprintCallable, ..., meta=(BlueprintInternalUseOnly="TRUE"))
    static UMyAbilityTask* CreateMyTask(UGameplayAbility* OwningAbility, float SomeParam);

    // ③ Activate() — 실제 작업 시작, 외부 델리게이트 바인딩
    virtual void Activate() override;

    // ④ OnDestroy() — 정리, 델리게이트 언바인딩. Super::OnDestroy() 마지막 호출 필수
    virtual void OnDestroy(bool AbilityEnded) override;

private:
    // ⑤ 콜백 — 바인딩한 외부 델리게이트가 발동될 때 호출
    void OnExternalEventFired();

    float SomeParam;
};
```

`meta=(BlueprintInternalUseOnly="TRUE")`를 달아야 Blueprint에서 잠재 노드로만 쓸 수 있고,
직접 호출을 막을 수 있다.

---

### Lyra 예시 1 — AbilityTask_GrantNearbyInteraction

> `Source/LyraGame/Interaction/Tasks/`

"완료"가 없는 **지속형 태스크**다. GA가 살아있는 동안 계속 주변을 감지해서 Ability를 부여한다.

```
GA 활성화
  └─ Task::Activate()
       └─ 타이머 등록 (InteractionScanRate마다 QueryInteractables)
            └─ 범위 안 오브젝트에 Ability 부여 (서버 권한 작업)

GA 종료
  └─ Task::OnDestroy()
       └─ 타이머 해제
```

```cpp
// 팩토리 함수 — 파라미터 세팅 후 return. ReadyForActivation은 호출자 몫
UAbilityTask_GrantNearbyInteraction* UAbilityTask_GrantNearbyInteraction::GrantAbilitiesForNearbyInteractors(
    UGameplayAbility* OwningAbility, float InteractionScanRange, float InteractionScanRate)
{
    UAbilityTask_GrantNearbyInteraction* MyObj = NewAbilityTask<UAbilityTask_GrantNearbyInteraction>(OwningAbility);
    MyObj->InteractionScanRange = InteractionScanRange;
    MyObj->InteractionScanRate  = InteractionScanRate;
    return MyObj;
}

void UAbilityTask_GrantNearbyInteraction::Activate()
{
    SetWaitingOnAvatar();   // AvatarActor가 준비될 때까지 대기
    World->GetTimerManager().SetTimer(QueryTimerHandle, this,
        &ThisClass::QueryInteractables, InteractionScanRate, true);
}

void UAbilityTask_GrantNearbyInteraction::OnDestroy(bool AbilityEnded)
{
    World->GetTimerManager().ClearTimer(QueryTimerHandle);
    Super::OnDestroy(AbilityEnded);   // 반드시 마지막에 호출
}
```

**설계 포인트**
- 출력 델리게이트가 없다 — 완료 신호 없이 GA가 끝날 때까지 돌아간다.
- `bTickingTask` 대신 타이머를 쓴다 — 매 프레임이 아니라 `InteractionScanRate` 간격으로만 쿼리하면 되기 때문이다.
- 서버 전용 — Ability 부여는 서버 권한 작업이므로 `bSimulatedTask` 불필요.

---

### Lyra 예시 2 — AbilityTask_WaitForInteractableTargets_SingleLineTrace

> `Source/LyraGame/Interaction/Tasks/`

주기적으로 라인 트레이스를 쏴서 인터랙션 가능한 오브젝트가 바뀌면 델리게이트를 브로드캐스트하는 태스크다.
추상 베이스 클래스를 상속해 트레이스 방식만 구현하는 **상속 분리 패턴**을 사용한다.

```
UAbilityTask
  └─ UAbilityTask_WaitForInteractableTargets          (추상 — 델리게이트, 공통 로직)
        └─ UAbilityTask_WaitForInteractableTargets_SingleLineTrace  (구체 — 라인 트레이스 구현)
```

```cpp
// 베이스 클래스가 소유한 출력 델리게이트
// (AbilityTask_WaitForInteractableTargets.h)
UPROPERTY(BlueprintAssignable)
FInteractableObjectsChangedEvent InteractableObjectsChanged;
```

```cpp
void UAbilityTask_WaitForInteractableTargets_SingleLineTrace::Activate()
{
    SetWaitingOnAvatar();
    World->GetTimerManager().SetTimer(TimerHandle, this,
        &ThisClass::PerformTrace, InteractionScanRate, true);
}

void UAbilityTask_WaitForInteractableTargets_SingleLineTrace::PerformTrace()
{
    // 라인 트레이스
    FHitResult OutHitResult;
    LineTrace(OutHitResult, World, TraceStart, TraceEnd, TraceProfile.Name, Params);

    // 결과를 베이스 클래스의 UpdateInteractableOptions()에 위임
    // → 이전과 달라졌을 때만 InteractableObjectsChanged 브로드캐스트
    TArray<TScriptInterface<IInteractableTarget>> InteractableTargets;
    UInteractionStatics::AppendInteractableTargetsFromHitResult(OutHitResult, InteractableTargets);
    UpdateInteractableOptions(InteractionQuery, InteractableTargets);
}
```

**설계 포인트**
- 델리게이트가 베이스 클래스에 있다 — 트레이스 방식(단일/다중/오버랩 등)이 바뀌어도 GA 쪽 바인딩 코드는 바꿀 필요가 없다.
- 변경 감지는 베이스의 `UpdateInteractableOptions()`가 담당 — 결과가 같으면 브로드캐스트하지 않아 불필요한 업데이트를 막는다.
- 완료 없는 루프 태스크 + 델리게이트 패턴 — "끝났다"를 알리는 것이 아니라 "뭔가 바뀌었다"를 계속 알린다.

---

### 두 패턴 비교

| | AbilityTask_GrantNearbyInteraction | AbilityTask_WaitForInteractableTargets |
|---|---|---|
| 출력 델리게이트 | 없음 (지속 실행) | 있음 (`InteractableObjectsChanged`) |
| 종료 시점 | GA 종료 시 | GA 종료 시 |
| 주기 실행 방법 | Timer | Timer |
| 서버/클라 | 서버 전용 | Owning Client (트레이스) |
| 상속 구조 | 단일 클래스 | 추상 베이스 + 구체 구현 분리 |
