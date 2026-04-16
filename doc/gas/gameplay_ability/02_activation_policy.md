# ActivationPolicy — 능력 활성화 방식

> 소스: `LyraGameplayAbility.h`, `LyraAbilitySystemComponent.cpp`

---

## ELyraAbilityActivationPolicy

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationPolicy : uint8
{
    OnInputTriggered,   // 입력 발생 시 1회 활성화 시도
    WhileInputActive,   // 입력 유지 중 매 프레임 활성화 시도
    OnSpawn             // Pawn Avatar 설정 시 자동 활성화
};
```

---

## OnInputTriggered

버튼을 누르는 순간 1회 활성화를 시도한다.

```
키 눌림 → InputPressedSpecHandles 추가
           → ProcessAbilityInput()에서 TryActivateAbility() 1회
```

활성화 중인 상태에서 다시 입력이 들어오면 `AbilitySpecInputPressed()`로 이벤트만 전달된다.
(AbilityTask `WaitInputPress`가 이를 수신 가능)

**사용 예시**: 기본 공격, 스킬 사용, 상호작용, 점프

---

## WhileInputActive

입력을 누르고 있는 동안 매 프레임 활성화를 시도한다. (단, 이미 활성화 중이면 시도하지 않음)

```
키 누름 → InputHeldSpecHandles 추가
키 유지 → 매 프레임 ProcessAbilityInput()
           → !IsActive() → AbilitiesToActivate 추가 → TryActivateAbility()
키 해제 → InputHeldSpecHandles에서 제거
```

**사용 예시**: 달리기(Sprint), 웅크리기(Crouch), 스캔/조준

---

## OnSpawn

Pawn Avatar가 ASC에 설정될 때 자동으로 활성화된다. 입력과 무관.

### 활성화 시점

```cpp
// LyraAbilitySystemComponent::InitAbilityActorInfo()에서
TryActivateAbilitiesOnSpawn();  // 모든 OnSpawn 정책 GA 활성화

// LyraGameplayAbility::OnGiveAbility()에서도
TryActivateAbilityOnSpawn(ActorInfo, Spec);  // Ability 부여 시에도 체크
```

### TryActivateAbilityOnSpawn 구현

```cpp
void ULyraGameplayAbility::TryActivateAbilityOnSpawn(
    const FGameplayAbilityActorInfo* ActorInfo, 
    const FGameplayAbilitySpec& Spec) const
{
    if (ActorInfo && !Spec.IsActive() && 
        (ActivationPolicy == ELyraAbilityActivationPolicy::OnSpawn))
    {
        UAbilitySystemComponent* ASC = ActorInfo->AbilitySystemComponent.Get();
        const AActor* AvatarActor = ActorInfo->AvatarActor.Get();
        
        // TearOff되거나 LifeSpan이 설정된 임시 Actor는 스킵
        if (ASC && AvatarActor && !AvatarActor->GetTearOff() && 
            (AvatarActor->GetLifeSpan() <= 0.0f))
        {
            // NetExecution Policy에 따라 어느 쪽에서 활성화할지 결정
            const bool bClientShouldActivate = ActorInfo->IsLocallyControlled() && bIsLocalExecution;
            const bool bServerShouldActivate = ActorInfo->IsNetAuthority() && bIsServerExecution;
            
            if (bClientShouldActivate || bServerShouldActivate)
                ASC->TryActivateAbility(Spec.Handle);
        }
    }
}
```

**사용 예시**: 패시브 GA (체력 재생, 항상 켜진 효과), 리스폰 후 자동 적용할 능력

---

## ProcessAbilityInput 전체 로직

```cpp
void ULyraAbilitySystemComponent::ProcessAbilityInput(float DeltaTime, bool bGamePaused)
{
    // AbilityInputBlocked 태그 있으면 모든 입력 차단
    if (HasMatchingGameplayTag(TAG_Gameplay_AbilityInputBlocked))
    {
        ClearAbilityInput();
        return;
    }

    TArray<FGameplayAbilitySpecHandle> AbilitiesToActivate;

    // 1. WhileInputActive 처리 (홀드 중 + 미활성화)
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputHeldSpecHandles)
    {
        if (const FGameplayAbilitySpec* Spec = FindAbilitySpecFromHandle(SpecHandle))
        {
            if (Spec->Ability && !Spec->IsActive())
            {
                const ULyraGameplayAbility* CDO = Cast<ULyraGameplayAbility>(Spec->Ability);
                if (CDO && CDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::WhileInputActive)
                    AbilitiesToActivate.AddUnique(Spec->Handle);
            }
        }
    }

    // 2. OnInputTriggered 처리 (이번 프레임 누름)
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputPressedSpecHandles)
    {
        if (FGameplayAbilitySpec* Spec = FindAbilitySpecFromHandle(SpecHandle))
        {
            Spec->InputPressed = true;
            
            if (Spec->IsActive())
                AbilitySpecInputPressed(*Spec);  // 활성화 중: 입력 이벤트 전달
            else
            {
                const ULyraGameplayAbility* CDO = Cast<ULyraGameplayAbility>(Spec->Ability);
                if (CDO && CDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::OnInputTriggered)
                    AbilitiesToActivate.AddUnique(Spec->Handle);
            }
        }
    }

    // 3. 수집된 능력 일괄 활성화
    for (const FGameplayAbilitySpecHandle& Handle : AbilitiesToActivate)
        TryActivateAbility(Handle);

    // 4. 릴리스 처리
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputReleasedSpecHandles)
    {
        if (FGameplayAbilitySpec* Spec = FindAbilitySpecFromHandle(SpecHandle))
        {
            Spec->InputPressed = false;
            if (Spec->IsActive())
                AbilitySpecInputReleased(*Spec);  // 활성화 중: 릴리스 이벤트 전달
        }
    }

    InputPressedSpecHandles.Reset();
    InputReleasedSpecHandles.Reset();
}
```
