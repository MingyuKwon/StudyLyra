# 입력 바인딩 — InputTag → Ability 활성화

> 소스: `LyraAbilitySystemComponent.cpp`, `LyraAbilitySet.cpp`

---

## 전체 흐름

```
키 입력 발생
    │
    ▼
ULyraHeroComponent::Input_AbilityInputTagPressed(InputTag)
    │ (EnhancedInput Action → HeroComponent 바인딩)
    │
    ▼
ULyraAbilitySystemComponent::AbilityInputTagPressed(InputTag)
    │ InputTag를 DynamicSpecSourceTags에 가진 AbilitySpec 탐색
    │ → InputPressedSpecHandles.AddUnique(Spec.Handle)
    │ → InputHeldSpecHandles.AddUnique(Spec.Handle)
    │
    ▼ (매 프레임 — LyraHeroComponent에서 호출)
ULyraAbilitySystemComponent::ProcessAbilityInput(DeltaTime, bGamePaused)
    │ TAG_Gameplay_AbilityInputBlocked 체크 → 있으면 ClearAbilityInput()
    │
    │ [InputHeldSpecHandles 처리]
    │   ActivationPolicy == WhileInputActive → AbilitiesToActivate에 추가
    │
    │ [InputPressedSpecHandles 처리]
    │   이미 활성화 중 → AbilitySpecInputPressed() (InputPressed 이벤트 전달)
    │   미활성화 + ActivationPolicy == OnInputTriggered → AbilitiesToActivate에 추가
    │
    │ → TryActivateAbility(Handle) 호출
    │
    │ [InputReleasedSpecHandles 처리]
    │   이미 활성화 중 → AbilitySpecInputReleased() (InputReleased 이벤트 전달)
    │
    ▼
입력 버퍼 초기화
```

---

## InputTag가 AbilitySpec에 붙는 방법

`ULyraAbilitySet::GiveToAbilitySystem()`에서 InputTag를 `DynamicSpecSourceTags`에 추가한다.

```cpp
// LyraAbilitySet.cpp
FGameplayAbilitySpec AbilitySpec(AbilityCDO, AbilityToGrant.AbilityLevel);
AbilitySpec.SourceObject = SourceObject;

// InputTag를 DynamicSpecSourceTags에 추가 (AbilitySpec의 동적 태그)
AbilitySpec.GetDynamicSpecSourceTags().AddTag(AbilityToGrant.InputTag);

const FGameplayAbilitySpecHandle AbilitySpecHandle = LyraASC->GiveAbility(AbilitySpec);
```

`FLyraAbilitySet_GameplayAbility`의 `InputTag` 필드가 이 연결을 정의한다.

---

## AbilityInputTagPressed 구현

```cpp
// LyraAbilitySystemComponent.cpp
void ULyraAbilitySystemComponent::AbilityInputTagPressed(const FGameplayTag& InputTag)
{
    if (InputTag.IsValid())
    {
        for (const FGameplayAbilitySpec& AbilitySpec : ActivatableAbilities.Items)
        {
            if (AbilitySpec.Ability && AbilitySpec.GetDynamicSpecSourceTags().HasTagExact(InputTag))
            {
                InputPressedSpecHandles.AddUnique(AbilitySpec.Handle);
                InputHeldSpecHandles.AddUnique(AbilitySpec.Handle);
            }
        }
    }
}
```

---

## AbilitySpecInputPressed — 입력 이벤트 전달

GA가 이미 활성화된 상태에서 입력이 들어오면, `AbilityTask`가 이 이벤트를 수신할 수 있다.

```cpp
void ULyraAbilitySystemComponent::AbilitySpecInputPressed(FGameplayAbilitySpec& Spec)
{
    Super::AbilitySpecInputPressed(Spec);
    
    if (Spec.IsActive())
    {
        // bReplicateInputDirectly 미사용 → 대신 Generic Replicated Event 사용
        // WaitInputPress AbilityTask가 이 이벤트를 수신
        InvokeReplicatedEvent(EAbilityGenericReplicatedEvent::InputPressed, 
            Spec.Handle, OriginalPredictionKey);
    }
}
```

> `bReplicateInputDirectly`는 사용하지 않는다. 대신 `InvokeReplicatedEvent`로 서버에 복제.

---

## ProcessAbilityInput에서 AbilityInputBlocked 처리

```cpp
void ULyraAbilitySystemComponent::ProcessAbilityInput(float DeltaTime, bool bGamePaused)
{
    // TAG_Gameplay_AbilityInputBlocked 태그가 있으면 입력 무시
    if (HasMatchingGameplayTag(TAG_Gameplay_AbilityInputBlocked))
    {
        ClearAbilityInput();
        return;
    }
    // ...
}
```

`TAG_Gameplay_AbilityInputBlocked`는 `"Gameplay.AbilityInputBlocked"` 태그.  
UI가 열려있거나 대화 중일 때 이 태그를 추가하면 모든 능력 입력이 차단된다.

---

## ActivationPolicy 별 처리

| ActivationPolicy | 처리 위치 |
|---|---|
| `OnInputTriggered` | `InputPressedSpecHandles` → 버튼 누를 때 1회 활성화 |
| `WhileInputActive` | `InputHeldSpecHandles` → 버튼 누른 동안 매 프레임 활성화 시도 |
| `OnSpawn` | 입력 무관. `InitAbilityActorInfo` → `TryActivateAbilitiesOnSpawn()`에서 처리 |

### WhileInputActive의 처리 이유

비활성화된 경우에만 재활성화를 시도한다:
```cpp
for (const FGameplayAbilitySpecHandle& SpecHandle : InputHeldSpecHandles)
{
    if (const FGameplayAbilitySpec* AbilitySpec = FindAbilitySpecFromHandle(SpecHandle))
    {
        // 이미 활성화 중이면 건너뜀 (중복 활성화 방지)
        if (AbilitySpec->Ability && !AbilitySpec->IsActive())
        {
            if (LyraAbilityCDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::WhileInputActive)
                AbilitiesToActivate.AddUnique(AbilitySpec->Handle);
        }
    }
}
```
