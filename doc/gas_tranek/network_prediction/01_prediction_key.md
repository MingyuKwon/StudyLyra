# Prediction Key

> **GASDoc**: 4.10.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-p"></a>
### GAS에서 클라이언트 측 예측이란 무엇이며 예측 가능한 것과 불가능한 것은 어떻게 나뉘는가?

클라이언트 측 예측이란 클라이언트가 서버의 허가를 기다리지 않고 `GameplayAbility`를 활성화하고 `GameplayEffect`를 적용하는 것이다. 서버가 허가할 것이라 "예측"하고 먼저 실행하며, 서버가 오예측(misprediction)으로 판단하면 클라이언트가 변경사항을 롤백한다.

Epic의 기본 방침: **"빠져나갈 수 있는 것만 예측"**. Paragon과 Fortnite는 데미지를 예측하지 않는다.

**예측되는 것:**
- Ability 활성화, Triggered 이벤트
- GameplayEffect 적용 (Attribute 수정, GameplayTag 수정)
- GameplayCue 이벤트
- 몽타주, 이동 (CharacterMovement 내장)

**예측되지 않는 것:**
- GameplayEffect 제거
- GameplayEffect 주기적 효과(도트 틱)

`GameplayEffect` 제거를 예측할 수 없기 때문에 **쿨다운을 완전히 예측할 수 없다**. 레이턴시가 높은 클라이언트는 서버의 Cooldown GE가 제거되기까지 더 오래 기다려야 하므로 발사 속도가 느려진다. Fortnite는 Cooldown GE 대신 커스텀 기록 방식으로 이를 회피한다.

GE 제거 예측 우회책: 이동 속도 40% 감소를 예측 제거하고 싶다면, 40% 버프를 예측 적용한 뒤 두 GE를 동시에 제거한다. 모든 상황에 적합하지는 않다.

> 데미지 예측은 권장하지 않는다. 오예측 시 적 체력이 다시 올라가거나, 사망 예측이 틀리면 래그돌이 멈추고 다시 공격해오는 어색한 상황이 발생한다.

<a name="concepts-p-key"></a>
#### Prediction Key는 어떻게 생성되어 서버와 클라이언트 간에 어떤 과정으로 검증되는가?

Prediction Key는 클라이언트가 `GameplayAbility` 활성화 시 생성하는 정수 식별자다.

**흐름:**
1. 클라이언트: Prediction Key 생성 → 이를 `Activation Prediction Key`라 부름
2. 클라이언트: `CallServerTryActivateAbility()`로 Key를 서버에 전송
3. 클라이언트: Key가 유효한 동안 적용하는 모든 GE에 Key를 태깅
4. 서버: Key를 수신하고, 자신이 적용하는 모든 GE에 동일한 Key를 태깅
5. 서버: Key를 클라이언트에게 복제
6. 클라이언트: 같은 Key를 가진 복제된 GE를 수신하면 예측 성공 → 잠시 동안 GE 복사본이 두 개 존재
7. 클라이언트: 복제된 Key가 돌아오면 stale(만료) 처리 → stale Key로 적용한 예측 GE 제거
8. 서버에서 대응하는 복제본이 없는 GE는 오예측으로 처리되어 롤백

Prediction Key는 단 하나의 프레임에만 유효하다고 생각하면 된다. Latent AbilityTask 콜백에서는 유효하지 않으며, 내장 Sync Point가 있는 AbilityTask만 예외다.

---

### Activation Prediction Key와 Scoped Prediction Key는 각각 언제 생성되며 유효 범위는 어떻게 다른가?

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`  
**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`

| 구분 | Activation Prediction Key | Scoped Prediction Key |
|---|---|---|
| 생성 위치 | `InternalTryActivateAbility()` | 각 콜백 진입 시 `FScopedPredictionWindow` |
| 유효 범위 | `ActivateAbility()` 콜스택 안 | 해당 콜백의 동기 실행 범위 안 |
| 주요 용도 | GA 인스턴스 식별자 + 초기 GE 태깅 | 콜백 이후 GE 태깅 |
| 취득 방법 | `GetActivationPredictionKey()` | `ASC->ScopedPredictionKey` |

```cpp
// InternalTryActivateAbility — GA 활성화 시 Activation Key 생성
FScopedPredictionWindow ScopedPredictionWindow(this, true); // Key#1 생성
ActivationInfo.SetPredicting(ScopedPredictionKey);          // Key#1을 Activation Key로 저장
CallServerTryActivateAbility(Handle, InputPressed, ScopedPredictionKey); // 서버 RPC
```

---

### Dependent Key 체인은 어떻게 구성되며 서버 거부 시 모든 단계가 연쇄 롤백되는 원리는?

`FScopedPredictionWindow(ASC, bCanGenerateNewKey=true)` 를 클라이언트에서 생성하면 내부적으로:

```cpp
InAbilitySystemComponent->ScopedPredictionKey.GenerateDependentPredictionKey();
```

`GenerateDependentPredictionKey()` 구현:

```cpp
void FPredictionKey::GenerateDependentPredictionKey()
{
    KeyType Previous = Current;      // Key#1 기억
    if (Base == 0) Base = Current;   // Base = Key#1

    GenerateNewPredictionKey();      // Current = Key#2 (완전히 새 ID)

    // ★ 핵심: "Key#1이 Reject되면 Key#2도 Reject" 종속 관계 등록
    FPredictionKeyDelegates::AddDependency(Current/*Key#2*/, Previous/*Key#1*/);
}
```

`AddDependency` 내부:

```cpp
void AddDependency(KeyType ThisKey/*Key#2*/, KeyType DependsOn/*Key#1*/)
{
    // Key#1 Rejected → Key#2도 Reject (연쇄 롤백)
    NewRejectedDelegate(DependsOn).BindStatic(&Reject, ThisKey);

    // Key#2 CaughtUp(서버 확인) → Key#1도 CaughtUp (역방향 확인)
    NewCaughtUpDelegate(ThisKey).BindStatic(&CatchUpTo, DependsOn);
}
```

> **이 종속 관계는 클라이언트에만 존재한다.** 서버는 Key 체인을 모른다.

---

### 서버가 GA를 거부했을 때 클라이언트에서 전체 롤백은 어떤 순서로 일어나는가?

시나리오: GA 예측 활성화 후 `WaitInputPress` 콜백까지 실행, 이후 서버가 GA를 거부.

```
서버                                 클라이언트
──────────────────────────────────────────────────────
ServerTryActivateAbility(Key#1)
  검사 실패
  ClientActivateAbilityFailed(Key#1) ──────────────→ ClientActivateAbilityFailed_Impl(Key#1)
                                                        │
                                                        ├─ BroadcastRejectedDelegate(Key#1)
                                                        │    ├─ Key#1 GE들 롤백
                                                        │    └─ AddDependency가 등록한
                                                        │        Reject(Key#2) 호출
                                                        │         └─ Key#2 GE들 롤백
                                                        │
                                                        └─ EndAbility()
                                                             └─ WaitInputPress.EndTask()
```

`ClientActivateAbilityFailed_Implementation` 코드:
```cpp
void UAbilitySystemComponent::ClientActivateAbilityFailed_Implementation(
    FGameplayAbilitySpecHandle Handle, int16 PredictionKey)
{
    if (PredictionKey > 0)
        FPredictionKeyDelegates::BroadcastRejectedDelegate(PredictionKey); // ← Key#1 거부 발동

    FGameplayAbilitySpec* Spec = FindAbilitySpecFromHandle(Handle);
    // ... GA 인스턴스 찾아서 EndAbility 호출
}
```

---

### GA 거부 후 뒤늦게 도착한 Input RPC는 어떻게 처리되며 사이드 이펙트가 없는 이유는?

서버가 GA를 거부한 뒤 `ServerSetReplicatedEvent(InputPressed, Key#1, Key#2)` RPC가 도착한 경우:

```cpp
// ServerSetReplicatedEvent_Implementation
FScopedPredictionWindow ScopedPrediction(this, CurrentPredictionKey); // Key#2 세팅
InvokeReplicatedEvent(EventType, AbilityHandle, Key#1, Key#2);
// → (Handle, Key#1) 슬롯의 Delegate를 Broadcast()
```

GA가 이미 종료되어 `WaitInputPress`의 `OnPressCallback` 델리게이트가 해제된 상태이므로, `Delegate.IsBound() == false` → Broadcast 무시. 이벤트 데이터는 `AbilityTargetDataMap`에 캐시되지만 아무도 소비하지 않아 사이드 이펙트 없음.

---

### 예측 키 롤백의 각 단계를 어떻게 요약할 수 있는가?

| 단계 | 내부 동작 |
|---|---|
| 서버 GA 거부 | `ClientActivateAbilityFailed(Key#1)` RPC |
| Key#1 Reject | Key#1 GE 제거 + `AddDependency` 연쇄 발동 |
| Key#2 Reject | Key#2 GE 제거 (WaitInput 콜백 이후 적용분 포함) |
| GA 종료 | `EndAbility()` → 모든 AbilityTask 정리 |
| 뒤늦은 Input RPC | 델리게이트 없음 → 무시, 사이드 이펙트 없음 |
| Key#3, #4... | 같은 방식으로 전부 연쇄 Reject |

**연쇄 롤백은 서버 통신 없이 클라이언트 내부 `FPredictionKeyDelegates` 맵에서 순수하게 처리된다.**
