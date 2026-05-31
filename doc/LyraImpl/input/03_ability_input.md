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

## 핸들 등록 — AbilityInputTagPressed

입력이 왔을 때 즉시 GA를 활성화하지 않고 Handle만 배열에 쌓는다. 실제 처리는 매 틱 `ProcessAbilityInput`에서 일괄 처리.

```cpp
// LyraAbilitySystemComponent.cpp:186
void ULyraAbilitySystemComponent::AbilityInputTagPressed(const FGameplayTag& InputTag)
{
    for (const FGameplayAbilitySpec& AbilitySpec : ActivatableAbilities.Items)
    {
        if (AbilitySpec.GetDynamicSpecSourceTags().HasTagExact(InputTag))
        {
            InputPressedSpecHandles.AddUnique(AbilitySpec.Handle);
            InputHeldSpecHandles.AddUnique(AbilitySpec.Handle);
        }
    }
}
```

---

## ProcessAbilityInput (매 틱)

`TAG_Gameplay_AbilityInputBlocked` 태그가 ASC에 붙어 있으면 3개 배열을 모두 초기화하고 즉시 리턴한다. 컷씬, UI 모달 등 입력을 막을 때 이 태그를 부여한다.

3개 배열을 순서대로 처리한 뒤 Held/Press 목록을 합산해 `TryActivateAbility`를 한 번에 실행한다.  
한 번에 실행하는 이유: Hold로 이미 활성화된 GA에 Press 이벤트가 중복 전달되는 것을 방지.

| 배열 | 처리 | 추가 시점 | 제거 시점 |
|------|------|-----------|-----------|
| `InputHeldSpecHandles` | WhileInputActive 정책 GA 활성화 (이미 실행 중이면 스킵) | 키 누름 | 키 뗌 |
| `InputPressedSpecHandles` | OnInputTriggered GA 활성화 / 이미 활성 → InputPressed 이벤트 | 키 누름 | 매 틱 끝 |
| `InputReleasedSpecHandles` | 이미 활성 → InputReleased 이벤트 | 키 뗌 | 매 틱 끝 |

---

## 이미 실행 중인 GA에 입력이 오면

`InputPressedSpecHandles` 처리 시 `AbilitySpec->IsActive() == true`이면 `TryActivateAbility` 대신 `AbilitySpecInputPressed()`를 호출한다.

이 경로는 **GA 내부에서 WaitInputPress/Release Task를 대기시켜 두고 다음 입력 이벤트를 받는** 패턴에 쓰인다.

### 연결 체인

```
AbilitySpecInputPressed(*AbilitySpec)
    → Super::AbilitySpecInputPressed()        ← GA InputPressed() 가상함수
    → InvokeReplicatedEvent(InputPressed, handle, predKey)
        → GenericEvents[InputPressed].Delegate.Broadcast()
            → WaitInputPress::OnPressCallback()
                → OnPress.Broadcast(ElapsedTime)   ← GA 콜백 실행
                → (IsPredictingClient) ServerSetReplicatedEvent()
                → EndTask()
```

`bReplicateInputDirectly` 대신 `InvokeReplicatedEvent`를 쓰는 이유: WaitInputPress/Release Task는 ASC의 `GenericEvents` 슬롯을 통해야 네트워크 환경에서 올바르게 동작하기 때문.

### WaitInputPress / WaitInputRelease 사용법

GA 활성화 시점에 Task를 생성하고 `ReadyForActivation()`을 호출하면, Task가 `GenericEvents[InputPressed]` 슬롯에 자신의 콜백을 등록한다. 이후 버튼 입력이 오면 위 체인을 통해 콜백이 실행된다.

```cpp
// 충전 스킬 예시
void UMyChargeAbility::ActivateAbility(...)
{
    StartCharging();

    UAbilityTask_WaitInputRelease* Task = UAbilityTask_WaitInputRelease::WaitInputRelease(this);
    Task->OnRelease.AddDynamic(this, &ThisClass::OnReleased);
    Task->ReadyForActivation();
}

void UMyChargeAbility::OnReleased(float HeldTime)
{
    FireCharged(HeldTime);
    EndAbility(...);
}
```

Task 생성 전에 이미 이벤트가 발동된 경우, `Activate()` 내에서 `CallReplicatedEventDelegateIfSet()`으로 사후 처리한다.  
WaitInputRelease는 슬롯만 `EAbilityGenericReplicatedEvent::InputReleased`로 바뀐다.
