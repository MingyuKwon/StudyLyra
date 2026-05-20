# UAbilityTask_WaitTargetData 구현 분석

> 출처: `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitTargetData.cpp`  
>        `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_WaitTargetData.h`

---

## UAbilityTask_WaitTargetData의 두 가지 생성 경로는 어떻게 다른가?

```cpp
// 경로 A: TargetClass 기반 — Blueprint 노드에서 Deferred Spawn 처리
UAbilityTask_WaitTargetData* WaitTargetData(
    UGameplayAbility* OwningAbility,
    FName TaskInstanceName,
    EGameplayTargetingConfirmation::Type ConfirmationType,
    TSubclassOf<AGameplayAbilityTargetActor> InTargetClass);

// 경로 B: 이미 존재하는 TargetActor 재사용
UAbilityTask_WaitTargetData* WaitTargetDataUsingActor(
    UGameplayAbility* OwningAbility,
    FName TaskInstanceName,
    EGameplayTargetingConfirmation::Type ConfirmationType,
    AGameplayAbilityTargetActor* InTargetActor);
```

- **경로 A**: `Activate()`에서 아무것도 하지 않는다. BP 노드가 `BeginSpawningActor` → `FinishSpawningActor` 순서로 수동 호출한다.
- **경로 B**: `Activate()`가 직접 TargetActor를 초기화하고 시작한다.

---

## TargetActor 재사용 경로에서 Activate()는 어떻게 처리하는가?

```cpp
void UAbilityTask_WaitTargetData::Activate()
{
    if (Ability && (TargetClass == nullptr))
    {
        if (TargetActor)
        {
            TargetClass = SpawnedActor->GetClass();
            RegisterTargetDataCallbacks();

            if (ShouldSpawnTargetActor())
            {
                InitializeTargetActor(SpawnedActor);
                FinalizeTargetActor(SpawnedActor);
            }
            else
            {
                // 서버이면 Actor 파괴
                TargetActor = nullptr;
                SpawnedActor->Destroy();
            }
        }
        else
        {
            EndTask();
        }
    }
}
```

---

## 클래스 기반 경로에서 BeginSpawningActor와 FinishSpawningActor는 어떤 순서로 동작하는가?

Blueprint의 latent 실행 핀 구조:

```
[WaitTargetData 노드]
  ├─ BeginSpawningActor ──────► [TargetActor 속성 설정 가능]
  └─ FinishSpawningActor ─────► [실제 스폰 완료 + 활성화]
```

`BeginSpawningActor`: Deferred Spawn(`SpawnActorDeferred`)으로 Actor를 생성한다. `BeginPlay`는 아직 호출되지 않으므로, 두 함수 사이에서 Blueprint가 속성을 설정할 수 있다. 서버는 스폰하지 않고 `RegisterTargetDataCallbacks()`만 호출한다.

`FinishSpawningActor`: `FinishSpawning()`으로 `BeginPlay`를 호출하고, `FinalizeTargetActor()`로 조준을 시작한다.

---

## ShouldSpawnTargetActor()는 서버와 로컬 클라이언트를 어떻게 구분하여 스폰을 결정하는가?

```cpp
bool UAbilityTask_WaitTargetData::ShouldSpawnTargetActor() const
{
    const bool bReplicates = CDO->GetIsReplicated();
    const bool bIsLocallyControlled = Ability->GetCurrentActorInfo()->IsLocallyControlled();
    const bool bShouldProduceTargetDataOnServer = CDO->ShouldProduceTargetDataOnServer;

    return (bReplicates || bIsLocallyControlled || bShouldProduceTargetDataOnServer);
}
```

기본값(`bIsReplicated=false`, `ShouldProduceTargetDataOnServer=false`) 기준:

| 실행 위치 | bIsLocallyControlled | 결과 |
|-----------|----------------------|------|
| 로컬 클라이언트 | true | 스폰 O |
| 서버 (원격 클라) | false | 스폰 X |

---

## InitializeTargetActor()에서 PlayerController 주입과 콜백 등록이 이루어지는 이유는?

```cpp
void UAbilityTask_WaitTargetData::InitializeTargetActor(AGameplayAbilityTargetActor* SpawnedActor) const
{
    SpawnedActor->PrimaryPC = Ability->GetCurrentActorInfo()->PlayerController.Get();

    SpawnedActor->TargetDataReadyDelegate.AddUObject(this, &OnTargetDataReadyCallback);
    SpawnedActor->CanceledDelegate.AddUObject(this, &OnTargetDataCancelledCallback);
}
```

콜백 등록은 `InitializeTargetActor`에서 한다. `FinalizeTargetActor`가 아니다.

---

## FinalizeTargetActor()에서 ConfirmationType에 따라 어떻게 다르게 동작하는가?

```cpp
void UAbilityTask_WaitTargetData::FinalizeTargetActor(AGameplayAbilityTargetActor* SpawnedActor) const
{
    ASC->SpawnedTargetActors.Push(SpawnedActor);
    SpawnedActor->StartTargeting(Ability);

    if (SpawnedActor->ShouldProduceTargetData())
    {
        if (ConfirmationType == EGameplayTargetingConfirmation::Instant)
            SpawnedActor->ConfirmTargeting();  // 즉시 확정
        else if (ConfirmationType == EGameplayTargetingConfirmation::UserConfirmed)
            SpawnedActor->BindToConfirmCancelInputs();  // 입력 대기
    }
}
```

---

## 서버에서 RegisterTargetDataCallbacks()가 클라이언트 RPC를 어떻게 기다리는가?

```cpp
void UAbilityTask_WaitTargetData::RegisterTargetDataCallbacks()
{
    if (!bIsLocallyControlled && !bShouldProduceTargetDataOnServer)
    {
        ASC->AbilityTargetDataSetDelegate(SpecHandle, ActivationPredictionKey)
           .AddUObject(this, &OnTargetDataReplicatedCallback);
        ASC->AbilityTargetDataCancelledDelegate(SpecHandle, ActivationPredictionKey)
           .AddUObject(this, &OnTargetDataReplicatedCancelledCallback);

        // RPC가 이미 도착해 있으면 즉시 처리
        ASC->CallReplicatedTargetDataDelegatesIfSet(SpecHandle, ActivationPredictionKey);
        SetWaitingOnRemotePlayerData();
    }
}
```

---

## OnTargetDataReadyCallback()에서 클라이언트는 TargetData를 서버로 어떻게 전송하는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReadyCallback(const FGameplayAbilityTargetDataHandle& Data)
{
    FScopedPredictionWindow ScopedPrediction(ASC, ShouldReplicateDataToServer());

    if (IsPredictingClient())
    {
        if (!TargetActor->ShouldProduceTargetDataOnServer)
            // TargetData 전체를 서버에 RPC 전송
            ASC->CallServerSetReplicatedTargetData(
                GetAbilitySpecHandle(), GetActivationPredictionKey(),
                Data, ApplicationTag, ASC->ScopedPredictionKey);
        else if (ConfirmationType == EGameplayTargetingConfirmation::UserConfirmed)
            // 서버가 직접 생성하는 경우: "확인했음" 신호만 전송
            ASC->ServerSetReplicatedEvent(EAbilityGenericReplicatedEvent::GenericConfirm, ...);
    }

    if (ShouldBroadcastAbilityTaskDelegates())
        ValidData.Broadcast(Data);  // 클라이언트 로컬 즉시 처리

    if (ConfirmationType != EGameplayTargetingConfirmation::CustomMulti)
        EndTask();
}
```

`ShouldProduceTargetDataOnServer=true`면 TargetData를 보내지 않고 `GenericConfirm` 이벤트만 보낸다. 서버가 직접 트레이스·검증해서 TargetData를 만들기 때문이다.

---

## 서버가 클라이언트 TargetData를 수신했을 때 OnTargetDataReplicatedCallback()은 어떻게 검증하는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReplicatedCallback(
    const FGameplayAbilityTargetDataHandle& Data, FGameplayTag ActivationTag)
{
    ASC->ConsumeClientReplicatedTargetData(GetAbilitySpecHandle(), GetActivationPredictionKey());

    // TargetActor가 있으면 서버 측 검증 기회 부여
    if (TargetActor && !TargetActor->OnReplicatedTargetDataReceived(MutableData))
        Cancelled.Broadcast(MutableData);  // TargetActor가 거부
    else
        ValidData.Broadcast(MutableData);  // 정상 처리

    if (ConfirmationType != EGameplayTargetingConfirmation::CustomMulti)
        EndTask();
}
```

---

## ConfirmationType에 따라 WaitTargetData Task의 동작과 종료 조건은 어떻게 달라지는가?

| 값 | FinalizeTargetActor 처리 | Task 종료 조건 |
|----|--------------------------|----------------|
| `Instant` | `ConfirmTargeting()` 즉시 호출 | OnTargetDataReadyCallback 후 |
| `UserConfirmed` | `BindToConfirmCancelInputs()` | 플레이어 확인 입력 후 |
| `CustomTargeting` | 아무것도 하지 않음 (TargetActor가 직접 결정) | OnTargetDataReadyCallback 후 |
| `CustomMulti` | — | 자동 종료 없음 (여러 번 ValidData 가능) |

---

## 클래스 기반 경로에서 클라이언트·서버 양쪽의 전체 흐름은 어떻게 되는가?

```
[클라이언트]                                [서버]

BeginSpawningActor()                        BeginSpawningActor()
  ShouldSpawnTargetActor() → true             ShouldSpawnTargetActor() → false
  SpawnActorDeferred()                        RegisterTargetDataCallbacks()
  InitializeTargetActor()                       AbilityTargetDataSetDelegate 등록

(BP에서 TargetActor 속성 설정)

FinishSpawningActor()
  FinishSpawning() → BeginPlay
  FinalizeTargetActor()
    StartTargeting()
    Instant → ConfirmTargeting() 즉시

(플레이어 조준 / 조준 Actor 동작)

TargetActor.TargetDataReadyDelegate 발화
  OnTargetDataReadyCallback()
    CallServerSetReplicatedTargetData() ──RPC──► OnTargetDataReplicatedCallback()
    ValidData.Broadcast() (로컬 즉시)               ConsumeClientReplicatedTargetData()
    EndTask()                                        ValidData.Broadcast()
                                                     EndTask()
```

---

## Lyra의 히트스캔 무기가 WaitTargetData Task를 사용하지 않고 직접 구현하는 이유는?

| | WaitTargetData | Lyra 히트스캔 |
|--|----------------|---------------|
| TargetActor 스폰 | 매 발사마다 스폰/파괴 | 없음 |
| 조준 대기 | 가능 (`UserConfirmed`) | 불필요 (즉시 트레이스) |
| TargetData 전송 방식 | `CallServerSetReplicatedTargetData` | 동일 (직접 호출) |
| 콜백 등록 | Task 내부에서 TargetActor에 등록 | `AbilityTargetDataSetDelegate`에 직접 등록 |

발사 즉시 라인 트레이스가 완료되므로 TargetActor 스폰이 불필요하다. `OnTargetDataReadyCallback`을 직접 `AbilityTargetDataSetDelegate`에 등록하고, `StartRangedWeaponTargeting()`에서 트레이스 후 콜백을 직접 호출해 같은 흐름을 구현한다.
