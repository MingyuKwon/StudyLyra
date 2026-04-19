# ULyraGameplayAbility

> 출처: `Source/LyraGame/AbilitySystem/Abilities/LyraGameplayAbility.h/.cpp`

---

## 기본 설정 (생성자)

```cpp
// LyraGameplayAbility.cpp
ULyraGameplayAbility::ULyraGameplayAbility(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
    ReplicationPolicy  = EGameplayAbilityReplicationPolicy::ReplicateNo;
    InstancingPolicy   = EGameplayAbilityInstancingPolicy::InstancedPerActor; // Actor당 인스턴스 1개
    NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::LocalPredicted;  // 로컬 예측
    NetSecurityPolicy  = EGameplayAbilityNetSecurityPolicy::ClientOrServer;

    ActivationPolicy = ELyraAbilityActivationPolicy::OnInputTriggered; // 기본값
    ActivationGroup  = ELyraAbilityActivationGroup::Independent;       // 기본값
}
```

---

## 활성화 정책 (ActivationPolicy)

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationPolicy : uint8
{
    OnInputTriggered,  // 입력 태그 트리거 시 한 번 활성화
    WhileInputActive,  // 입력 유지 중 계속 활성화 시도
    OnSpawn,           // 아바타 할당 즉시 자동 활성화
};
```

| 정책 | 사용 예 | 동작 |
|---|---|---|
| `OnInputTriggered` | ADS, 수류탄 | 버튼을 누르면 한 번, 자동 재활성화 없음 |
| `WhileInputActive` | 샷건 발사 | 입력 유지 중 반복 활성화 시도 |
| `OnSpawn` | 자동 재장전 | 폰 빙의 즉시 활성화, 빙의 해제 전까지 유지 |

`OnSpawn`은 `OnGiveAbility()`에서 즉시 시도한다:

```cpp
// LyraGameplayAbility.cpp
void ULyraGameplayAbility::OnGiveAbility(
    const FGameplayAbilityActorInfo* ActorInfo, const FGameplayAbilitySpec& Spec)
{
    Super::OnGiveAbility(ActorInfo, Spec);
    K2_OnAbilityAdded();           // BP 이벤트 호출
    TryActivateAbilityOnSpawn(ActorInfo, Spec);  // OnSpawn이면 즉시 활성화 시도
}

void ULyraGameplayAbility::TryActivateAbilityOnSpawn(
    const FGameplayAbilityActorInfo* ActorInfo, const FGameplayAbilitySpec& Spec) const
{
    if (ActorInfo && !Spec.IsActive() && (ActivationPolicy == ELyraAbilityActivationPolicy::OnSpawn))
    {
        UAbilitySystemComponent* ASC = ActorInfo->AbilitySystemComponent.Get();
        const AActor* AvatarActor = ActorInfo->AvatarActor.Get();

        // TearOff 중이거나 소멸 예정이면 건너뜀
        if (ASC && AvatarActor && !AvatarActor->GetTearOff() && (AvatarActor->GetLifeSpan() <= 0.0f))
        {
            const bool bClientShouldActivate = ActorInfo->IsLocallyControlled() && bIsLocalExecution;
            const bool bServerShouldActivate = ActorInfo->IsNetAuthority() && bIsServerExecution;

            if (bClientShouldActivate || bServerShouldActivate)
                ASC->TryActivateAbility(Spec.Handle);
        }
    }
}
```

---

## 활성화 그룹 (ActivationGroup)

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationGroup : uint8
{
    Independent,           // 다른 어빌리티와 무관하게 자유롭게 실행
    Exclusive_Replaceable, // 다른 Exclusive 어빌리티가 오면 취소됨
    Exclusive_Blocking,    // 실행 중 다른 Exclusive 어빌리티 차단
};
```

`CanActivateAbility()`에서 그룹 충돌 검사:

```cpp
// LyraGameplayAbility.cpp
bool ULyraGameplayAbility::CanActivateAbility(...) const
{
    if (!Super::CanActivateAbility(...)) return false;

    ULyraAbilitySystemComponent* LyraASC = CastChecked<ULyraAbilitySystemComponent>(...);
    // 현재 Exclusive_Blocking 어빌리티가 실행 중이면 차단
    if (LyraASC->IsActivationGroupBlocked(ActivationGroup))
    {
        if (OptionalRelevantTags)
            OptionalRelevantTags->AddTag(LyraGameplayTags::Ability_ActivateFail_ActivationGroup);
        return false;
    }
    return true;
}
```

`Exclusive_Replaceable`은 `SetCanBeCanceled(false)` 호출 시 오류 처리:

```cpp
void ULyraGameplayAbility::SetCanBeCanceled(bool bCanBeCanceled)
{
    // Replaceable은 항상 취소 가능해야 함 — 방어 코드
    if (!bCanBeCanceled && (ActivationGroup == ELyraAbilityActivationGroup::Exclusive_Replaceable))
    {
        UE_LOG(LogLyraAbilitySystem, Error, TEXT("SetCanBeCanceled: Ability [%s] cannot block canceling because its activation group is replaceable."), *GetName());
        return;
    }
    Super::SetCanBeCanceled(bCanBeCanceled);
}
```

---

## 추가 비용 (AdditionalCosts)

기본 GAS는 GE 하나만 비용 가능. Lyra는 `ULyraAbilityCost` 배열로 복수 비용을 지원한다.

```cpp
// LyraGameplayAbility.h
UPROPERTY(EditDefaultsOnly, Instanced, Category = Costs)
TArray<TObjectPtr<ULyraAbilityCost>> AdditionalCosts;
```

비용 확인과 지불이 표준 GAS 흐름에 통합되어 있다:

```cpp
// LyraGameplayAbility.cpp — CheckCost
bool ULyraGameplayAbility::CheckCost(...) const
{
    if (!Super::CheckCost(...)) return false;  // 기본 GE 비용 먼저 확인

    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
    {
        if (!AdditionalCost->CheckCost(this, Handle, ActorInfo, OptionalRelevantTags))
            return false;  // 하나라도 실패하면 전체 차단
    }
    return true;
}

// LyraGameplayAbility.cpp — ApplyCost
void ULyraGameplayAbility::ApplyCost(...) const
{
    Super::ApplyCost(...);

    for (const TObjectPtr<ULyraAbilityCost>& AdditionalCost : AdditionalCosts)
    {
        if (AdditionalCost->ShouldOnlyApplyCostOnHit())
        {
            // 타깃 적중 시에만 비용 지불 (탄약 절약 등)
            if (!bAbilityHitTarget) continue;
        }
        AdditionalCost->ApplyCost(this, Handle, ActorInfo, ActivationInfo);
    }
}
```

### 구현체

| 클래스 | 동작 |
|---|---|
| `ULyraAbilityCost_ItemTagStack` | 장비 아이템의 GameplayTag 스택 소모. `Lyra.ShooterGame.Weapon.MagazineAmmo` 스택을 발사마다 감소 |
| `ULyraAbilityCost_InventoryItem` | 인벤토리에서 아이템 소모. 소모품에 사용 |
| `ULyraAbilityCost_PlayerTagStack` | PlayerState의 GameplayTag 스택 소모 |

---

## Blueprint 이벤트 3종

기존 GAS `ActivateAbility`/`EndAbility`와 별개인 생명주기 훅이다.

```cpp
// LyraGameplayAbility.h

// 어빌리티가 ASC에 부여될 때 — Avatar/InputComponent 아직 없을 수 있음
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnAbilityAdded")
void K2_OnAbilityAdded();

// 폰이 완전히 초기화 완료 — Avatar + InputComponent 모두 유효
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnPawnAvatarSet")
void K2_OnPawnAvatarSet();

// ASC에서 어빌리티가 제거될 때 — 폰 파괴, 빙의 해제 등
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnAbilityRemoved")
void K2_OnAbilityRemoved();
```

C++ 훅에서 BP 이벤트를 호출하는 연결:

```cpp
// LyraGameplayAbility.cpp
void ULyraGameplayAbility::OnGiveAbility(...) // 부여 시
{
    Super::OnGiveAbility(ActorInfo, Spec);
    K2_OnAbilityAdded();              // ← BP OnAbilityAdded 호출
    TryActivateAbilityOnSpawn(ActorInfo, Spec);
}

void ULyraGameplayAbility::OnRemoveAbility(...) // 제거 시
{
    K2_OnAbilityRemoved();            // ← BP OnAbilityRemoved 호출 (Super 전에!)
    Super::OnRemoveAbility(ActorInfo, Spec);
}

void ULyraGameplayAbility::OnPawnAvatarSet() // 폰 초기화 완료 시
{
    K2_OnPawnAvatarSet();             // ← BP OnPawnAvatarSet 호출
}
```

**사용 패턴**:
- `OnAbilityAdded` → UI 위젯 UIExtensionSubsystem에 등록 (핸들 저장)
- `OnPawnAvatarSet` → 폰 의존 초기화 (카메라 설정, 무기 참조 등)
- `OnAbilityRemoved` → 위젯 등록 해제, 클린업

---

## 카메라 모드 오버라이드

```cpp
// LyraGameplayAbility.cpp
void ULyraGameplayAbility::SetCameraMode(TSubclassOf<ULyraCameraMode> CameraMode)
{
    if (ULyraHeroComponent* HeroComponent = GetHeroComponentFromActorInfo())
    {
        HeroComponent->SetAbilityCameraMode(CameraMode, CurrentSpecHandle);
        ActiveCameraMode = CameraMode;
    }
}

void ULyraGameplayAbility::ClearCameraMode()
{
    if (ActiveCameraMode)
    {
        if (ULyraHeroComponent* HeroComponent = GetHeroComponentFromActorInfo())
            HeroComponent->ClearAbilityCameraMode(CurrentSpecHandle);
        ActiveCameraMode = nullptr;
    }
}

// EndAbility에서 자동 호출 — 어빌리티 종료 시 카메라가 항상 원복됨
void ULyraGameplayAbility::EndAbility(...)
{
    ClearCameraMode();  // ← 항상 클린업
    Super::EndAbility(...);
}
```

---

## 활성화 실패 처리

```cpp
// LyraGameplayAbility.cpp
void ULyraGameplayAbility::NativeOnAbilityFailedToActivate(
    const FGameplayTagContainer& FailedReason) const
{
    for (FGameplayTag Reason : FailedReason)
    {
        // 실패 태그에 매핑된 사용자 메시지 브로드캐스트
        if (const FText* pUserFacingMessage = FailureTagToUserFacingMessages.Find(Reason))
        {
            FLyraAbilitySimpleFailureMessage Message;
            Message.PlayerController = GetActorInfo().PlayerController.Get();
            Message.FailureTags = FailedReason;
            Message.UserFacingReason = *pUserFacingMessage;

            UGameplayMessageSubsystem& MessageSystem = UGameplayMessageSubsystem::Get(GetWorld());
            MessageSystem.BroadcastMessage(TAG_ABILITY_SIMPLE_FAILURE_MESSAGE, Message);
        }

        // 실패 태그에 매핑된 애니메이션 몽타주 재생 (예: 탄약 없을 때 dry fire 소리)
        if (UAnimMontage* pMontage = FailureTagToAnimMontage.FindRef(Reason))
        {
            FLyraAbilityMontageFailureMessage Message;
            Message.PlayerController = GetActorInfo().PlayerController.Get();
            Message.AvatarActor = GetActorInfo().AvatarActor.Get();
            Message.FailureTags = FailedReason;
            Message.FailureMontage = pMontage;

            UGameplayMessageSubsystem& MessageSystem = UGameplayMessageSubsystem::Get(GetWorld());
            MessageSystem.BroadcastMessage(TAG_ABILITY_PLAY_MONTAGE_FAILURE_MESSAGE, Message);
        }
    }
}
```

---

## 주요 네이티브 서브클래스

| 클래스 | 역할 |
|---|---|
| `ULyraGameplayAbility_Death` | 사망 이벤트 트리거, 모든 어빌리티 취소 후 HealthComponent에 사망 시작 알림 |
| `ULyraGameplayAbility_Jump` | 유효한 로컬 제어 폰인지 확인 후 CharacterMovement에 Jump/StopJumping 입력 |
| `ULyraGameplayAbility_Reset` | 폰을 초기 스폰 상태로 즉시 리셋, 모든 어빌리티 취소 |
| `ULyraGameplayAbility_FromEquipment` | 장비 시스템 접근, 관련 아이템 검색 |
| `ULyraGameplayAbility_RangedWeapon` | 발사 원뿔 계산, 레이캐스팅, 탄약 추적 |
