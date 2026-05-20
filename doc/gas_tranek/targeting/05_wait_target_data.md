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

- **경로 A**: `TargetClass != null`, `TargetActor = null`. `Activate()`는 아무것도 안 하고, BP 노드가 `BeginSpawningActor` → `FinishSpawningActor` 순서로 수동 호출한다.
- **경로 B**: `TargetClass = null`, `TargetActor != null`. `Activate()`가 직접 처리한다.

---

## TargetActor 재사용 경로에서 Activate()는 어떻게 처리하는가?

```cpp
void UAbilityTask_WaitTargetData::Activate()
{
    // TargetClass가 없을 때만 진입 — 경로 A(클래스 기반)에서는 호출되지 않음
    if (Ability && (TargetClass == nullptr))
    {
        if (TargetActor)
        {
            AGameplayAbilityTargetActor* SpawnedActor = TargetActor;
            TargetClass = SpawnedActor->GetClass();  // ShouldSpawnTargetActor에서 check() 통과용

            RegisterTargetDataCallbacks();  // 서버: 클라 RPC 대기 등록

            if (!IsValidChecked(this))
                return;

            if (ShouldSpawnTargetActor())
            {
                // 로컬 클라이언트 → Actor 초기화 + 시작
                InitializeTargetActor(SpawnedActor);
                FinalizeTargetActor(SpawnedActor);
            }
            else
            {
                // 서버인데 Actor가 이미 넘어온 경우 → 파괴
                TargetActor = nullptr;
                SpawnedActor->Destroy();
            }
        }
        else
        {
            EndTask();  // TargetActor도 없으면 즉시 종료
        }
    }
    // TargetClass != null (경로 A)이면 Activate에서 아무것도 하지 않는다
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

```cpp
bool UAbilityTask_WaitTargetData::BeginSpawningActor(
    UGameplayAbility* OwningAbility,
    TSubclassOf<AGameplayAbilityTargetActor> InTargetClass,
    AGameplayAbilityTargetActor*& SpawnedActor)
{
    SpawnedActor = nullptr;

    if (Ability)
    {
        if (ShouldSpawnTargetActor())
        {
            // Deferred Spawn — FinishSpawning 전까지 BeginPlay 호출 안 됨
            SpawnedActor = World->SpawnActorDeferred<AGameplayAbilityTargetActor>(
                Class, FTransform::Identity, nullptr, nullptr,
                ESpawnActorCollisionHandlingMethod::AlwaysSpawn);

            if (SpawnedActor)
            {
                TargetActor = SpawnedActor;
                InitializeTargetActor(SpawnedActor);  // PlayerController + 콜백 등록
            }
        }

        RegisterTargetDataCallbacks();  // 서버: RPC 대기 등록 (항상 호출)
    }

    return (SpawnedActor != nullptr);
}
```

```cpp
void UAbilityTask_WaitTargetData::FinishSpawningActor(
    UGameplayAbility* OwningAbility,
    AGameplayAbilityTargetActor* SpawnedActor)
{
    if (ASC && IsValid(SpawnedActor))
    {
        const FTransform SpawnTransform = ASC->GetOwner()->GetTransform();
        SpawnedActor->FinishSpawning(SpawnTransform);  // BeginPlay 호출

        FinalizeTargetActor(SpawnedActor);  // SpawnedTargetActors 등록 + 시작
    }
}
```

두 함수 사이에서 Blueprint가 SpawnedActor의 속성(범위, 채널 등)을 설정할 수 있다.

---

## ShouldSpawnTargetActor()는 서버와 로컬 클라이언트를 어떻게 구분하여 스폰을 결정하는가?

```cpp
bool UAbilityTask_WaitTargetData::ShouldSpawnTargetActor() const
{
    const AGameplayAbilityTargetActor* CDO = CastChecked<AGameplayAbilityTargetActor>(TargetClass->GetDefaultObject());

    const bool bReplicates = CDO->GetIsReplicated();
    const bool bIsLocallyControlled = Ability->GetCurrentActorInfo()->IsLocallyControlled();
    const bool bShouldProduceTargetDataOnServer = CDO->ShouldProduceTargetDataOnServer;

    return (bReplicates || bIsLocallyControlled || bShouldProduceTargetDataOnServer);
}
```

기본값(`bIsReplicated=false`, `ShouldProduceTargetDataOnServer=false`):

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

    // TargetActor → Task 콜백 연결
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
    // SpawnedTargetActors에 등록 — GA가 끝날 때 일괄 정리
    ASC->SpawnedTargetActors.Push(SpawnedActor);

    SpawnedActor->StartTargeting(Ability);  // 조준 로직 시작

    if (SpawnedActor->ShouldProduceTargetData())
    {
        if (ConfirmationType == EGameplayTargetingConfirmation::Instant)
        {
            // 즉시 확정 — 조준 대기 없이 바로 TargetData 반환
            SpawnedActor->ConfirmTargeting();
        }
        else if (ConfirmationType == EGameplayTargetingConfirmation::UserConfirmed)
        {
            // 플레이어 입력(GA_Confirm) 대기
            SpawnedActor->BindToConfirmCancelInputs();
        }
    }
}
```

---

## 서버에서 RegisterTargetDataCallbacks()가 클라이언트 RPC를 어떻게 기다리는가?

```cpp
void UAbilityTask_WaitTargetData::RegisterTargetDataCallbacks()
{
    const bool bIsLocallyControlled = Ability->GetCurrentActorInfo()->IsLocallyControlled();
    const bool bShouldProduceTargetDataOnServer = CDO->ShouldProduceTargetDataOnServer;

    if (!bIsLocallyControlled)
    {
        if (!bShouldProduceTargetDataOnServer)
        {
            // 서버: 클라이언트 RPC 수신 콜백 등록
            ASC->AbilityTargetDataSetDelegate(SpecHandle, ActivationPredictionKey)
               .AddUObject(this, &OnTargetDataReplicatedCallback);
            ASC->AbilityTargetDataCancelledDelegate(SpecHandle, ActivationPredictionKey)
               .AddUObject(this, &OnTargetDataReplicatedCancelledCallback);

            // RPC가 이미 도착해 있으면 즉시 처리 (타이밍 경쟁 방지)
            ASC->CallReplicatedTargetDataDelegatesIfSet(SpecHandle, ActivationPredictionKey);

            SetWaitingOnRemotePlayerData();
        }
    }
}
```

`AbilityTargetDataCancelledDelegate`도 등록한다 — 클라이언트가 취소를 RPC로 보낼 경우.

---

## OnTargetDataReadyCallback()에서 클라이언트는 TargetData를 서버로 어떻게 전송하는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReadyCallback(
    const FGameplayAbilityTargetDataHandle& Data)
{
    FScopedPredictionWindow ScopedPrediction(ASC, ShouldReplicateDataToServer());

    if (IsPredictingClient())
    {
        if (!TargetActor->ShouldProduceTargetDataOnServer)
        {
            // 일반 경우: TargetData 전체를 서버에 RPC 전송
            ASC->CallServerSetReplicatedTargetData(
                GetAbilitySpecHandle(), GetActivationPredictionKey(),
                Data, ApplicationTag, ASC->ScopedPredictionKey);
        }
        else if (ConfirmationType == EGameplayTargetingConfirmation::UserConfirmed)
        {
            // 서버가 직접 TargetData 생성하는 경우:
            // TargetData 대신 "확인했음" 신호만 전송
            ASC->ServerSetReplicatedEvent(
                EAbilityGenericReplicatedEvent::GenericConfirm,
                GetAbilitySpecHandle(), GetActivationPredictionKey(),
                ASC->ScopedPredictionKey);
        }
    }

    if (ShouldBroadcastAbilityTaskDelegates())
        ValidData.Broadcast(Data);  // 클라이언트 로컬 즉시 처리

    if (ConfirmationType != EGameplayTargetingConfirmation::CustomMulti)
        EndTask();
}
```

`ShouldProduceTargetDataOnServer=true`면 TargetData를 보내지 않고 **GenericConfirm 이벤트만** 보낸다.  
서버가 직접 트레이스/검증해서 TargetData를 만들기 때문이다.

---

## 클라이언트가 타게팅을 취소했을 때 서버에는 어떻게 통보되는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataCancelledCallback(
    const FGameplayAbilityTargetDataHandle& Data)
{
    FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient());

    if (IsPredictingClient())
    {
        if (!TargetActor->ShouldProduceTargetDataOnServer)
            ASC->ServerSetReplicatedTargetDataCancelled(
                GetAbilitySpecHandle(), GetActivationPredictionKey(), ASC->ScopedPredictionKey);
        else
            ASC->ServerSetReplicatedEvent(EAbilityGenericReplicatedEvent::GenericCancel, ...);
    }

    Cancelled.Broadcast(Data);
    EndTask();
}
```

---

## 서버가 클라이언트 TargetData를 수신했을 때 OnTargetDataReplicatedCallback()은 어떻게 검증하는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReplicatedCallback(
    const FGameplayAbilityTargetDataHandle& Data, FGameplayTag ActivationTag)
{
    FGameplayAbilityTargetDataHandle MutableData = Data;

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

## 서버가 클라이언트 취소 신호를 수신했을 때 어떻게 처리하는가?

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReplicatedCancelledCallback()
{
    if (ShouldBroadcastAbilityTaskDelegates())
        Cancelled.Broadcast(FGameplayAbilityTargetDataHandle());
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
| `CustomMulti` | — | **자동 종료 없음** (여러 번 ValidData 가능) |

---

## 클래스 기반 경로에서 클라이언트·서버 양쪽의 전체 흐름은 어떻게 되는가?

```
[클라이언트]                                [서버]

BeginSpawningActor()                        BeginSpawningActor()
  ShouldSpawnTargetActor() → true             ShouldSpawnTargetActor() → false
  SpawnActorDeferred()                        RegisterTargetDataCallbacks()
  InitializeTargetActor()                       AbilityTargetDataSetDelegate 등록
    TargetDataReady/Cancelled 콜백 연결

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

Lyra는 발사 즉시 라인 트레이스가 완료되기 때문에 TargetActor 스폰이 불필요하다.  
`OnTargetDataReadyCallback`을 직접 `AbilityTargetDataSetDelegate`에 등록하고,  
`StartRangedWeaponTargeting()`에서 트레이스 후 콜백을 직접 호출하는 방식으로 같은 흐름을 구현한다.
