# GA 생명주기

> 소스: `LyraGameplayAbility.cpp`

---

## 전체 생명주기

```
ASC::GiveAbility(AbilitySpec)
    │ 서버에서만. 소유 클라이언트로 Spec 복제됨
    │
    ▼
UGameplayAbility::OnGiveAbility(ActorInfo, Spec)
    │ Lyra 확장: K2_OnAbilityAdded() BP 이벤트 발행
    │            TryActivateAbilityOnSpawn() 호출 (OnSpawn 정책)
    │
    ▼ (능력 활성화 시도)
UGameplayAbility::CanActivateAbility()  [조건 체크]
    │ 태그 조건, ActivationGroup 차단 여부, Cost 체크
    │
    ▼ (성공 시)
UGameplayAbility::PreActivate()
    │ ActivationOwnedTags 부여, Cooldown/Cost GE 적용 준비
    │
    ▼
ULyraGameplayAbility::ActivateAbility()
    │ Lyra 확장: Super::ActivateAbility() 호출
    │ 실제 능력 로직 (서브클래스에서 구현)
    │
    ▼ (능력 종료 시)
ULyraGameplayAbility::EndAbility()
    │ Lyra 확장: ClearCameraMode() 호출
    │            Super::EndAbility() 호출
    │
    ▼
UGameplayAbility::OnRemoveAbility()
    │ Lyra 확장: K2_OnAbilityRemoved() BP 이벤트 발행
```

---

## 주요 콜백

### OnGiveAbility (부여 시)

```cpp
void ULyraGameplayAbility::OnGiveAbility(const FGameplayAbilityActorInfo* ActorInfo, 
                                          const FGameplayAbilitySpec& Spec)
{
    Super::OnGiveAbility(ActorInfo, Spec);
    K2_OnAbilityAdded();           // BP: OnAbilityAdded 이벤트
    TryActivateAbilityOnSpawn(ActorInfo, Spec);  // OnSpawn 정책 처리
}
```

### OnPawnAvatarSet (새 Avatar 설정 시)

```cpp
void ULyraGameplayAbility::OnPawnAvatarSet()
{
    K2_OnPawnAvatarSet();   // BP: OnPawnAvatarSet 이벤트
}
// ASC::InitAbilityActorInfo()에서 모든 GA 인스턴스에 대해 호출됨
```

패시브 GA를 구현할 때 유용:
```cpp
// Blueprint 또는 C++에서 Override
void UMyPassiveAbility::K2_OnPawnAvatarSet()
{
    // Avatar가 설정된 즉시 능력 활성화 (OnSpawn 정책 대체)
    ASC->TryActivateAbility(CurrentSpecHandle);
}
```

### EndAbility (종료 시)

```cpp
void ULyraGameplayAbility::EndAbility(...)
{
    ClearCameraMode();   // 능력이 설정한 카메라 모드 자동 해제
    Super::EndAbility(...);
}
```

카메라 모드를 설정한 GA는 `EndAbility()`에서 자동으로 해제되므로 별도 처리 불필요.

---

## 능력 실패 처리

### NativeOnAbilityFailedToActivate

```cpp
void ULyraGameplayAbility::NativeOnAbilityFailedToActivate(const FGameplayTagContainer& FailedReason) const
{
    // 1. 실패 태그에 매핑된 유저 메시지 브로드캐스트
    for (FGameplayTag Reason : FailedReason)
    {
        if (const FText* pUserFacingMessage = FailureTagToUserFacingMessages.Find(Reason))
        {
            // GameplayMessageSubsystem으로 브로드캐스트
            UGameplayMessageSubsystem& MessageSystem = UGameplayMessageSubsystem::Get(GetWorld());
            MessageSystem.BroadcastMessage(TAG_ABILITY_SIMPLE_FAILURE_MESSAGE, Message);
        }
        
        // 2. 실패 태그에 매핑된 애니메이션 몽타주 재생
        if (UAnimMontage* pMontage = FailureTagToAnimMontage.FindRef(Reason))
        {
            MessageSystem.BroadcastMessage(TAG_ABILITY_PLAY_MONTAGE_FAILURE_MESSAGE, Message);
        }
    }
}
```

에디터에서 설정 가능한 필드:
```cpp
// 실패 태그 → 사용자 메시지 텍스트 (HUD에 표시)
TMap<FGameplayTag, FText> FailureTagToUserFacingMessages;

// 실패 태그 → 재생할 애니메이션 몽타주 (예: "탄약 없음" 제스처)
TMap<FGameplayTag, UAnimMontage*> FailureTagToAnimMontage;
```

---

## MakeEffectContext — Lyra 확장

```cpp
FGameplayEffectContextHandle ULyraGameplayAbility::MakeEffectContext(...) const
{
    FGameplayEffectContextHandle ContextHandle = Super::MakeEffectContext(...);
    
    FLyraGameplayEffectContext* EffectContext = FLyraGameplayEffectContext::ExtractEffectContext(ContextHandle);
    
    // AbilitySource (거리 감쇠, 물리 재질 감쇠 인터페이스)
    EffectContext->SetAbilitySource(AbilitySource, SourceLevel);
    EffectContext->AddInstigator(Instigator, EffectCauser);
    EffectContext->AddSourceObject(SourceObject);
    
    return ContextHandle;
}
```

### ApplyAbilityTagsToGameplayEffectSpec — 물리 재질 태그 전달

```cpp
void ULyraGameplayAbility::ApplyAbilityTagsToGameplayEffectSpec(FGameplayEffectSpec& Spec, ...) const
{
    Super::ApplyAbilityTagsToGameplayEffectSpec(Spec, AbilitySpec);
    
    // HitResult의 물리 재질 태그를 GE Spec에 포함
    if (const FHitResult* HitResult = Spec.GetContext().GetHitResult())
    {
        if (const UPhysicalMaterialWithTags* PhysMatWithTags = 
            Cast<UPhysicalMaterialWithTags>(HitResult->PhysMaterial.Get()))
        {
            Spec.CapturedTargetTags.GetSpecTags().AppendTags(PhysMatWithTags->Tags);
        }
    }
}
```

이를 통해 ExecCalc에서 물리 재질 정보(헤드샷, 약점 등)를 TagContainer로 읽을 수 있다.
