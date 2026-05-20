# Prediction Window 생성 & 액터 스폰

> **GASDoc**: 4.10.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-p-windows"></a>
#### AbilityTask 콜백 이후에 추가 액션을 예측하려면 새 Scoped Prediction Window를 어떻게 만드는가?

Latent AbilityTask의 콜백에서는 원래의 Prediction Key가 만료되어 있다. 추가 예측이 필요하다면 새로운 Scoped Prediction Window를 생성해야 한다.

- **입력 관련 AbilityTask** (`WaitInputPress` 등): 콜백에 Scoped Prediction Window가 내장되어 있어 별도 처리 불필요.
- **비입력 AbilityTask** (`WaitDelay` 등): 내장 Sync Point가 없으므로, 콜백 이후 예측이 필요하면 `WaitNetSync(OnlyServerWait)`를 수동으로 삽입해야 한다.

`WaitNetSync(OnlyServerWait)` 동작:
1. 클라이언트: Activation Prediction Key 기반으로 새 Scoped Prediction Key 생성 → 서버에 RPC 전송 → 즉시 계속 실행
2. 서버: 클라이언트의 Key RPC가 도착할 때까지 블로킹 → 수신 후 실행 재개

> **보안 주의**: `WaitNetSync`는 서버 실행을 클라 RPC 수신까지 블로킹한다. 악의적 클라이언트가 RPC를 지연시키면 서버 GA도 멈춘다. Epic은 일정 시간 후 자동 진행하는 변형 태스크 빌드를 권장한다.

예측 GE가 owning 클라에서 **두 번 재생**된다면, Prediction Key가 stale 상태인 "redo 문제"다. GE 적용 직전에 `WaitNetSync(OnlyServerWait)`를 삽입해 새 Scoped Prediction Key를 생성하면 해결된다.

<a name="concepts-p-spawn"></a>
#### 클라이언트에서 액터를 예측적으로 스폰하려면 어떻게 해야 하며 GAS 기본 지원이 없는 이유는?

GAS는 예측적 Actor 스폰을 기본 지원하지 않는다 (`SpawnActor` AbilityTask는 서버에서만 스폰). 핵심 개념은 클라이언트와 서버 **양쪽에서 복제된 Actor를 스폰**하는 것이다.

**Actor가 코스메틱 전용인 경우**: `IsNetRelevantFor()`를 오버라이드하여 서버가 owning 클라이언트에게 복제하지 못하도록 제한한다. owning 클라이언트는 로컬 스폰 버전을, 서버와 다른 클라이언트는 서버 복제본을 사용한다.

```c++
bool APAReplicatedActorExceptOwner::IsNetRelevantFor(const AActor* RealViewer, const AActor* ViewTarget, const FVector& SrcLocation) const
{
    return !IsOwnedBy(ViewTarget);
}
```

**데미지 예측이 필요한 발사체인 경우**: 이 문서의 범위를 벗어나는 고급 로직이 필요하다. Epic Games GitHub의 UnrealTournament 구현을 참고하라 — owning 클라이언트에만 더미 발사체를 스폰하고 서버 복제 발사체와 동기화하는 방식을 사용한다.

---

### WaitNetSync라 불리는 UAbilityTask_NetworkSyncPoint의 실제 구현은 무엇인가?

GASDoc에서 "WaitNetSync"라고 부르는 것의 실제 클래스명은 `UAbilityTask_NetworkSyncPoint`이며, 정적 팩토리 함수 이름이 `WaitNetSync()`다.

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_NetworkSyncPoint.h`

---

### WaitNetSync의 BothWait·OnlyServerWait·OnlyClientWait는 각각 어떤 상황에서 쓰는가?

```cpp
UENUM()
enum class EAbilityTaskNetSyncType : uint8
{
    BothWait,        // 클라-서버 둘 다 상대가 도달할 때까지 대기
    OnlyServerWait,  // 서버만 클라 신호를 기다림. 클라는 신호 보내고 즉시 계속
    OnlyClientWait   // 클라만 서버 신호를 기다림. 서버는 신호 보내고 즉시 계속
};
```

"새 Scoped Prediction Window 수동 생성" 용도에는 **`OnlyServerWait`** 을 쓴다.
- 클라이언트: Activation Prediction Key 기반으로 새 Scoped Prediction Key 생성 → 서버에 RPC → 즉시 계속 실행
- 서버: 클라이언트의 Key RPC가 도착할 때까지 블로킹 → 이후 실행 재개

---

### WaitNetSync의 Activate() 내부에서 클라이언트와 서버는 각각 어떤 동작을 수행하는가?

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_NetworkSyncPoint.cpp`

```cpp
void UAbilityTask_NetworkSyncPoint::Activate()
{
    FScopedPredictionWindow ScopedPrediction(AbilitySystemComponent.Get(), IsPredictingClient());

    if (IsPredictingClient())
    {
        if (SyncType != EAbilityTaskNetSyncType::OnlyServerWait)
            ReplicatedEventToListenFor = EAbilityGenericReplicatedEvent::GenericSignalFromServer;

        if (SyncType != EAbilityTaskNetSyncType::OnlyClientWait)
            // ★ 서버에 GenericSignalFromClient RPC + 새 ScopedPredictionKey 전달
            ASC->ServerSetReplicatedEvent(GenericSignalFromClient, Handle, ActivationKey,
                                          ASC->ScopedPredictionKey);
    }
    else if (IsForRemoteClient())  // 서버 측
    {
        if (SyncType != EAbilityTaskNetSyncType::OnlyClientWait)
            ReplicatedEventToListenFor = EAbilityGenericReplicatedEvent::GenericSignalFromClient;

        if (SyncType != EAbilityTaskNetSyncType::OnlyServerWait)
            ASC->ClientSetReplicatedEvent(GenericSignalFromServer, Handle, ActivationKey);
    }

    if (ReplicatedEventToListenFor != MAX)
        CallOrAddReplicatedDelegate(ReplicatedEventToListenFor, &OnSignalCallback);
    else
        SyncFinished();  // 기다릴 필요 없는 쪽은 바로 통과
}
```

`OnlyServerWait` 시 클라이언트 흐름:
1. `FScopedPredictionWindow` 생성 → 새 `ScopedPredictionKey` 발급
2. `ServerSetReplicatedEvent()` RPC로 서버에 Key 전달
3. `ReplicatedEventToListenFor == MAX` → `SyncFinished()` 즉시 호출 → 클라는 블로킹 없음
4. 서버는 `GenericSignalFromClient` 이벤트 대기 → RPC 수신 후 `SyncFinished()` → 실행 재개

---

### 입력 관련 AbilityTask에 내장된 Sync Point가 WaitNetSync와 어떻게 같은 패턴을 사용하는가?

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

```cpp
void UAbilityTask_WaitInputPress::OnPressCallback()
{
    UAbilitySystemComponent* ASC = AbilitySystemComponent.Get();

    // ★ 콜백 진입 시 FScopedPredictionWindow 생성 → 자동으로 새 Key 발급
    FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient());

    if (IsPredictingClient())
    {
        ASC->ServerSetReplicatedEvent(EAbilityGenericReplicatedEvent::InputPressed,
                                      GetAbilitySpecHandle(), GetActivationPredictionKey(),
                                      ASC->ScopedPredictionKey);
    }
    else
    {
        ASC->ConsumeGenericReplicatedEvent(InputPressed, Handle, ActivationKey);
    }

    if (ShouldBroadcastAbilityTaskDelegates())
        OnPress.Broadcast(ElapsedTime);

    EndTask();
}
```

`WaitNetSync`와 동일한 패턴 — `FScopedPredictionWindow` + `ServerSetReplicatedEvent()` — 을 콜백 내부에서 직접 수행한다. 이것이 "내장" Sync Point의 실체다.

`WaitDelay` 같은 비입력 태스크는 이 코드가 없어서, 이후 예측이 필요하면 `WaitNetSync(OnlyServerWait)` 를 수동으로 삽입해야 한다.

---

### 예측 GE 적용 문제가 발생하는 상황별 WaitNetSync 사용 패턴은 어떻게 되는가?

| 상황 | 해결책 |
|---|---|
| `WaitInputPress` 콜백 이후 GE 적용 | 내장 Sync Point가 있으므로 바로 `ApplyGameplayEffect` |
| `WaitDelay` 콜백 이후 GE 적용 | `WaitNetSync(OnlyServerWait)` → `OnSync` 콜백 안에서 `ApplyGameplayEffect` |
| 예측 GE가 owning 클라에서 두 번 재생됨 | `ApplyGameplayEffect` 직전에 `WaitNetSync(OnlyServerWait)` 삽입 |
| Sprint처럼 매 비용 지불 시 새 Window 필요 | 비용 적용 루프마다 `WaitNetSync(OnlyServerWait)` |
