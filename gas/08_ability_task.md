# AbilityTask

> 참고: [GAS Doc 캐시](gas_doc_cache.md) | 소스: `AbilityTask_GrantNearbyInteraction.h/cpp`

---

## 역할

GameplayAbility는 단일 프레임 내에서 실행된다. **시간이 걸리거나 외부 이벤트를 기다려야 하는 작업**은 AbilityTask로 처리한다.

사용 예시:
- 애니메이션 몽타주 완료 대기 (`PlayMontageAndWait`)
- 입력 이벤트 대기 (`WaitInputPress`, `WaitInputRelease`)
- 타겟 선택 대기 (`WaitTargetData`)
- 월드 오버랩 주기적 쿼리
- 근처 상호작용 가능 오브젝트 능력 부여

전역 동시 실행 한도: **1000개** (생성자에서 설정, 초과 시 가장 오래된 것 종료).

---

## 생명주기

```
GA::ActivateAbility()
    │
    ▼
AbilityTask::정적팩토리함수()  ← NewAbilityTask<T>() 호출, 파라미터 설정
    │
    ▼
Task->ReadyForActivation()
    │  C++: 수동 호출 필요
    │  Blueprint: K2Node_LatentGameplayTaskCall이 자동 호출
    │
    ▼
Task::Activate()             ← 실제 작업 시작 (델리게이트 바인딩, 타이머 설정 등)
    │
    ▼
[작업 진행 중]
    │ 완료 조건 충족 시
    ▼
델리게이트 브로드캐스트       ← GA가 바인딩한 콜백 실행
    │
    ▼
Task::OnDestroy()            ← 정리 (타이머 해제, 델리게이트 언바인딩)
```

### Tick 지원

```cpp
// 생성자에서
bTickingTask = true;

// 오버라이드
virtual void TickTask(float DeltaTime) override;
```

### Simulated Proxy 지원

기본적으로 GA를 실행하는 쪽(소유 클라이언트 또는 서버)에서만 AT 실행.
Simulated Proxy에서도 실행하려면:
```cpp
bSimulatedTask = true;
virtual void InitSimulatedTask(UGameplayTasksComponent& InGameplayTasksComponent) override;
// + 복제할 변수 추가
```

---

## 기본 사용 패턴

### C++에서 사용

```cpp
void UMyGameplayAbility::ActivateAbility(...)
{
    // 1. 팩토리 함수로 생성
    UMyAbilityTask* Task = UMyAbilityTask::CreateTask(this, Param1, Param2);
    
    // 2. 델리게이트 바인딩
    Task->OnCompleted.AddDynamic(this, &UMyGameplayAbility::OnTaskCompleted);
    Task->OnCancelled.AddDynamic(this, &UMyGameplayAbility::OnTaskCancelled);
    
    // 3. 활성화 (Blueprint는 자동, C++는 수동)
    Task->ReadyForActivation();
}
```

---

## 커스텀 AbilityTask 만들기

### 기본 구조

```cpp
UCLASS()
class UMyAbilityTask : public UAbilityTask
{
    GENERATED_BODY()

    // 완료 델리게이트
    UPROPERTY(BlueprintAssignable)
    FMyDelegate OnCompleted;

    // 팩토리 함수 (UFUNCTION + BlueprintCallable 필수)
    UFUNCTION(BlueprintCallable, Category = "Ability|Tasks",
        meta = (HidePin = "OwningAbility", DefaultToSelf = "OwningAbility",
                BlueprintInternalUseOnly = "TRUE"))
    static UMyAbilityTask* CreateTask(UGameplayAbility* OwningAbility, float Param);

    // 오버라이드
    virtual void Activate() override;
    virtual void OnDestroy(bool AbilityEnded) override;

private:
    float Param;
};
```

---

## Lyra 예시 — UAbilityTask_GrantNearbyInteraction

> 소스: `Interaction/Tasks/AbilityTask_GrantNearbyInteraction.h/cpp`

근처의 상호작용 가능 오브젝트를 주기적으로 스캔하고, 필요한 GA를 자동으로 부여한다.

```cpp
UCLASS()
class UAbilityTask_GrantNearbyInteraction : public UAbilityTask
{
    GENERATED_UCLASS_BODY()

    // 팩토리 함수
    static UAbilityTask_GrantNearbyInteraction* GrantAbilitiesForNearbyInteractors(
        UGameplayAbility* OwningAbility, 
        float InteractionScanRange,  // 스캔 반경
        float InteractionScanRate    // 스캔 주기(초)
    );

    virtual void Activate() override;
    virtual void OnDestroy(bool AbilityEnded) override;

private:
    void QueryInteractables();  // 실제 스캔 + 능력 부여 로직

    float InteractionScanRange = 100;
    float InteractionScanRate = 0.100;
    FTimerHandle QueryTimerHandle;
    TMap<FObjectKey, FGameplayAbilitySpecHandle> InteractionAbilityCache;
};
```

### Activate() 구현

```cpp
void UAbilityTask_GrantNearbyInteraction::Activate()
{
    SetWaitingOnAvatar();
    
    UWorld* World = GetWorld();
    World->GetTimerManager().SetTimer(
        QueryTimerHandle, 
        this, 
        &ThisClass::QueryInteractables, 
        InteractionScanRate, 
        true   // bLoop=true
    );
}
```

### QueryInteractables() 핵심 로직

```cpp
void UAbilityTask_GrantNearbyInteraction::QueryInteractables()
{
    // 1. 반경 내 오버랩 검색
    World->OverlapMultiByChannel(OverlapResults, 
        ActorOwner->GetActorLocation(), FQuat::Identity,
        Lyra_TraceChannel_Interaction,
        FCollisionShape::MakeSphere(InteractionScanRange), Params);

    // 2. IInteractableTarget 인터페이스 구현체 추출
    TArray<TScriptInterface<IInteractableTarget>> InteractableTargets;
    UInteractionStatics::AppendInteractableTargetsFromOverlapResults(OverlapResults, InteractableTargets);

    // 3. 각 대상에서 상호작용 옵션 수집
    TArray<FInteractionOption> Options;
    for (auto& Target : InteractableTargets)
    {
        FInteractionOptionBuilder Builder(Target, Options);
        Target->GatherInteractionOptions(InteractionQuery, Builder);
    }

    // 4. 필요한 GA를 아직 부여하지 않았다면 부여
    for (FInteractionOption& Option : Options)
    {
        if (Option.InteractionAbilityToGrant)
        {
            FObjectKey ObjectKey(Option.InteractionAbilityToGrant);
            if (!InteractionAbilityCache.Find(ObjectKey))
            {
                FGameplayAbilitySpec Spec(Option.InteractionAbilityToGrant, 1, INDEX_NONE, this);
                FGameplayAbilitySpecHandle Handle = AbilitySystemComponent->GiveAbility(Spec);
                InteractionAbilityCache.Add(ObjectKey, Handle);
            }
        }
    }
}
```

### OnDestroy() 정리

```cpp
void UAbilityTask_GrantNearbyInteraction::OnDestroy(bool AbilityEnded)
{
    if (UWorld* World = GetWorld())
    {
        World->GetTimerManager().ClearTimer(QueryTimerHandle);
    }
    Super::OnDestroy(AbilityEnded);
}
```

---

## 내장 AbilityTask 주요 목록

| Task 이름 | 기능 |
|---|---|
| `PlayMontageAndWait` | 애니메이션 재생 + 완료/취소 대기 (ASC 통해 복제) |
| `WaitGameplayEvent` | 특정 GameplayEvent 태그 대기 |
| `WaitInputPress` / `WaitInputRelease` | 입력 이벤트 대기 |
| `WaitTargetData` | TargetActor로 타겟 선택 + 데이터 수신 대기 |
| `WaitNetSync` | 서버-클라이언트 동기화 (새 Prediction Key 생성) |
| `WaitDelay` | 일정 시간 대기 |
| `SpawnActor` | 액터 스폰 (서버 전용) |

> `PlayMontageAndWait`를 쓰면 ASC를 통해 자동 복제된다.
> `UAnimInstance::PlayMontage` 직접 호출 시 복제 안 됨.
