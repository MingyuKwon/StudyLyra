# UAbilityTask_WaitTargetData 구현 분석

> 출처: `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitTargetData.cpp`  
>        `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_WaitTargetData.h`

---

## 개요

`UAbilityTask_WaitTargetData`는 `AGameplayAbilityTargetActor`를 스폰(또는 재사용)하고,  
TargetData가 준비됐을 때 `ValidData` / `Cancelled` delegate를 브로드캐스트하는 AbilityTask다.

```
GA (Ability) ──activate──► WaitTargetData Task
                                 │
                         TargetActor 스폰
                                 │
                     플레이어 조준/확인 대기
                                 │
              ┌──────────────────┴──────────────────┐
           클라이언트                             서버
        OnTargetDataReadyCallback          OnTargetDataReplicatedCallback
          ValidData.Broadcast()              ValidData.Broadcast()
          CallServerSetReplicatedTargetData ◄─── (클라 RPC 수신)
```

---

## ConfirmationType — Task 종료 조건

`CreateWaitTargetData()`의 첫 번째 핵심 파라미터.

| 값 | 의미 |
|----|------|
| `Instant` | TargetActor가 즉시 TargetData를 반환. 조준 UI 없이 바로 확정. |
| `UserConfirmed` | 플레이어가 별도 확인 입력(GA_Confirm 등)을 해야 TargetData 반환. 조준 UI 표시 중 대기. |
| `CustomTargeting` | TargetActor가 자체 로직으로 완료 시점을 결정. |
| `CustomMulti` | 여러 번 ValidData 브로드캐스트 가능. **Task가 자동 종료되지 않는다.** |

---

## Activate — 전체 흐름

```cpp
void UAbilityTask_WaitTargetData::Activate()
{
    if (ShouldSpawnTargetActor())
    {
        // 1. TargetActor 스폰 또는 재사용
        SpawnTargetActor();             // Deferred Spawn 방식
        InitializeTargetActor();        // TargetActor에 AbilityInfo 주입
        FinalizeTargetActor(SpawnedActor);  // FinishSpawning → 콜백 연결 → Confirm 처리
    }
    else
    {
        // 서버 단순 대기 경로
        RegisterTargetDataCallbacks();
    }
}
```

`SpawnTargetActor()`와 `FinalizeTargetActor()`가 분리된 이유:  
`UGameplayAbility::BeginSpawningActor` / `EndSpawningActor` 쌍으로 **Deferred Spawn**을 지원하기 위함.  
Blueprint에서 스폰 도중 TargetActor 속성을 설정할 수 있다.

---

## ShouldSpawnTargetActor — 서버는 스폰하지 않는다

```cpp
bool UAbilityTask_WaitTargetData::ShouldSpawnTargetActor() const
{
    const UGameplayAbilityTargetActor* CDO = TargetClass->GetDefaultObject<UGameplayAbilityTargetActor>();
    const bool bReplicates = CDO->GetIsReplicated();
    const bool bIsLocallyControlled = Ability->GetCurrentActorInfo()->IsLocallyControlled();
    const bool bShouldProduceTargetDataOnServer = CDO->ShouldProduceTargetDataOnServer;

    // 로컬 클라이언트이거나, TargetActor가 복제되거나, 서버 생성 옵션이면 스폰
    return (bReplicates || bIsLocallyControlled || bShouldProduceTargetDataOnServer);
}
```

기본 설정에서 `bIsReplicated = false`, `ShouldProduceTargetDataOnServer = false`이므로:

- **클라이언트** → `bIsLocallyControlled = true` → **TargetActor 스폰 O**
- **서버** → 세 조건 모두 false → **TargetActor 스폰 X** → `RegisterTargetDataCallbacks()`로 진입

서버에 불필요한 Actor를 스폰하지 않아 성능을 절약한다.

---

## FinalizeTargetActor — 콜백 연결

```cpp
void UAbilityTask_WaitTargetData::FinalizeTargetActor(AGameplayAbilityTargetActor* SpawnedActor) const
{
    // TargetActor → Task 콜백 연결
    SpawnedActor->TargetDataReadyDelegate.AddUObject(
        this, &UAbilityTask_WaitTargetData::OnTargetDataReadyCallback);
    SpawnedActor->CancelledDelegate.AddUObject(
        this, &UAbilityTask_WaitTargetData::OnTargetDataCancelledCallback);

    // ConfirmationType에 따라 즉시 확인하거나 입력 대기
    MyAbilityComponent->SpawnedTargetActors.Push(SpawnedActor);
    SpawnedActor->StartTargeting(Ability);
    SpawnedActor->BindToConfirmCancelInputs();
}
```

`BindToConfirmCancelInputs()`: TargetActor가 GA_Confirm / GA_Cancel 입력을 직접 구독한다.  
`UserConfirmed` 타입이면 이 구독이 의미 있고, `Instant`라면 `StartTargeting`에서 즉시 `ConfirmTargetingAndContinue()`가 호출된다.

---

## RegisterTargetDataCallbacks — 서버 대기 경로

```cpp
void UAbilityTask_WaitTargetData::RegisterTargetDataCallbacks()
{
    const bool bIsLocallyControlled = Ability->GetCurrentActorInfo()->IsLocallyControlled();
    const bool bShouldProduceTargetDataOnServer = /* TargetActor CDO */->ShouldProduceTargetDataOnServer;

    if (!bIsLocallyControlled)
    {
        if (!bShouldProduceTargetDataOnServer)
        {
            // 서버: 클라이언트가 RPC로 보낼 TargetData를 기다린다
            ASC->AbilityTargetDataSetDelegate(SpecHandle, ActivationPredictionKey)
               .AddUObject(this, &ThisClass::OnTargetDataReplicatedCallback);

            // 클라이언트 RPC가 이미 도착했을 경우 즉시 처리
            ASC->CallReplicatedTargetDataDelegatesIfSet(SpecHandle, ActivationPredictionKey);

            SetWaitingOnRemotePlayerData();
        }
    }
}
```

**핵심**: 서버는 `AbilityTargetDataSetDelegate`에 콜백을 등록하고 대기한다.  
`CallReplicatedTargetDataDelegatesIfSet`: 이미 RPC가 도착해 맵에 저장돼 있으면 즉시 콜백을 실행한다 (타이밍 경쟁 방지).

---

## OnTargetDataReadyCallback — 클라이언트가 서버에 전송

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReadyCallback(
    const FGameplayAbilityTargetDataHandle& Data)
{
    UAbilitySystemComponent* ASC = AbilitySystemComponent.Get();

    if (IsPredictingClient())
    {
        // 서버 생성 모드가 아니면 TargetData를 서버로 RPC 전송
        if (!TargetActor->ShouldProduceTargetDataOnServer)
        {
            ASC->CallServerSetReplicatedTargetData(
                GetAbilitySpecHandle(),
                GetActivationPredictionKey(),
                Data,
                ApplicationTag,
                ASC->ScopedPredictionKey);
        }
    }

    // Task가 살아있으면 ValidData 브로드캐스트 → GA에서 GE 적용 등 처리
    if (ShouldBroadcastAbilityTaskDelegates())
        ValidData.Broadcast(Data);

    // CustomMulti가 아니면 Task 종료 (한 번만 TargetData 허용)
    if (ConfirmationType != EGameplayTargetingConfirmation::CustomMulti)
        EndTask();
}
```

- 클라이언트는 `CallServerSetReplicatedTargetData` RPC로 서버에 TargetData를 전달한다.
- 전달과 동시에 `ValidData.Broadcast(Data)`로 **로컬에서도 즉시 처리** (Prediction).
- `CustomMulti`가 아니면 EndTask — 일반적으로 한 번 발사하면 Task가 끝난다.

---

## OnTargetDataReplicatedCallback — 서버가 클라이언트로부터 수신

```cpp
void UAbilityTask_WaitTargetData::OnTargetDataReplicatedCallback(
    const FGameplayAbilityTargetDataHandle& Data,
    FGameplayTag ActivationTag)
{
    FGameplayAbilityTargetDataHandle MutableData = Data;

    // 이미 소비된 TargetData 맵에서 제거 (중복 처리 방지)
    ASC->ConsumeClientReplicatedTargetData(GetAbilitySpecHandle(), GetActivationPredictionKey());

    // TargetActor가 있으면 검증 기회 부여 (OnReplicatedTargetDataReceived)
    if (TargetActor)
    {
        if (!TargetActor->OnReplicatedTargetDataReceived(MutableData))
        {
            // TargetActor가 거부 → Cancelled 브로드캐스트
            if (ShouldBroadcastAbilityTaskDelegates())
                Cancelled.Broadcast(MutableData);
        }
        else
        {
            if (ShouldBroadcastAbilityTaskDelegates())
                ValidData.Broadcast(MutableData);
        }
    }
    else
    {
        // 서버에 TargetActor가 없을 때 (일반 경우) → 그냥 ValidData
        if (ShouldBroadcastAbilityTaskDelegates())
            ValidData.Broadcast(MutableData);
    }

    if (ConfirmationType != EGameplayTargetingConfirmation::CustomMulti)
        EndTask();
}
```

- `ConsumeClientReplicatedTargetData`: `AbilityTargetDataMap`에서 이 키의 데이터를 꺼내 삭제. 중복 처리 방지.
- 서버에 TargetActor가 없는 경우(기본)에는 검증 없이 `ValidData` 브로드캐스트.
- 서버에 TargetActor가 있는 경우 `OnReplicatedTargetDataReceived`로 서버 측 검증 가능.

---

## ShouldProduceTargetDataOnServer 플래그

`AGameplayAbilityTargetActor`의 멤버. 기본값 `false`.

| 값 | 동작 |
|----|------|
| `false` (기본) | 클라이언트가 TargetData 생성 → RPC로 서버 전송 → 서버가 ValidData 처리 |
| `true` | 서버가 직접 TargetActor 스폰 → 서버에서 TargetData 생성 → RPC 없음 |

`true`로 설정하면 서버 권위적이지만 응답성이 떨어진다. 치트 방지가 중요한 경우에만 사용.

---

## 클라이언트 ↔ 서버 대칭 구조 요약

```
[클라이언트]                           [서버]

Activate()                             Activate()
  ShouldSpawnTargetActor() → true        ShouldSpawnTargetActor() → false
  SpawnTargetActor()                     RegisterTargetDataCallbacks()
  FinalizeTargetActor()                    AbilityTargetDataSetDelegate에 등록
    TargetActor 시작 + 입력 구독

(플레이어 조준)

TargetActor→TargetDataReadyDelegate
  OnTargetDataReadyCallback()
    CallServerSetReplicatedTargetData() ──RPC──►  OnTargetDataReplicatedCallback()
    ValidData.Broadcast() ← 즉시 처리               ConsumeClientReplicatedTargetData()
    EndTask()                                        ValidData.Broadcast()
                                                     EndTask()
```

---

## Lyra가 WaitTargetData를 쓰지 않는 이유

| | WaitTargetData | Lyra 히트스캔 |
|--|----------------|---------------|
| TargetActor 스폰 | 매 발사마다 스폰 | 없음 |
| 조준 대기 | 가능 (`UserConfirmed`) | 불필요 (즉시 트레이스) |
| ConfirmationType | `Instant` / `UserConfirmed` | 해당 없음 |
| TargetData 전송 | `CallServerSetReplicatedTargetData` | `CallServerSetReplicatedTargetData` (직접 호출) |

Lyra 히트스캔은 발사 즉시 트레이스가 완료되기 때문에 TargetActor를 스폰할 이유가 없다.  
`OnTargetDataReadyCallback`을 WaitTargetData 없이 직접 콜백으로 등록하고,  
`StartRangedWeaponTargeting()`에서 트레이스 → 콜백 직접 호출로 동일한 흐름을 구현한다.
