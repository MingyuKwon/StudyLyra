# GAS — AbilityTask / TargetData

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 34. UGameplayTask 핵심 내부 구조

> 소스: `C:/Program Files/Epic Games/UE_5.7/Engine/Source/Runtime/GameplayTasks/`  
> 상세 문서: `doc/gas_tranek/ability_task/00_gameplay_task.md`

### 상태 머신 (EGameplayTaskState)
`Uninitialized → AwaitingActivation → Active ↔ Paused → Finished`

### ReadyForActivation() 분기 (GameplayTask.cpp:56)
- `RequiresPriorityOrResourceManagement() == false` → `PerformActivation()` 즉시 호출
- 우선순위/리소스 필요 → `TasksComponent->AddTaskReadyForActivation()` 큐 등록
- TasksComponent 없음 → `EndTask()` 즉시 종료

### PerformActivation() 흐름 (GameplayTask.cpp:275)
`TaskState = Active` → `Activate()` 호출 → `IsFinished() == false`이면 `TasksComponent->OnGameplayTaskActivated()`

### 종료 경로 두 가지
- `EndTask()` → `OnDestroy(false)` : 태스크 스스로 종료
- `TaskOwnerEnded()` → `bOwnerFinished = true` + `OnDestroy(true)` : 소유자(GA) 종료로 인한 정리

### OnDestroy() (GameplayTask.cpp:206)
`TaskState = Finished` → `TasksComponent->OnGameplayTaskDeactivated()` → `MarkAsGarbage()`  
오버라이드 시 `Super::OnDestroy()`를 **마지막**에 호출해야 함 (`MarkAsGarbage` 간섭 방지)

### bSimulatedTask vs bIsSimulating (GameplayTask.h:344~348)
- `bSimulatedTask`: 설정값. `true`이면 `IsSupportedForNetworking() = true` → 복제 허용
- `bIsSimulating`: 런타임 상태. `InitSimulatedTask()` 내부에서 `true`로 세팅됨

### Activate() 베이스 구현
VLOG 출력만 하고 아무것도 하지 않는다. 개발자가 오버라이드해서 실제 로직 구현.

---

## 19. EAbilityGenericReplicatedEvent — GA 인스턴스 신호 채널

**출처**:  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/GameplayAbilityTargetTypes.h:662`  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:3880`  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

### 정의

활성화된 GA 인스턴스에 묶인 신호 슬롯. 이름의 "Replicated"는 클라↔서버 RPC로 동기화되기 때문.

```cpp
namespace EAbilityGenericReplicatedEvent
{
    enum Type : int
    {
        GenericConfirm,           // WaitConfirm
        GenericCancel,            // WaitCancel
        InputPressed,             // WaitInputPress
        InputReleased,            // WaitInputRelease
        GenericSignalFromClient,  // 범용 클라→서버
        GenericSignalFromServer,  // 범용 서버→클라
        GameCustom1 ~ GameCustom6 // 게임 전용 확장
    };
}
```

### 저장소

ASC의 `AbilityTargetDataMap`:
- key: `FGameplayAbilitySpecHandle + FPredictionKey` (GA 인스턴스 단위 분리)
- value: `FAbilityReplicatedDataCache` → `GenericEvents[MAX]` 슬롯 배열
  - 각 슬롯: `bTriggered`, `VectorPayload`, `Delegate(FSimpleMulticastDelegate)`

### InvokeReplicatedEvent (로컬 발동)

1. `GenericEvents[Type].bTriggered = true` 저장
2. Delegate가 바인딩 돼 있으면 즉시 Broadcast
3. 아무도 구독 안 하면 `bTriggered=true`만 저장 → 나중에 `CallReplicatedEventDelegateIfSet()`으로 사후 처리 가능 (타이밍 레이스 방지)

### RPC 동기화

- 클라→서버: `ServerSetReplicatedEvent()` → 서버에서 `InvokeReplicatedEvent()` 호출
- 서버→클라: `ClientSetReplicatedEvent()` → 클라에서 `InvokeReplicatedEvent()` 호출

### WaitInputPress 구독 방법

```cpp
// Activate()
DelegateHandle = ASC->AbilityReplicatedEventDelegate(
    EAbilityGenericReplicatedEvent::InputPressed,
    GetAbilitySpecHandle(), GetActivationPredictionKey()
).AddUObject(this, &ThisClass::OnPressCallback);

// 이미 발동됐을 경우 사후 처리
if (IsForRemoteClient())
    ASC->CallReplicatedEventDelegateIfSet(InputPressed, handle, predKey);
```

### 호출 체인 (ProcessAbilityInput → WaitInputPress)

```
AbilitySpec->IsActive() == true
  → AbilitySpecInputPressed()
      → InvokeReplicatedEvent(InputPressed, handle, predKey)
          → GenericEvents[InputPressed].Delegate.Broadcast()
              → WaitInputPress::OnPressCallback()
                  → OnPress.Broadcast(ElapsedTime)
                  → (IsPredictingClient) ServerSetReplicatedEvent()
                  → EndTask()
```

---

## 35. WaitNetSync — UAbilityTask_NetworkSyncPoint 구현

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_NetworkSyncPoint.h`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_NetworkSyncPoint.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

### 핵심 요약

- GASDoc의 "WaitNetSync"는 `UAbilityTask_NetworkSyncPoint` 클래스이며, 정적 팩토리 `WaitNetSync()` 함수로 생성
- Lyra 소스에는 WaitNetSync 직접 사용 코드 없음 (GASDoc의 Sprint GA 예시는 별도 샘플 프로젝트)

### SyncType

```cpp
enum class EAbilityTaskNetSyncType : uint8
{
    BothWait,        // 클라-서버 둘 다 대기
    OnlyServerWait,  // 서버만 대기 (클라는 신호 보내고 즉시 계속) ← Scoped Prediction 용도
    OnlyClientWait   // 클라만 대기
};
```

### Activate() 핵심 로직

```cpp
FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient()); // 새 Key 발급

if (IsPredictingClient()) {
    if (SyncType != OnlyServerWait)   ReplicatedEventToListenFor = GenericSignalFromServer;
    if (SyncType != OnlyClientWait)   ASC->ServerSetReplicatedEvent(GenericSignalFromClient, ..., ASC->ScopedPredictionKey);
} else if (IsForRemoteClient()) {
    if (SyncType != OnlyClientWait)   ReplicatedEventToListenFor = GenericSignalFromClient;
    if (SyncType != OnlyServerWait)   ASC->ClientSetReplicatedEvent(GenericSignalFromServer, ...);
}
// 리스닝 대상 없으면 SyncFinished() 즉시 호출
```

OnlyServerWait 시: 클라는 RPC 보내고 SyncFinished() 즉시 → 서버는 GenericSignalFromClient 수신 후 재개

### 입력 태스크 내장 Sync Point (WaitInputPress.cpp)

```cpp
void UAbilityTask_WaitInputPress::OnPressCallback() {
    FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient()); // ← 내장 Key 발급
    if (IsPredictingClient())
        ASC->ServerSetReplicatedEvent(InputPressed, ..., ASC->ScopedPredictionKey);
    // WaitNetSync와 동일한 패턴을 콜백 내부에서 직접 수행
}
```

### 적용 판단 기준

- 입력 태스크(WaitInputPress 등) 콜백 이후 → 내장 Sync Point 있음, 추가 불필요
- WaitDelay 콜백 이후 GE 적용 → `WaitNetSync(OnlyServerWait)` 삽입 필요
- 예측 GE 두 번 재생(redo 문제) → GE Apply 직전 `WaitNetSync(OnlyServerWait)` 삽입

---

## 22. TargetData — 타겟팅 결과 패킷 & ASC 저장 구조

> 출처: `Engine/Plugins/Runtime/GameplayAbilities/.../GameplayAbilityTargetTypes.h`, `AbilitySystemComponent_Abilities.cpp`  
> Lyra: `AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`, `AbilitySystem/LyraAbilitySystemComponent.cpp:520`  
> 상세 문서: `doc/gas_tranek/ability_task/02_target_data.md`

### FGameplayAbilityTargetData
- `USTRUCT` + 가상 함수 → UObject 없이 폴리모픽
- `GetActors()`, `GetHitResult()`, `GetEndPoint()`, `GetOrigin()` 가상 함수로 타겟 정보 추출
- `ApplyGameplayEffectSpec()` — TargetData 안의 모든 타겟에 GE 일괄 적용
- `FGameplayAbilityTargetDataHandle`으로 감싸서 사용 (`TArray<TSharedPtr<...>, TInlineAllocator<1>>`)

### ASC가 AbilityTargetDataMap에 캐싱하는 이유
- 클라→서버 RPC 타이밍이 GA 실행 흐름과 비동기: RPC 도착 시 GA가 이미 다른 단계
- `AbilityTargetDataMap` 키: `(FGameplayAbilitySpecHandle, FPredictionKey)` 쌍
- 값: `FAbilityReplicatedDataCache` — TargetData, ApplicationTag, bTargetConfirmed, bTargetCancelled, TargetSetDelegate, PredictionKey

### WaitTargetData 두 경로
- RPC 먼저 도착 → `CallReplicatedTargetDataDelegatesIfSet()` 즉시 발동
- RPC 미도착 → `AbilityTargetDataSetDelegate`에 바인딩 대기, 나중에 `ServerSetReplicatedTargetData_Implementation`에서 Broadcast

### LyraAbilitySystemComponent::GetAbilityTargetData (cpp:520)
```cpp
AbilityTargetDataMap.Find(FGameplayAbilitySpecHandleAndPredictionKey(Handle, PredKey))
  → ReplicatedData->TargetData 반환
```

### FLyraGameplayAbilityTargetData_SingleTargetHit
- `FGameplayAbilityTargetData_SingleHit` 서브클래스
- `int32 CartridgeID` 추가 — 산탄총 펠릿처럼 한 발사에서 나온 여러 히트를 묶기 위한 ID

---

## 20. TargetData 실제 사용 — LyraGameplayAbility_RangedWeapon

**출처**:
`Source/LyraGame/AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`
`Source/LyraGame/Weapons/LyraGameplayAbility_RangedWeapon.cpp`
`Source/LyraGame/AbilitySystem/LyraGameplayEffectContext.h`

### TargetData 서브클래스

`FLyraGameplayAbilityTargetData_SingleTargetHit` : `FGameplayAbilityTargetData_SingleTargetHit` 상속
- 추가 필드: `int32 CartridgeID` — 같은 탄창(산탄총 등) 총알들을 묶는 ID
- `NetSerialize`: 부모 호출 후 `Ar << CartridgeID`
- `AddTargetDataToContext` 오버라이드: CartridgeID를 `FLyraGameplayEffectContext`에 주입

### EffectContext 연결

`FLyraGameplayEffectContext` : `FGameplayEffectContext` 상속
- 추가 필드: `int32 CartridgeID = -1`
- `AddTargetDataToContext()`에서 `ExtractEffectContext(Context)->CartridgeID = CartridgeID` 로 복사됨
- 이후 ExecCalc/GameplayCue/AttributeSet 콜백에서 `ExtractEffectContext()`로 꺼내 사용 가능

### 전체 흐름 (Task 없이 수동 처리 방식)

```
ActivateAbility()
  → AbilityTargetDataSetDelegate 구독 (OnTargetDataReadyCallback)
  → StartRangedWeaponTargeting()
      → PerformLocalTargeting() — 클라이언트 레이캐스트
      → FLyraGameplayAbilityTargetData_SingleTargetHit 생성 + HitResult/CartridgeID 채움
      → Handle.Add(NewTargetData)
      → OnTargetDataReadyCallback() 직접 호출

OnTargetDataReadyCallback()
  → (클라이언트) CallServerSetReplicatedTargetData() RPC — PredictionKey 포함
  → (서버) AbilityTargetDataSetDelegate.Broadcast() → 동일 콜백 재진입
  → CommitAbility() → OnRangedWeaponTargetDataReady() Blueprint이벤트 (GE Apply)
  → ConsumeClientReplicatedTargetData() — ASC 내부 캐시 정리

EndAbility()
  → Delegate.Remove(Handle)
  → ConsumeClientReplicatedTargetData()
```

**특이점**: `WaitTargetData` AbilityTask를 쓰지 않고, `AbilityTargetDataSetDelegate`를 GA가 직접 구독하는 수동 방식이다. TargetData 전송 타이밍을 GA가 직접 제어한다.
