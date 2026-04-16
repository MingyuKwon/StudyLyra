# Lyra GA 구현 예시

> 소스: `LyraGameplayAbility_Death.h/cpp`, `LyraGameplayAbility_Jump.h/cpp`, `LyraGameplayAbility_FromEquipment.h/cpp`, `LyraGamePhaseAbility.h/cpp`

---

## LyraGameplayAbility_Death

사망 처리 전용 GA. `Status.Death` 태그가 소유자에게 적용될 때 이벤트로 트리거된다.

### 특징

- **Trigger**: `Status.Death` 태그 → `GameplayEvent.Death` 이벤트
- **ActivationPolicy**: 이벤트 기반 (`OnGiveAbility`에서 Trigger 설정)
- **목적**: `LyraHealthComponent::StartDeath()` → GA 발동 → `LyraHealthComponent::FinishDeath()` 호출

### 사망 처리 흐름

```
ULyraHealthSet::PostGameplayEffectExecute()
    │ Health <= 0
    ▼
OnOutOfHealth 델리게이트
    ▼
ULyraHealthComponent::HandleOutOfHealth()
    │ Messaging: "GameplayEvent.Death" 전송
    │ GE: Status.Death 태그 부여 GE 적용
    ▼
ULyraGameplayAbility_Death::ActivateAbility()
    │ StartDeath() 호출 (DeathState = DeathStarted)
    │ 사망 애니메이션 재생
    │ 일정 시간 후
    ▼
FinishDeath() (DeathState = DeathFinished)
    │ Pawn 소멸 or 리스폰 요청
```

---

## LyraGameplayAbility_Jump

점프 능력. Character의 Jump()를 GAS로 래핑한다.

### 특징

- **NetExecutionPolicy**: `LocalPredicted` — 클라이언트가 먼저 점프, 서버 검증
- **ActivationPolicy**: `OnInputTriggered`
- **비용 없음** (쿨다운 없음)

### 예측 점프

```
클라이언트: TryActivateAbility()
    → Character::Jump() 즉시 호출 (예측)
    → 서버 RPC

서버: 검증 후 Character::Jump()
    → CharacterMovementComponent가 클라이언트와 동기화
```

CMC(CharacterMovementComponent)가 자체 예측을 지원하므로,
LocalPredicted 정책 + CMC 조합으로 자연스러운 점프 예측이 가능하다.

---

## LyraGameplayAbility_FromEquipment

장비 기반 GA의 베이스 클래스. 장비 인스턴스에 접근하는 방법을 제공한다.

```cpp
class ULyraGameplayAbility_FromEquipment : public ULyraGameplayAbility
{
public:
    // 이 GA를 부여한 장비 인스턴스 반환
    UFUNCTION(BlueprintCallable, Category = "Lyra|Ability")
    ULyraEquipmentInstance* GetAssociatedEquipment() const;

    // 장비 인스턴스에서 무기 인스턴스 반환
    UFUNCTION(BlueprintCallable, Category = "Lyra|Ability")
    ULyraWeaponInstance* GetAssociatedWeapon() const;
};
```

### 장비 → GA 연결 흐름

```
ULyraEquipmentManagerComponent::EquipItem()
    │
    ▼
ULyraEquipmentDefinition에서 AbilitySet 목록 읽기
    │
    ▼
AbilitySet->GiveToAbilitySystem(ASC, &GrantedHandles, EquipmentInstance)
    │ SourceObject = EquipmentInstance
    │
    ▼
GA::GetSourceObject() → EquipmentInstance
GA::GetAssociatedEquipment() → Cast<ULyraEquipmentInstance>(GetSourceObject())
```

`ULyraAbilitySet::GiveToAbilitySystem()`에서 `AbilitySpec.SourceObject = SourceObject`로
장비 인스턴스를 GA의 SourceObject로 설정하기 때문에, GA 내부에서 장비에 직접 접근 가능하다.

### ULyraGameplayAbility_RangedWeapon

`FromEquipment`를 상속받아 원거리 무기 발사 로직을 구현한다.

```cpp
class ULyraGameplayAbility_RangedWeapon : public ULyraGameplayAbility_FromEquipment
{
    // 발사 시작 (애니메이션 + 탄도 계산 + GE 적용)
    void StartRangedWeaponTargeting();
    
    // TargetData 수신 후 실제 데미지 GE 적용
    void OnTargetDataReadyCallback(const FGameplayAbilityTargetDataHandle& InData, ...);
};
```

---

## ULyraGamePhaseAbility

게임 페이즈(Phase) 전환을 제어하는 특수 GA.

```cpp
class ULyraGamePhaseAbility : public ULyraGameplayAbility
{
    // 이 GA가 나타내는 게임 페이즈 태그
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Game Phase")
    FGameplayTag GamePhaseTag;
};
```

### 페이즈 전환 방식

- `ULyraGamePhaseSubsystem`이 페이즈 GA를 부여/활성화
- 페이즈 GA 활성화 중: 현재 페이즈를 나타내는 GameplayTag 보유
- 새 페이즈 전환 시: 이전 페이즈 GA 취소 → 새 페이즈 GA 활성화
- **ActivationGroup**: `Exclusive_Blocking` — 한 번에 하나의 페이즈만 활성화

```
게임 시작
    → WarmupPhase GA 활성화 (GamePhaseTag = "GamePhase.Warmup")
    
준비 완료
    → WarmupPhase GA 취소
    → PlayingPhase GA 활성화 (GamePhaseTag = "GamePhase.Playing")
    
게임 종료
    → PlayingPhase GA 취소
    → PostGamePhase GA 활성화 (GamePhaseTag = "GamePhase.PostGame")
```

이를 통해 게임 상태 전환이 GAS 태그 시스템과 통합된다.
예: `Status.Death`처럼 `GamePhase.Playing` 태그 보유 여부로 특정 능력 활성화/차단 가능.
