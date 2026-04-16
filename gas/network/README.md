# 네트워크 & Prediction

> 참고: [GAS Doc 캐시](../cache/gas_doc_cache.md) | 소스: `LyraAbilitySystemComponent.h/cpp`, `LyraPlayerState.h`

---

## GAS 복제 구조

### ASC Replication Mode

| 모드 | GE 복제 대상 | 권장 상황 |
|---|---|---|
| `Full` | 모든 클라이언트 | 싱글플레이어 전용 |
| `Mixed` | Owner만 복제 | 플레이어 제어 캐릭터 (Lyra 기본) |
| `Minimal` | 복제 안 함 | AI 제어 캐릭터 |

> GameplayTag와 GameplayCue는 Replication Mode와 무관하게 항상 NetMulticast로 전달된다.

Lyra에서는 `ALyraPlayerState`에서 `ReplicationMode = EGameplayEffectReplicationMode::Mixed`로 설정한다.

### Owner/Avatar 분리의 복제 이점

```
ALyraPlayerState (Owner)
    └── ULyraAbilitySystemComponent  ← 항상 복제됨 (PlayerState는 리스폰 후에도 유지)
    
ALyraCharacter (Avatar)
    └── 리스폰 시 새로 생성됨
        → InitAbilityActorInfo(PlayerState, NewCharacter) 재호출
```

PlayerState는 항상 모든 클라이언트에 복제되므로, ASC를 PlayerState에 두면 리스폰 후에도
Attribute 상태와 GE가 유지된다.

---

## Ability 활성화 복제 흐름

### 로컬 예측(LocalPredicted) 방식

```
클라이언트:
  TryActivateAbility()
      → InternalTryActivateAbility()
          → CanActivateAbility() [로컬 체크]
          → CallServerTryActivateAbility(PredictionKey)  [RPC]
          → CallActivateAbility()
              → PreActivate()
              → ActivateAbility()  ← 클라이언트가 먼저 실행!

서버:
  ServerTryActivateAbility(PredictionKey) 수신
      → InternalTryActivateAbility()
          → CanActivateAbility() [서버 체크]
          ↓ 성공
          → ClientActivateAbilitySucceed()  [RPC]
          → CallActivateAbility()
              → ActivateAbility()
          ↓ 실패
          → ClientActivateAbilityFailed()  [RPC]
              → 클라이언트: GA 즉시 종료 + 예측 롤백
```

### Lyra에서의 AbilityFailed 처리

```cpp
// 서버: 클라이언트에게 실패 알림
void ULyraAbilitySystemComponent::NotifyAbilityFailed(...)
{
    if (!Avatar->IsLocallyControlled() && Ability->IsSupportedForNetworking())
    {
        ClientNotifyAbilityFailed(Ability, FailureReason);  // Unreliable RPC
        return;
    }
    HandleAbilityFailed(Ability, FailureReason);
}

// 클라이언트: 실패 메시지 처리
void ULyraAbilitySystemComponent::HandleAbilityFailed(...)
{
    if (const ULyraGameplayAbility* LyraAbility = Cast<const ULyraGameplayAbility>(Ability))
    {
        LyraAbility->OnAbilityFailedToActivate(FailureReason);
        // → GameplayMessageSubsystem으로 실패 메시지 브로드캐스트
        // → 실패 애니메이션 몽타주 재생 가능
    }
}
```

---

## Prediction Key

### 동작 원리

```
1. 클라이언트: Activation Prediction Key 생성 (임시 ID)
2. CallServerTryActivateAbility(PredictionKey) 전송
3. 클라이언트: 유효 키 범위 내 GE에 키 태그 (예측 GE)
4. 서버: 수신한 키로 GE에 태그 → 클라이언트로 복제
5. 클라이언트: 서버에서 같은 키의 GE 받음 → 예측 GE 제거 (정확한 예측)
6. 클라이언트: Replicated Key stale 처리 → stale 키 GE 모두 제거 (서버 복제본 유지)
```

### Scoped Prediction Window

AbilityTask 콜백 시점에는 이미 원래 Prediction Key가 만료된다.
새 예측 창이 필요하면 `WaitNetSync` AbilityTask를 사용:

```cpp
// WaitNetSync(OnlyServerWait) 사용 패턴
UAbilityTask_WaitNetSync* WaitTask = UAbilityTask_WaitNetSync::WaitNetSync(this, EWaitNetSyncPoint::OnlyServerWait);
WaitTask->OnSync.AddDynamic(this, &UMyAbility::OnSyncPoint);
WaitTask->ReadyForActivation();

// OnSyncPoint에서: 새 Scoped Prediction Key가 이미 생성됨
// 이 범위 내에서 적용되는 GE는 예측 가능
```

---

## 예측 가능한 것 / 불가능한 것

### 예측 가능 (클라이언트가 먼저 실행)
- Ability 활성화
- 트리거 이벤트
- GE 적용
- Attribute 수정 (ExecCalc 제외)
- GameplayTag 수정
- GameplayCue
- 애니메이션 몽타주
- 이동 (CharacterMovementComponent와 연동)

### 예측 불가 (서버만 실행)
- **GE 제거** — 우회: 반대 효과 GE를 예측 적용 후 둘 다 제거
- **GE 주기적 효과** (Periodic GE)
- **ExecCalc** (`#if WITH_SERVER_CODE`)
- **Cooldown** (Duration GE + Tag 패턴이므로 GE 제거 예측 불가)
- **Actor 스폰** (`SpawnActor` AbilityTask는 서버 전용)

---

## Lyra에서의 구현

### Ability Batching (RPC 최적화)

여러 RPC를 1개로 압축하는 패턴:

```cpp
// GA에서 오버라이드
virtual bool ShouldDoServerAbilityRPCBatch() const override { return true; }

// 활성화 시
{
    FScopedServerAbilityRPCBatcher ScopedRPCBatcher(this, CurrentSpecHandle);
    TryActivateAbility(CurrentSpecHandle);
    // Activate + TargetData + End → 1 RPC
}
```

### 입력→능력 연결의 예측

```
클라이언트 키 입력
    │
    ▼
ULyraHeroComponent::Input_AbilityInputTagPressed(Tag)
    │
    ▼
ULyraAbilitySystemComponent::AbilityInputTagPressed(Tag)
    │ InputPressedSpecHandles에 추가
    │
    ▼ (다음 프레임)
ULyraAbilitySystemComponent::ProcessAbilityInput()
    │ TryActivateAbility() 호출
    │ → LocalPredicted 정책이면 클라이언트 즉시 실행 + 서버에 RPC
```

### AttributeSet 복제 (REPNOTIFY_Always)

```cpp
// LyraHealthSet에서
GAMEPLAYATTRIBUTE_REPNOTIFY(ULyraHealthSet, Health, OldHealth)
// → SetBaseAttributeValueFromReplication() 내부 호출
// → 예측된 클라이언트 값을 서버 값으로 되감음(rewind)
// REPNOTIFY_Always 필수: 예측값과 서버값이 같아도 OnRep 강제 호출
```

---

## 알려진 한계 (Dave Ratti Q&A)

- **Cooldown 예측 불가** → 높은 지연 플레이어 불이익 (Fortnite는 자체 관리)
- **GE 제거 예측 불가** → 우회: 반대 효과 GE 예측 적용 후 둘 다 제거
- **WaitNetSync 치팅 취약점**: 클라이언트가 서버 신호 지연으로 타이밍 조작 가능
  → Paragon은 최대 대기 시간 타임아웃으로 대응
- **GAS V2 계획**: GE 제거 예측, 지연 보정, RPC 배치 일반화 (미구현)
