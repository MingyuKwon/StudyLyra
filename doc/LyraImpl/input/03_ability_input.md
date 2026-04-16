# Ability 입력 경로

> 출처: `AbilitySystem/LyraAbilitySystemComponent.cpp:186-318`,  
>        `Character/LyraHeroComponent.cpp:343-372`,  
>        `Player/LyraPlayerController.cpp:376-384`

---

## 전체 흐름

```
[키 누름] Enhanced Input 이벤트 발생
    └─ HeroComponent::Input_AbilityInputTagPressed(InputTag)
            └─ LyraASC::AbilityInputTagPressed(InputTag)
                    └─ ActivatableAbilities 순회
                            → InputPressedSpecHandles에 추가
                            → InputHeldSpecHandles에 추가

[매 틱] ALyraPlayerController::PostProcessInput()
    └─ LyraASC::ProcessAbilityInput(DeltaTime, bGamePaused)
            ├─ InputHeldSpecHandles    → WhileInputActive 정책 GA 활성화
            ├─ InputPressedSpecHandles → OnInputTriggered GA 활성화 / InputPressed 이벤트
            └─ InputReleasedSpecHandles → InputReleased 이벤트
            (Pressed/Released 배열 초기화, Held는 그대로 유지)

[키 뗌] Enhanced Input 이벤트 발생
    └─ HeroComponent::Input_AbilityInputTagReleased(InputTag)
            └─ LyraASC::AbilityInputTagReleased(InputTag)
                    └─ InputReleasedSpecHandles에 추가
                       InputHeldSpecHandles에서 제거
```

---

## 1단계 — 키 누름 → ASC에 등록

```cpp
// HeroComponent.cpp:343
void ULyraHeroComponent::Input_AbilityInputTagPressed(FGameplayTag InputTag)
{
    if (ULyraAbilitySystemComponent* LyraASC = ...)
        LyraASC->AbilityInputTagPressed(InputTag);
}

// LyraAbilitySystemComponent.cpp:186
void ULyraAbilitySystemComponent::AbilityInputTagPressed(const FGameplayTag& InputTag)
{
    for (const FGameplayAbilitySpec& AbilitySpec : ActivatableAbilities.Items)
    {
        // DynamicSpecSourceTags에 InputTag가 있는 Spec을 찾음
        if (AbilitySpec.GetDynamicSpecSourceTags().HasTagExact(InputTag))
        {
            InputPressedSpecHandles.AddUnique(AbilitySpec.Handle);
            InputHeldSpecHandles.AddUnique(AbilitySpec.Handle);   // 홀드 목록에도 추가
        }
    }
}
```

입력이 왔을 때 즉시 GA를 활성화하지 않고, **Handle만 배열에 쌓아둔다**. 실제 처리는 매 틱 `ProcessAbilityInput`에서 일괄 처리.

---

## 2단계 — ProcessAbilityInput (매 틱)

```cpp
// LyraAbilitySystemComponent.cpp:216
void ULyraAbilitySystemComponent::ProcessAbilityInput(float DeltaTime, bool bGamePaused)
{
    // AbilityInputBlocked 태그가 있으면 모두 무시
    if (HasMatchingGameplayTag(TAG_Gameplay_AbilityInputBlocked))
    {
        ClearAbilityInput();
        return;
    }
```

### InputHeldSpecHandles — WhileInputActive 처리

```cpp
for (const FGameplayAbilitySpecHandle& SpecHandle : InputHeldSpecHandles)
{
    const ULyraGameplayAbility* LyraAbilityCDO = Cast<ULyraGameplayAbility>(AbilitySpec->Ability);
    if (LyraAbilityCDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::WhileInputActive)
    {
        if (!AbilitySpec->IsActive())   // 아직 실행 중이 아닐 때만
            AbilitiesToActivate.Add(AbilitySpec->Handle);
    }
}
```

키를 누르고 있는 동안 매 틱 활성화를 시도한다. 이미 실행 중이면 재활성화하지 않는다.

### InputPressedSpecHandles — OnInputTriggered 처리

```cpp
for (const FGameplayAbilitySpecHandle& SpecHandle : InputPressedSpecHandles)
{
    AbilitySpec->InputPressed = true;

    if (AbilitySpec->IsActive())
    {
        // 이미 실행 중 → InputPressed 이벤트만 전달 (WaitInputPress Task 등에서 수신)
        AbilitySpecInputPressed(*AbilitySpec);
    }
    else
    {
        if (LyraAbilityCDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::OnInputTriggered)
            AbilitiesToActivate.Add(AbilitySpec->Handle);
    }
}
```

이미 활성화된 GA에게는 `InputPressed` 이벤트를 보낸다 → `WaitInputPress` AbilityTask가 이를 수신.

### 일괄 TryActivateAbility

```cpp
for (const FGameplayAbilitySpecHandle& Handle : AbilitiesToActivate)
{
    TryActivateAbility(Handle);
}
```

Hold와 Press 목록을 합산해 **한 번에 활성화**. 이렇게 하는 이유: Hold로 이미 활성화된 GA에 Press 이벤트가 중복 전달되는 것을 방지.

### InputReleasedSpecHandles — 뗌 처리

```cpp
for (const FGameplayAbilitySpecHandle& SpecHandle : InputReleasedSpecHandles)
{
    AbilitySpec->InputPressed = false;
    if (AbilitySpec->IsActive())
        AbilitySpecInputReleased(*AbilitySpec);  // WaitInputRelease Task 등에서 수신
}

// Pressed/Released만 초기화. Held는 키를 뗄 때까지 유지.
InputPressedSpecHandles.Reset();
InputReleasedSpecHandles.Reset();
```

---

## 3개 배열의 생명주기

| 배열 | 추가 시점 | 제거 시점 |
|------|-----------|-----------|
| `InputPressedSpecHandles` | 키 누름 | 매 틱 ProcessAbilityInput 끝 |
| `InputReleasedSpecHandles` | 키 뗌 | 매 틱 ProcessAbilityInput 끝 |
| `InputHeldSpecHandles` | 키 누름 | 키 뗌 (`AbilityInputTagReleased`) |

---

## AbilitySpecInputPressed / Released — 복제 처리

```cpp
// LyraAbilitySystemComponent.cpp:155
void ULyraAbilitySystemComponent::AbilitySpecInputPressed(FGameplayAbilitySpec& Spec)
{
    Super::AbilitySpecInputPressed(Spec);
    // bReplicateInputDirectly 미사용. 대신 ReplicatedEvent 사용.
    if (Spec.IsActive())
        InvokeReplicatedEvent(EAbilityGenericReplicatedEvent::InputPressed,
            Spec.Handle, OriginalPredictionKey);
}
```

`bReplicateInputDirectly`를 사용하지 않고 `InvokeReplicatedEvent`로 처리한다.  
이 방식이어야 `WaitInputPress` / `WaitInputRelease` AbilityTask가 네트워크 환경에서 올바르게 동작한다.

---

## TAG_Gameplay_AbilityInputBlocked

`ProcessAbilityInput` 진입 시 가장 먼저 확인하는 태그.  
이 태그가 ASC에 붙어 있으면 **모든 입력을 무시**하고 3개 배열을 모두 초기화한다.  
컷씬 재생, UI 모달 등 입력을 막아야 하는 상황에서 이 태그를 부여하는 방식으로 제어한다.
