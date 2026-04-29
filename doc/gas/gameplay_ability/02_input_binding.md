# 입력 바인딩

> **GASDoc**: 4.6.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

> **GASDoc 원문 생략**: 원문의 입력 바인딩 방식은 `uint8` enum + `BindAbilityActivationToInputComponent()`를 사용하는 **UE4 레거시 입력 시스템** 기반이다. UE5/Lyra는 Enhanced Input System으로 완전히 대체했으므로 원문 내용은 현재 프로젝트에 적용되지 않는다.

---

## 내 분석

### GASDoc 방식은 Lyra에서 쓰이지 않는다

GASDoc의 `enum`+`BindAbilityActivationToInputComponent()` 패턴은 **UE4 레거시 입력 시스템** 기반이다.
Lyra는 **Enhanced Input System**으로 완전히 대체했으며, 입력 식별자도 정수 enum 대신 `GameplayTag`를 쓴다.

| | GASDoc 방식 | Lyra 방식 |
|---|---|---|
| 입력 시스템 | Legacy InputAction (UE4) | Enhanced Input System (UE5) |
| 입력 식별자 | `uint8` enum (InputID) | `FGameplayTag` |
| ASC 바인딩 함수 | `BindAbilityActivationToInputComponent()` | 커스텀 `BindAbilityActions()` |
| Spec 매칭 | `Spec.InputID == InputID` | `Spec.DynamicSpecSourceTags.HasTagExact(InputTag)` |
| 입력 처리 방식 | 즉시 `TryActivateAbility()` | 프레임 큐 → `PostProcessInput()` |
| 활성화 정책 | press = 무조건 활성화 | `OnInputTriggered` / `WhileInputActive` 분리 |

---

### 바인딩 설정 — InitializePlayerInput

`ULyraHeroComponent::InitializePlayerInput()`에서 Enhanced Input에 콜백을 등록한다.
`ULyraInputConfig`(DataAsset)가 `InputAction → GameplayTag` 매핑 테이블 역할을 한다.

```cpp
// LyraHeroComponent.cpp:283
LyraIC->BindAbilityActions(InputConfig, this,
    &ThisClass::Input_AbilityInputTagPressed,   // ETriggerEvent::Triggered
    &ThisClass::Input_AbilityInputTagReleased,  // ETriggerEvent::Completed
    BindHandles);
```

---

### 프레임 내 호출 타이밍

```
[프레임 시작]

PreProcessInput()

Enhanced Input 처리 — 이 프레임의 모든 입력 이벤트
  키 누름 감지 → ETriggerEvent::Triggered
    → Input_AbilityInputTagPressed(Tag)
        → LyraASC->AbilityInputTagPressed(Tag)
            → InputPressedSpecHandles / InputHeldSpecHandles 큐에 핸들 추가
              (아직 어빌리티 활성화 없음)

PostProcessInput()   ← LyraPlayerController.cpp:376
  → LyraASC->ProcessAbilityInput()
      → 큐 전체를 한 번에 소화 → TryActivateAbility() / AbilitySpecInputPressed()

[프레임 끝]
```

`AbilityInputTagPressed`는 Enhanced Input 단계에서 **큐에 쌓기만** 한다.
`PostProcessInput`에서 이 프레임의 모든 입력이 수집된 뒤 일괄 처리하는 이유는, 같은 프레임에 Hold와 Press가 동시에 들어왔을 때 Hold가 어빌리티를 먼저 활성화하고 Press가 또 InputPressed 이벤트를 쏘는 중복을 방지하기 위해서다.

---

### 입력 처리 파이프라인 — ProcessAbilityInput

```cpp
// LyraAbilitySystemComponent.cpp:216
void ULyraAbilitySystemComponent::ProcessAbilityInput(float DeltaTime, bool bGamePaused)
{
    // AbilityInputBlocked 태그가 있으면 전체 입력 무시
    if (HasMatchingGameplayTag(TAG_Gameplay_AbilityInputBlocked))
    {
        ClearAbilityInput();
        return;
    }

    // 1. WhileInputActive 정책 — 홀드 중이고 비활성 상태면 활성화 큐에 추가
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputHeldSpecHandles)
    {
        if (LyraAbilityCDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::WhileInputActive)
            AbilitiesToActivate.AddUnique(SpecHandle);
    }

    // 2. OnInputTriggered 정책 — 이번 프레임에 Press된 것 처리
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputPressedSpecHandles)
    {
        AbilitySpec->InputPressed = true;

        if (AbilitySpec->IsActive())
            AbilitySpecInputPressed(*AbilitySpec);      // 이미 실행 중 → 입력 이벤트 전달
        else if (ActivationPolicy == OnInputTriggered)
            AbilitiesToActivate.AddUnique(SpecHandle); // 비활성 → 활성화 큐에 추가
    }

    // 3. 수집한 어빌리티 한꺼번에 활성화
    for (const FGameplayAbilitySpecHandle& Handle : AbilitiesToActivate)
        TryActivateAbility(Handle);

    // 4. Release 처리 — 활성 중인 스펙에 InputReleased 이벤트 전달
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputReleasedSpecHandles)
        AbilitySpecInputReleased(*AbilitySpec);

    // 5. 큐 비우기 (InputHeldSpecHandles는 유지 — 다음 프레임도 홀드 중)
    InputPressedSpecHandles.Reset();
    InputReleasedSpecHandles.Reset();
}
```

---

### 활성화 정책 — ELyraAbilityActivationPolicy

```cpp
enum class ELyraAbilityActivationPolicy : uint8
{
    OnInputTriggered,  // 버튼 누를 때 한 번 활성화
    WhileInputActive,  // 버튼 누르는 동안 계속 활성화 유지
    OnSpawn,           // 부여 즉시 활성화 (입력 무관)
};
```

---

### 이미 활성화된 GA에 추가 입력 전달하기

GA가 실행 중일 때 입력을 추가로 받아야 하는 경우는 두 가지 메커니즘으로 나뉜다.

#### 같은 입력 — WaitInputPress / WaitInputRelease

`ProcessAbilityInput`에서 이미 활성화된 스펙에 같은 입력이 들어오면 `AbilitySpecInputPressed()`를 호출한다.
내부적으로 `GenericReplicatedEvent` 시스템을 통해 `WaitInputPress` AbilityTask로 신호가 전달된다.
→ 상세 동작은 [10 GenericReplicatedEvent](10_generic_replicated_event.md) 참조.

```
ProcessAbilityInput()
  → AbilitySpec->IsActive() == true
      → AbilitySpecInputPressed()
          → InvokeReplicatedEvent(InputPressed, Handle)
              → WaitInputPress::OnPressCallback() → OnPress.Broadcast()
```

**제약**: `GetAbilitySpecHandle()`로 바인딩하므로 **이 GA를 활성화한 바로 그 입력**에만 반응한다.

#### 다른 입력 — WaitGameplayEvent

A로 GA를 활성화한 상태에서 B 입력을 받으려면 `GameplayEvent` 경유가 표준 패턴이다.

```
[B 키 누름]
  → Input_AbilityInputTagPressed(Tag_B)
      → B에 바인딩된 GA_B 활성화 (또는 입력 핸들러에서 직접)
          → ASC->HandleGameplayEvent(Tag_Input_B, EventData)

[GA_A 내부]
  → UAbilityTask_WaitGameplayEvent 대기 중
      → EventReceived.Broadcast(EventData) → GA_A가 반응
```

```cpp
// GA_A::ActivateAbility() 안에서
UAbilityTask_WaitGameplayEvent* Task = UAbilityTask_WaitGameplayEvent::WaitGameplayEvent(
    this,
    FGameplayTag::RequestGameplayTag("Input.B")
);
Task->EventReceived.AddDynamic(this, &ThisClass::OnBInputReceived);
Task->ReadyForActivation();
```

#### 패턴 정리

| 상황 | 메커니즘 |
|---|---|
| GA 활성화한 **같은** 입력을 다시 누름/뗌 | `WaitInputPress` / `WaitInputRelease` |
| GA 활성화 중 **다른** 입력 B를 받음 | `WaitGameplayEvent` + B 핸들러에서 `HandleGameplayEvent()` |
| 확인/취소 전용 입력 | `WaitConfirm` / `WaitCancel` |

---

### 입력 태그가 Spec에 들어가는 경위

`DynamicSpecSourceTags`에 InputTag가 있어야 `AbilityInputTagPressed`의 매칭이 된다.
어빌리티 부여 시 `FGameplayAbilitySpec`을 생성하면서 `DynamicSpecSourceTags.AddTag(InputTag)`를 호출해야 한다.
`ULyraAbilitySet::GiveToAbilitySystem()`에서 이 작업을 처리한다.
