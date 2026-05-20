# GA Spec & 데이터 전달

> **GASDoc**: 4.6.10~11 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-spec"></a>
#### GameplayAbilitySpec은 무엇이며 GA 클래스와 어떤 정보를 별도로 보관하는가?

GA가 부여된 후 ASC 위에 존재하는 구조체다. GA 클래스 자체와 분리하여 유지해야 하는 런타임 상태 정보를 담는다: GA 클래스, 레벨, 입력 바인딩, 활성화 카운트, 인스턴스 목록 등.

서버에서 GA가 부여되면 서버는 `GameplayAbilitySpec`을 owning client에 복제하여 해당 클라이언트가 어빌리티를 활성화할 수 있도록 한다. Spec을 활성화하면 `Instancing Policy`에 따라 GA 인스턴스가 생성된다 (`Non-Instanced`의 경우에는 인스턴스가 생성되지 않는다).

<a name="concepts-ga-data"></a>
#### GA에 외부 데이터를 전달하는 방법에는 무엇이 있으며, 각 방법의 장단점은?

| 방법 | 장점 | 단점 |
|---|---|---|
| 이벤트로 GA 활성화 | 로컬 예측 GA의 경우 이벤트 페이로드가 클라→서버로 복제됨 | 입력 바인딩으로는 활성화 불가 |
| `WaitGameplayEvent` AbilityTask | GA 활성화 이후에도 페이로드 수신 가능 | AbilityTask가 이벤트를 복제하지 않으므로 `Local Only`/`Server Only`에서만 사용해야 함 |
| `TargetData` | 클라이언트와 서버 사이에서 임의의 데이터를 구조화해 전달 가능 | — |
| `OwnerActor`/`AvatarActor`에 데이터 저장 | 가장 유연하며 입력 바인딩으로 활성화되는 GA와도 호환 | 복제 변수를 설정하고 즉시 GA를 활성화하면 수신 측에서 처리 순서가 보장되지 않을 수 있음 |

---

**출처**: `AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`, `Weapons/LyraGameplayAbility_RangedWeapon.cpp`

---

### TargetData로 GA에 데이터를 전달하는 세 가지 패턴은 무엇이며 각각 언제 사용하는가?

#### GA를 이벤트로 트리거할 때 TargetData를 함께 전달하는 방법은?

`FGameplayEventData.TargetData`에 담아 함께 전송한다. GA 수신 측에서는 `TriggerEventData->TargetData`로 꺼내 쓴다.

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
void UMyAbility::ActivateAbilityFromEvent(...)
{
    FGameplayAbilityTargetDataHandle TargetData = TriggerEventData->TargetData;
}
```

단, 이 방법을 쓰면 입력 바인딩으로 직접 발동이 불가능하다 (`TryActivateAbility`로는 TriggerEventData가 nullptr).

---

#### WaitTargetData AbilityTask로 활성화 이후 단계에서 타겟을 수집하는 방법은?

GA 활성화 이후 별도 단계에서 타겟팅을 수집하는 방식이다. 내부적으로 `AGameplayAbilityTargetActor`를 스폰하고, 타겟 확정 시 클라→서버 RPC를 자동 처리한다.

```cpp
void UMyAbility::ActivateAbility(...)
{
    UAbilityTask_WaitTargetData* Task = UAbilityTask_WaitTargetData::WaitTargetData(
        this, NAME_None,
        EGameplayTargetingConfirmation::Instant,
        AGameplayAbilityTargetActor_SingleLineTrace::StaticClass());
    Task->ValidData.AddDynamic(this, &UMyAbility::OnTargetDataReady);
    Task->ReadyForActivation();
}
```

---

#### Lyra의 원거리 무기처럼 TargetData 전송 타이밍을 GA가 직접 제어하는 수동 방식은 어떻게 동작하는가?

`WaitTargetData` Task 없이 GA가 `AbilityTargetDataSetDelegate`를 직접 구독한다. Lyra 원거리 무기 GA(`LyraGameplayAbility_RangedWeapon`)가 이 방식을 사용한다.

```
ActivateAbility()
  └─ AbilityTargetDataSetDelegate 구독 (OnTargetDataReadyCallback)
  └─ PerformLocalTargeting() — 클라이언트 레이캐스트
  └─ FLyraGameplayAbilityTargetData_SingleTargetHit 생성
  └─ OnTargetDataReadyCallback() 직접 호출

OnTargetDataReadyCallback()
  ├─ [클라이언트] CallServerSetReplicatedTargetData() RPC 전송 (PredictionKey 포함)
  ├─ [서버] Delegate.Broadcast() → 동일 콜백 재진입
  └─ CommitAbility() → GE Apply → ConsumeClientReplicatedTargetData()
```

---

### TargetData는 왜 클라→서버 방향이 기본이며, 서버→클라 방향은 언제 사용하는가?

#### 클라이언트→서버 방향이 기본 설계인 이유는 무엇인가?

타겟팅 정보(어디를 겨냥했는가)는 클라이언트의 뷰포트에서 결정된다. `AbilityTargetDataMap` 키에 `PredictionKey`(클라 발급)가 포함되어 있어 설계 자체가 클라→서버 중심이다. 서버는 받은 TargetData를 검증 후 권위 있는 GE를 적용한다.

#### 서버→클라이언트 방향 TargetData는 어떤 경우에 사용하며 예측이 불가능한 이유는?

`AGameplayAbilityTargetActor`를 서버에서만 실행하도록 구성하면 서버가 타겟을 결정하고 클라에 결과를 전달한다. AI가 타겟팅을 결정하거나 서버 권위가 필요한 AOE 타겟팅에서 사용한다. 클라이언트 예측이 불가능하다 (`PredictionKey` 미사용). **Lyra는 이 방향을 사용하지 않는다.**

---

### 클라→서버 vs 서버→클라 TargetData 방향을 어떻게 비교할 수 있는가?

| | 클라 → 서버 | 서버 → 클라 |
|---|---|---|
| **주 사용처** | 플레이어 직접 조준/타겟팅 | AI 또는 서버 권위 타겟팅 |
| **예측** | 가능 (PredictionKey 사용) | 불가능 |
| **RPC** | `ServerSetReplicatedTargetData` | `ClientSetReplicatedTargetData` |
| **Lyra 사용** | O (원거리 무기) | X |
