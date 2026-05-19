# Prediction Window 생성 & 액터 스폰

> **GASDoc**: 4.10.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-p-windows"></a>
#### 4.10.2 Ability 내에서 새 Prediction Window 생성

`AbilityTask` 콜백에서 추가 액션을 예측하려면 새로운 Scoped Prediction Key로 새로운 Scoped Prediction Window를 생성해야 한다. 이를 클라이언트와 서버 사이의 Synch Point라고 부르기도 한다. 입력 관련 AbilityTask들은 모두 새 Scoped Prediction Window를 생성하는 기능이 내장되어 있어, `AbilityTask` 콜백의 원자적 코드에서 유효한 Scoped Prediction Key를 사용할 수 있다. `WaitDelay` 태스크 같은 경우에는 콜백에 대한 새 Scoped Prediction Window를 생성하는 내장 코드가 없다. `WaitDelay`처럼 Scoped Prediction Window를 생성하는 내장 코드가 없는 `AbilityTask` 이후에 액션을 예측해야 한다면, `OnlyServerWait` 옵션으로 `WaitNetSync` `AbilityTask`를 사용해 수동으로 처리해야 한다. 클라이언트가 `OnlyServerWait` 상태의 `WaitNetSync`에 도달하면, `GameplayAbility`의 Activation Prediction Key를 기반으로 새로운 Scoped Prediction Key를 생성하고, 이를 서버에 RPC로 전송하며, 새로 적용하는 `GameplayEffect`에 추가한다. 서버가 `OnlyServerWait` 상태의 `WaitNetSync`에 도달하면, 클라이언트로부터 새로운 Scoped Prediction Key를 받을 때까지 대기한 후 계속 실행한다. 이 Scoped Prediction Key는 Activation Prediction Key와 동일한 방식으로 `GameplayEffect`에 적용되고 클라이언트에게 복제되어 stale 처리된다. Scoped Prediction Key는 스코프를 벗어나면 만료되어 Scoped Prediction Window가 닫힌다. 따라서 원자적 연산만 새 Scoped Prediction Key를 사용할 수 있으며, latent한 연산은 사용할 수 없다.

필요한 만큼 많은 Scoped Prediction Window를 생성할 수 있다.

자신의 커스텀 `AbilityTask`에 Synch Point 기능을 추가하고 싶다면, 입력 관련 AbilityTask가 `WaitNetSync` `AbilityTask` 코드를 어떻게 주입하는지 살펴보라.

> **참고**  
> `WaitNetSync`를 사용하면 서버의 `GameplayAbility` 실행이 클라이언트에서 응답을 받을 때까지 **블로킹**된다. 게임을 해킹한 악의적인 사용자가 의도적으로 새로운 Scoped Prediction Key 전송을 지연시켜 이를 악용할 소지가 있다. Epic은 `WaitNetSync`를 최소한으로 사용하며, 보안이 우려된다면 클라이언트 응답 없이 일정 시간 후 자동으로 계속 진행하는 딜레이가 있는 새 버전의 `AbilityTask`를 빌드하는 것을 권장한다.

샘플 프로젝트는 Sprint `GameplayAbility`에서 스태미나 비용을 적용할 때마다 `WaitNetSync`를 사용하여 새로운 Scoped Prediction Window를 생성한다. 비용(Cost)과 쿨다운(Cooldown)을 적용할 때 유효한 Prediction Key를 갖추는 것이 이상적이다.

owning 클라이언트에서 예측된 `GameplayEffect`가 두 번 재생된다면, Prediction Key가 stale 상태인 "redo 문제"를 겪고 있는 것이다. `GameplayEffect`를 적용하기 직전에 `OnlyServerWait` 옵션의 `WaitNetSync` `AbilityTask`를 추가하여 새로운 Scoped Prediction Key를 생성하면 대개 해결할 수 있다.

<a name="concepts-p-spawn"></a>
#### 4.10.3 액터 예측 스폰

클라이언트에서 `Actor`를 예측적으로 스폰하는 것은 고급 주제다. GAS는 이에 대한 기능을 기본 제공하지 않는다(`SpawnActor` `AbilityTask`는 서버에서만 `Actor`를 스폰한다). 핵심 개념은 클라이언트와 서버 **양쪽에서 복제된 `Actor`를 스폰**하는 것이다.

`Actor`가 단순히 코스메틱이거나 게임플레이 목적이 없다면, 간단한 해결책은 `Actor`의 `IsNetRelevantFor()` 함수를 오버라이드하여 서버가 owning 클라이언트에게 복제하지 못하도록 제한하는 것이다. owning 클라이언트는 로컬에서 스폰한 버전을, 서버와 다른 클라이언트들은 서버의 복제본을 사용하게 된다.

```c++
bool APAReplicatedActorExceptOwner::IsNetRelevantFor(const AActor * RealViewer, const AActor * ViewTarget, const FVector & SrcLocation) const
{
	return !IsOwnedBy(ViewTarget);
}
```

스폰된 `Actor`가 데미지 예측이 필요한 발사체처럼 게임플레이에 영향을 미친다면, 이 문서의 범위를 벗어나는 고급 로직이 필요하다. Epic Games의 GitHub에서 UnrealTournament가 발사체를 예측적으로 스폰하는 방식을 참고하라. owning 클라이언트에만 더미 발사체를 스폰하여 서버의 복제 발사체와 동기화하는 방식을 사용한다.

---

### WaitNetSync의 실제 클래스: `UAbilityTask_NetworkSyncPoint`

GASDoc에서 "WaitNetSync"라고 부르는 것의 실제 클래스명은 `UAbilityTask_NetworkSyncPoint`이며,
정적 팩토리 함수 이름이 `WaitNetSync()`다.

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_NetworkSyncPoint.h`

---

### SyncType 3종

```cpp
UENUM()
enum class EAbilityTaskNetSyncType : uint8
{
    BothWait,        // 클라-서버 둘 다 상대가 도달할 때까지 대기
    OnlyServerWait,  // 서버만 클라 신호를 기다림. 클라는 신호 보내고 즉시 계속
    OnlyClientWait   // 클라만 서버 신호를 기다림. 서버는 신호 보내고 즉시 계속
};
```

GASDoc이 말하는 "새 Scoped Prediction Window 수동 생성" 용도에는 **`OnlyServerWait`** 을 쓴다.
- 클라이언트: Activation Prediction Key 기반으로 새 Scoped Prediction Key 생성 → 서버에 RPC → 즉시 계속 실행
- 서버: 클라이언트의 Key RPC가 도착할 때까지 블로킹 → 이후 실행 재개

---

### `Activate()` 내부 구현 흐름

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_NetworkSyncPoint.cpp`

```cpp
void UAbilityTask_NetworkSyncPoint::Activate()
{
    // FScopedPredictionWindow 생성 → IsPredictingClient()일 때만 새 Key 발급
    FScopedPredictionWindow ScopedPrediction(AbilitySystemComponent.Get(), IsPredictingClient());

    if (IsPredictingClient())
    {
        // OnlyServerWait: 클라는 대기하지 않음 → ReplicatedEventToListenFor 는 MAX 유지
        if (SyncType != EAbilityTaskNetSyncType::OnlyServerWait)
            ReplicatedEventToListenFor = EAbilityGenericReplicatedEvent::GenericSignalFromServer;

        // OnlyClientWait: 서버가 기다리지 않으므로 RPC 불필요
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

    // 리스닝 대상이 있으면 델리게이트 등록, 없으면 즉시 SyncFinished()
    if (ReplicatedEventToListenFor != MAX)
        CallOrAddReplicatedDelegate(ReplicatedEventToListenFor, &OnSignalCallback);
    else
        SyncFinished();  // 기다릴 필요 없는 쪽은 바로 통과
}
```

`OnlyServerWait` 시 클라이언트 측 흐름 요약:
1. `FScopedPredictionWindow` 생성 → 내부적으로 새 `ScopedPredictionKey` 발급
2. `ServerSetReplicatedEvent()` RPC로 서버에 Key 전달
3. `ReplicatedEventToListenFor == MAX` → `SyncFinished()` 즉시 호출 → 클라는 블로킹 없음
4. 서버는 `GenericSignalFromClient` 이벤트 대기 → RPC 수신 후 `SyncFinished()` → 실행 재개

---

### 입력 태스크의 내장 Sync Point 비교 (`WaitInputPress`)

GASDoc이 "입력 관련 AbilityTask는 내장된 Scoped Prediction Window가 있다"고 한 이유:

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

```cpp
void UAbilityTask_WaitInputPress::OnPressCallback()
{
    UAbilitySystemComponent* ASC = AbilitySystemComponent.Get();

    // ★ 콜백 진입 시 FScopedPredictionWindow 생성 → 자동으로 새 Key 발급
    FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient());

    if (IsPredictingClient())
    {
        // 클라: 서버에 InputPressed RPC + 새 ScopedPredictionKey 전달
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

`WaitNetSync`와 **동일한 패턴** — `FScopedPredictionWindow` + `ServerSetReplicatedEvent()` — 을
콜백 내부에서 직접 수행한다. 이것이 "내장" Sync Point의 실체다.

`WaitDelay` 같은 비입력 태스크는 콜백에 이 코드가 없어서, 이후 예측이 필요하면
`WaitNetSync(OnlyServerWait)` 을 수동으로 삽입해야 한다.

---

### 적용 패턴 정리

| 상황 | 해결책 |
|---|---|
| `WaitInputPress` 콜백 이후 GE 적용 | 내장 Sync Point가 있으므로 바로 `ApplyGameplayEffect` |
| `WaitDelay` 콜백 이후 GE 적용 | `WaitNetSync(OnlyServerWait)` → `OnSync` 콜백 안에서 `ApplyGameplayEffect` |
| 예측 GE가 owning 클라에서 두 번 재생됨 | `ApplyGameplayEffect` 직전에 `WaitNetSync(OnlyServerWait)` 삽입 |
| Sprint처럼 매 비용 지불 시 새 Window 필요 | 비용 적용 루프마다 `WaitNetSync(OnlyServerWait)` |

> **보안 주의**: `WaitNetSync`는 서버 실행을 클라 RPC 수신까지 블로킹한다. 악의적 클라이언트가
> RPC를 지연시키면 서버 GA도 멈춘다. Epic은 일정 시간 후 자동 진행하는 변형 태스크 빌드를 권장한다.
