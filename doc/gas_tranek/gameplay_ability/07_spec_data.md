# GA Spec & 데이터 전달

> **GASDoc**: 4.6.10~11 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-spec"></a>
#### GameplayAbilitySpec은 무엇이며 GA 클래스와 어떤 정보를 별도로 보관하는가?

`GameplayAbility`가 부여된 이후에는 ASC 위에 `GameplayAbilitySpec`이 존재하게 된다. `GameplayAbilitySpec`은 활성화 가능한 `GameplayAbility`를 정의하며, GameplayAbility 클래스, 레벨, 입력 바인딩, 그리고 GameplayAbility 클래스와 분리하여 유지해야 하는 런타임 상태 정보를 담고 있다.

서버에서 `GameplayAbility`가 부여되면, 서버는 `GameplayAbilitySpec`을 owning client에 복제하여 해당 클라이언트가 능력을 활성화할 수 있도록 한다.

`GameplayAbilitySpec`을 활성화하면 그 `Instancing Policy`에 따라 `GameplayAbility`의 인스턴스가 생성된다 (`Non-Instanced` GameplayAbility의 경우에는 인스턴스가 생성되지 않는다).

<a name="concepts-ga-data"></a>
#### GA에 외부 데이터를 전달하는 방법에는 무엇이 있으며, 각 방법의 장단점은?

`GameplayAbility`의 일반적인 패러다임은 `Activate → Generate Data → Apply → End`다. 때로는 기존 데이터를 기반으로 동작해야 하는 경우도 있다. GAS는 외부 데이터를 `GameplayAbility`로 전달하기 위한 몇 가지 방법을 제공한다.

| 방법                                            | 설명                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 이벤트로 `GameplayAbility` 활성화               | 데이터 페이로드를 포함한 이벤트로 `GameplayAbility`를 활성화한다. 로컬 예측 `GameplayAbility`의 경우, 이벤트 페이로드는 클라이언트에서 서버로 복제된다. 기존 변수에 맞지 않는 임의의 데이터를 전달할 때는 두 개의 `Optional Object` 변수 또는 `TargetData` 변수를 사용한다. 단, 이 방법을 사용하면 입력 바인딩으로는 어빌리티를 활성화할 수 없다는 단점이 있다. 이벤트로 `GameplayAbility`를 활성화하려면, `GameplayAbility`에서 `Triggers`를 설정하고 `GameplayTag`를 할당한 후 `GameplayEvent` 옵션을 선택해야 한다. 이벤트를 전송할 때는 `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor(AActor* Actor, FGameplayTag EventTag, FGameplayEventData Payload)` 함수를 사용한다. |
| `WaitGameplayEvent` AbilityTask 사용            | `WaitGameplayEvent` AbilityTask를 사용하여, `GameplayAbility`가 활성화된 이후 페이로드 데이터를 포함한 이벤트를 수신 대기하도록 설정한다. 이벤트 페이로드와 전송 방법은 이벤트로 GameplayAbility를 활성화하는 것과 동일하다. 단, AbilityTask가 이벤트를 복제하지 않으므로 `Local Only` 및 `Server Only` GameplayAbility에서만 사용해야 한다는 단점이 있다. 이벤트 페이로드를 복제하는 커스텀 AbilityTask를 직접 작성하는 것도 가능하다.                                                                                                                                                                                                                                                                                       |
| `TargetData` 사용                               | 커스텀 `TargetData` 구조체는 클라이언트와 서버 사이에서 임의의 데이터를 전달하는 좋은 방법이다.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `OwnerActor` 또는 `AvatarActor`에 데이터 저장  | `OwnerActor`, `AvatarActor`, 또는 참조를 얻을 수 있는 다른 오브젝트에 복제 변수를 저장하여 사용한다. 이 방법은 가장 유연하며 입력 바인딩으로 활성화되는 `GameplayAbility`와도 함께 사용할 수 있다. 단, 사용 시점에 복제로 인한 데이터 동기화가 보장되지 않는다. 즉, 복제 변수를 설정하고 즉시 `GameplayAbility`를 활성화하면, 패킷 손실 등의 이유로 수신 측에서 처리 순서가 보장되지 않을 수 있다.                                                                                                                                                                                                                                                                                                                                     |

---

**출처**: `AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`, `Weapons/LyraGameplayAbility_RangedWeapon.cpp`

---

### TargetData로 GA에 데이터를 전달하는 세 가지 패턴은 무엇이며 각각 언제 사용하는가?

#### GA를 이벤트로 트리거할 때 TargetData를 함께 전달하는 방법은?

GA를 이벤트로 트리거할 때 `FGameplayEventData.TargetData`에 담아 같이 보낸다.

```cpp
// 발신 측
FGameplayEventData EventData;
FGameplayAbilityTargetDataHandle Handle;
Handle.Add(new FGameplayAbilityTargetData_SingleHit(HitResult));
EventData.TargetData = Handle;

UAbilitySystemBlueprintLibrary::SendGameplayEventToActor(Actor, Tag, EventData);
```

```cpp
// GA 수신 측
void UMyAbility::ActivateAbilityFromEvent(
    const FGameplayAbilitySpecHandle Handle,
    const FGameplayAbilityActorInfo* ActorInfo,
    const FGameplayAbilityActivationInfo ActivationInfo,
    const FGameplayEventData* TriggerEventData)
{
    FGameplayAbilityTargetDataHandle TargetData = TriggerEventData->TargetData;
    // TargetData 사용
}
```

이벤트로 GA를 트리거하면 `TriggerEventData`가 채워진 채로 `ActivateAbility`가 호출된다. 단, 이 방법을 쓰면 **입력 바인딩으로 직접 발동이 불가능**하다 (`TryActivateAbility`로는 TriggerEventData가 nullptr).

---

#### WaitTargetData AbilityTask로 활성화 이후 단계에서 타겟을 수집하는 방법은?

GA 활성화 이후 별도 단계에서 타겟팅을 수집하는 방식.

```cpp
void UMyAbility::ActivateAbility(...)
{
    UAbilityTask_WaitTargetData* Task = UAbilityTask_WaitTargetData::WaitTargetData(
        this,
        NAME_None,
        EGameplayTargetingConfirmation::Instant,  // 즉시 확정
        AGameplayAbilityTargetActor_SingleLineTrace::StaticClass());

    Task->ValidData.AddDynamic(this, &UMyAbility::OnTargetDataReady);
    Task->ReadyForActivation();
}

void UMyAbility::OnTargetDataReady(const FGameplayAbilityTargetDataHandle& Data)
{
    // TargetData 사용 (서버에서 이미 동기화된 상태)
}
```

내부적으로 `AGameplayAbilityTargetActor`를 스폰하고, 타겟 확정 시 클라→서버 RPC를 자동으로 처리한다.

---

#### Lyra의 원거리 무기처럼 TargetData 전송 타이밍을 GA가 직접 제어하는 수동 방식은 어떻게 동작하는가?

`WaitTargetData` Task 없이 GA가 `AbilityTargetDataSetDelegate`를 직접 구독한다. Lyra 원거리 무기 GA(`LyraGameplayAbility_RangedWeapon`)가 이 방식.

```
ActivateAbility()
  └─ AbilityTargetDataSetDelegate 구독 (OnTargetDataReadyCallback)
  └─ PerformLocalTargeting() — 클라이언트 레이캐스트
  └─ FLyraGameplayAbilityTargetData_SingleTargetHit 생성
       (HitResult + CartridgeID 채움)
  └─ OnTargetDataReadyCallback() 직접 호출

OnTargetDataReadyCallback()
  ├─ [클라이언트] CallServerSetReplicatedTargetData() RPC 전송 (PredictionKey 포함)
  ├─ [서버] Delegate.Broadcast() → 동일 콜백 재진입
  └─ CommitAbility() → GE Apply → ConsumeClientReplicatedTargetData()
```

TargetData 전송 타이밍을 GA가 직접 제어해야 할 때 사용한다.

---

### TargetData는 왜 클라→서버 방향이 기본이며, 서버→클라 방향은 언제 사용하는가?

#### 클라이언트→서버 방향이 기본 설계인 이유는 무엇인가?

```
클라이언트                            서버
   │ 레이캐스트 → TargetData 생성       │
   │ 로컬에 예측 적용                   │
   │──ServerSetReplicatedTargetData()──▶│
   │                                   │ 검증 → GE 적용
```

이것이 기본인 이유:
- 타겟팅 정보(어디를 겨냥했는가)는 **클라이언트의 뷰포트**에서 결정된다.
- `AbilityTargetDataMap` 키에 `PredictionKey`(클라 발급)가 포함되어 있어, 설계 자체가 클라→서버 중심이다.
- 서버는 받은 TargetData를 검증 후 권위 있는 GE를 적용한다.

#### 서버→클라이언트 방향 TargetData는 어떤 경우에 사용하며 예측이 불가능한 이유는?

`AGameplayAbilityTargetActor`를 **서버에서만 실행**하도록 구성하면 서버가 타겟을 결정하고 클라에 결과를 전달한다.

```
클라이언트                            서버
   │                                   │ 서버 측 TargetActor 실행
   │                                   │ TargetData 생성
   │◀──ClientSetReplicatedTargetData()─│
   │ 수신 후 시각적 처리               │
```

이 방향이 쓰이는 경우:
- AI가 타겟팅을 결정하고 클라가 시각 효과만 재생할 때
- 서버 권위가 필요한 AOE 타겟팅

단, 이 경우 클라이언트 예측이 불가능하다 (`PredictionKey` 미사용). **Lyra는 이 방향을 사용하지 않는다.**

---

### 클라→서버 vs 서버→클라 TargetData 방향을 어떻게 비교할 수 있는가?

| | 클라 → 서버 | 서버 → 클라 |
|---|---|---|
| **주 사용처** | 플레이어 직접 조준/타겟팅 | AI 또는 서버 권위 타겟팅 |
| **예측** | 가능 (PredictionKey 사용) | 불가능 |
| **RPC** | `ServerSetReplicatedTargetData` | `ClientSetReplicatedTargetData` |
| **Lyra 사용** | O (원거리 무기) | X |
