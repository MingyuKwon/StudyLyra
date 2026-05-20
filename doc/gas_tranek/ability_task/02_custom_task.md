# 커스텀 AbilityTask

> **GASDoc**: 4.7.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-at-definition"></a>
### 커스텀 AbilityTask를 만들 때 어떤 구성 요소가 반드시 필요한가?

| 구성 요소 | 역할 |
|---|---|
| 정적 팩토리 함수 | 새 인스턴스 생성 + 파라미터 세팅 |
| 출력 델리게이트 | 태스크 완료 시 GA에 알리는 수단 |
| `Activate()` | 실제 작업 시작, 외부 델리게이트 바인딩 |
| `OnDestroy()` | 외부 델리게이트 언바인딩 등 정리 |
| 콜백 함수 | 바인딩한 외부 델리게이트가 발동할 때 호출 |

**주의사항**
- 출력 델리게이트는 한 가지 타입만 선언할 수 있다. 파라미터를 쓰지 않는 델리게이트에는 기본값을 전달한다.
- 기본적으로 소유 GA를 실행하는 클라이언트 또는 서버에서만 동작한다. 생성자에서 `bSimulatedTask = true`로 설정하고 `InitSimulatedTask()`를 오버라이드하면 시뮬레이션 클라이언트에서도 실행할 수 있다.
- 틱이 필요하면 생성자에서 `bTickingTask = true`로 설정하고 `TickTask(float DeltaTime)`을 오버라이드한다.

---

### 커스텀 AbilityTask의 기본 구조는 어떻게 생겼는가?

```cpp
UCLASS()
class UMyAbilityTask : public UAbilityTask
{
    GENERATED_UCLASS_BODY()

    // ① 출력 델리게이트
    UPROPERTY(BlueprintAssignable)
    FMyDelegate OnCompleted;

    // ② 정적 팩토리 함수 — NewAbilityTask<T> + 파라미터 세팅
    UFUNCTION(BlueprintCallable, ..., meta=(BlueprintInternalUseOnly="TRUE"))
    static UMyAbilityTask* CreateMyTask(UGameplayAbility* OwningAbility, float SomeParam);

    // ③ Activate() — 실제 작업 시작, 외부 델리게이트 바인딩
    virtual void Activate() override;

    // ④ OnDestroy() — 정리, 델리게이트 언바인딩. Super::OnDestroy() 마지막 호출 필수
    virtual void OnDestroy(bool AbilityEnded) override;

private:
    // ⑤ 콜백
    void OnExternalEventFired();

    float SomeParam;
};
```

`meta=(BlueprintInternalUseOnly="TRUE")`를 달아야 Blueprint에서 잠재 노드로만 쓸 수 있고 직접 호출을 막을 수 있다.

---

### 완료 신호 없이 GA가 살아있는 동안 계속 실행되는 지속형 AbilityTask는 어떻게 설계하는가?

> `Source/LyraGame/Interaction/Tasks/`

`AbilityTask_GrantNearbyInteraction`이 대표 예시다. GA가 살아있는 동안 주기적으로 범위 내 오브젝트에 Ability를 부여하는 지속형 태스크다.

```cpp
// 팩토리 함수 — 파라미터 세팅 후 return
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
    SetWaitingOnAvatar();
    World->GetTimerManager().SetTimer(QueryTimerHandle, this,
        &ThisClass::QueryInteractables, InteractionScanRate, true);
}

void UAbilityTask_GrantNearbyInteraction::OnDestroy(bool AbilityEnded)
{
    World->GetTimerManager().ClearTimer(QueryTimerHandle);
    Super::OnDestroy(AbilityEnded);   // 반드시 마지막에 호출
}
```

설계 포인트:
- 출력 델리게이트 없음 — GA가 끝날 때까지 계속 돌아간다
- `bTickingTask` 대신 타이머 사용 — 매 프레임이 아닌 `InteractionScanRate` 간격으로만 실행
- 서버 전용 — Ability 부여는 서버 권한 작업이므로 `bSimulatedTask` 불필요

---

### 상속으로 트레이스 방식만 교체할 수 있는 AbilityTask 계층은 어떻게 설계하는가?

> `Source/LyraGame/Interaction/Tasks/`

`AbilityTask_WaitForInteractableTargets`는 추상 베이스 클래스를 상속해 트레이스 방식만 구현하는 패턴을 사용한다.

```
UAbilityTask
  └─ UAbilityTask_WaitForInteractableTargets          (추상 — 델리게이트, 공통 로직)
        └─ UAbilityTask_WaitForInteractableTargets_SingleLineTrace  (구체 — 라인 트레이스 구현)
```

```cpp
// 구체 클래스 — 트레이스 실행 후 베이스 UpdateInteractableOptions()에 위임
void UAbilityTask_WaitForInteractableTargets_SingleLineTrace::PerformTrace()
{
    FHitResult OutHitResult;
    LineTrace(OutHitResult, World, TraceStart, TraceEnd, TraceProfile.Name, Params);

    TArray<TScriptInterface<IInteractableTarget>> InteractableTargets;
    UInteractionStatics::AppendInteractableTargetsFromHitResult(OutHitResult, InteractableTargets);
    UpdateInteractableOptions(InteractionQuery, InteractableTargets);  // 결과가 달라졌을 때만 델리게이트 브로드캐스트
}
```

설계 포인트:
- 델리게이트(`InteractableObjectsChanged`)가 베이스 클래스에 있어 트레이스 방식이 바뀌어도 GA 쪽 바인딩 코드는 수정 불필요
- 변경 감지는 베이스의 `UpdateInteractableOptions()`가 담당 — 결과가 같으면 브로드캐스트하지 않음

---

### "완료 없는 지속 루프"와 "변화 감지 델리게이트" 패턴은 어떤 차이가 있는가?

| | AbilityTask_GrantNearbyInteraction | AbilityTask_WaitForInteractableTargets |
|---|---|---|
| 출력 델리게이트 | 없음 (지속 실행) | 있음 (`InteractableObjectsChanged`) |
| 종료 시점 | GA 종료 시 | GA 종료 시 |
| 주기 실행 방법 | Timer | Timer |
| 서버/클라 | 서버 전용 | Owning Client (트레이스) |
| 상속 구조 | 단일 클래스 | 추상 베이스 + 구체 구현 분리 |
