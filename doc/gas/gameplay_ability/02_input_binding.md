# 입력 바인딩

> **GASDoc**: 4.6.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-input"></a>
#### 4.6.2 ASC에 입력 바인딩

ASC는 입력 액션을 직접 바인딩하여, 부여된 GA에 해당 입력을 할당할 수 있다. 입력 액션이 할당된 GA는 GameplayTag 요건이 충족된 상태에서 해당 입력이 눌리면 자동으로 활성화된다. 또한 입력에 반응하는 내장 AbilityTask를 사용하려면 이 입력 할당이 필요하다.

GA 활성화용 입력 외에도, ASC는 범용 `Confirm`과 `Cancel` 입력을 별도로 받는다. 이는 `Target Actor` 확인이나 취소와 같은 AbilityTask 기능에 사용된다.

ASC에 입력을 바인딩하려면, 먼저 InputAction 이름을 byte 값으로 변환하는 enum을 정의해야 한다. enum 이름은 프로젝트 설정의 InputAction 이름과 정확히 일치해야 한다. `DisplayName`은 일치하지 않아도 된다.

샘플 프로젝트 예시:
```c++
UENUM(BlueprintType)
enum class EGDAbilityInputID : uint8
{
	// 0 None
	None			UMETA(DisplayName = "None"),
	// 1 Confirm
	Confirm			UMETA(DisplayName = "Confirm"),
	// 2 Cancel
	Cancel			UMETA(DisplayName = "Cancel"),
	// 3 LMB
	Ability1		UMETA(DisplayName = "Ability1"),
	// 4 RMB
	Ability2		UMETA(DisplayName = "Ability2"),
	// 5 Q
	Ability3		UMETA(DisplayName = "Ability3"),
	// 6 E
	Ability4		UMETA(DisplayName = "Ability4"),
	// 7 R
	Ability5		UMETA(DisplayName = "Ability5"),
	// 8 Sprint
	Sprint			UMETA(DisplayName = "Sprint"),
	// 9 Jump
	Jump			UMETA(DisplayName = "Jump")
};
```

ASC가 Character에 있는 경우, `SetupPlayerInputComponent()`에서 ASC에 바인딩하는 함수를 호출한다:
```c++
// Bind to AbilitySystemComponent
FTopLevelAssetPath AbilityEnumAssetPath = FTopLevelAssetPath(FName("/Script/GASDocumentation"), FName("EGDAbilityInputID"));
AbilitySystemComponent->BindAbilityActivationToInputComponent(PlayerInputComponent, FGameplayAbilityInputBinds(FString("ConfirmTarget"),
	FString("CancelTarget"), AbilityEnumAssetPath, static_cast<int32>(EGDAbilityInputID::Confirm), static_cast<int32>(EGDAbilityInputID::Cancel)));
```

ASC가 PlayerState에 있는 경우, `SetupPlayerInputComponent()` 안에서 PlayerState가 아직 클라이언트에 복제되지 않았을 가능성이 있어 잠재적인 경쟁 조건(race condition)이 발생할 수 있다. 따라서 `SetupPlayerInputComponent()`와 `OnRep_PlayerState()` 양쪽에서 바인딩을 시도하는 것을 권장한다. `OnRep_PlayerState()` 단독으로는 충분하지 않은데, PlayerController가 클라이언트에게 `ClientRestart()`를 호출하기 전에 PlayerState가 먼저 복제될 경우 Actor의 InputComponent가 null일 수 있기 때문이다. 샘플 프로젝트는 bool 플래그를 사용하여 실제 바인딩이 한 번만 수행되도록 관리하면서 두 곳 모두에서 시도한다.

> **참고**  
> 샘플 프로젝트의 enum에서 `Confirm`과 `Cancel`은 프로젝트 설정의 InputAction 이름(`ConfirmTarget`, `CancelTarget`)과 일치하지 않지만, `BindAbilityActivationToInputComponent()`에서 직접 매핑을 제공한다. 이 두 항목은 특수 케이스로 매핑을 직접 지정하기 때문에 이름이 달라도 된다(물론 같아도 된다). 나머지 입력 항목들은 프로젝트 설정의 InputAction 이름과 반드시 일치해야 한다.

항상 동일한 슬롯에서만 활성화되는 GA(MOBA의 스킬 슬롯처럼)의 경우, `UGameplayAbility` 서브클래스에 입력 ID를 정의하는 변수를 추가하고 어빌리티 부여 시 `ClassDefaultObject`에서 이 값을 읽어오는 방식을 선호한다.

<a name="concepts-ga-input-noactivate"></a>
#### 4.6.2.1 활성화 없이 입력만 바인딩하기

입력이 눌렸을 때 GA가 자동으로 활성화되지 않으면서도 AbilityTask에서 입력을 사용할 수 있도록 바인딩만 유지하고 싶다면, `UGameplayAbility` 서브클래스에 기본값이 `true`인 `bActivateOnInput` bool 변수를 추가하고 `UAbilitySystemComponent::AbilityLocalInputPressed()`를 오버라이드한다.

```c++
void UGSAbilitySystemComponent::AbilityLocalInputPressed(int32 InputID)
{
	// Consume the input if this InputID is overloaded with GenericConfirm/Cancel and the GenericConfim/Cancel callback is bound
	if (IsGenericConfirmInputBound(InputID))
	{
		LocalInputConfirm();
		return;
	}

	if (IsGenericCancelInputBound(InputID))
	{
		LocalInputCancel();
		return;
	}

	// ---------------------------------------------------------

	ABILITYLIST_SCOPE_LOCK();
	for (FGameplayAbilitySpec& Spec : ActivatableAbilities.Items)
	{
		if (Spec.InputID == InputID)
		{
			if (Spec.Ability)
			{
				Spec.InputPressed = true;
				if (Spec.IsActive())
				{
					if (Spec.Ability->bReplicateInputDirectly && IsOwnerActorAuthoritative() == false)
					{
						ServerSetInputPressed(Spec.Handle);
					}

					AbilitySpecInputPressed(Spec);

					// Invoke the InputPressed event. This is not replicated here. If someone is listening, they may replicate the InputPressed event to the server.
					InvokeReplicatedEvent(EAbilityGenericReplicatedEvent::InputPressed, Spec.Handle, Spec.ActivationInfo.GetActivationPredictionKey());
				}
				else
				{
					UGSGameplayAbility* GA = Cast<UGSGameplayAbility>(Spec.Ability);
					if (GA && GA->bActivateOnInput)
					{
						// Ability is not active, so try to activate it
						TryActivateAbility(Spec.Handle);
					}
				}
			}
		}
	}
}
```

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
| 입력 처리 방식 | 즉시 `TryActivateAbility()` | 프레임 큐 → `ProcessAbilityInput()` |
| 활성화 정책 | press = 무조건 활성화 | `OnInputTriggered` / `WhileInputActive` 분리 |

---

### Lyra 입력 바인딩 흐름

```
ULyraPawnData::InputConfig (ULyraInputConfig)
  — InputAction → GameplayTag 매핑 테이블

ULyraHeroComponent::InitializePlayerInput()
  → LyraIC->BindAbilityActions(InputConfig, ..., &Input_AbilityInputTagPressed, &Input_AbilityInputTagReleased)
       — EnhancedInput: InputAction Triggered → Input_AbilityInputTagPressed(Tag)
       — EnhancedInput: InputAction Completed → Input_AbilityInputTagReleased(Tag)

Input_AbilityInputTagPressed(FGameplayTag InputTag)
  → LyraASC->AbilityInputTagPressed(InputTag)
       — ActivatableAbilities 순회
       — DynamicSpecSourceTags에 InputTag가 있는 Spec의 핸들을 큐에 추가

매 틱 LyraASC->ProcessAbilityInput()
  — InputHeldSpecHandles: WhileInputActive 정책 어빌리티 활성화
  — InputPressedSpecHandles: OnInputTriggered 정책 어빌리티 활성화 or InputPressed 이벤트 전달
  — InputReleasedSpecHandles: InputReleased 이벤트 전달
```

#### AbilityInputTagPressed / Released — 큐에 쌓을 뿐

```cpp
// LyraAbilitySystemComponent.cpp:186
void ULyraAbilitySystemComponent::AbilityInputTagPressed(const FGameplayTag& InputTag)
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
```

입력이 들어오면 즉시 활성화하지 않고 핸들을 큐에 넣는다.
실제 `TryActivateAbility()`는 같은 프레임 말에 `ProcessAbilityInput()`이 일괄 처리한다.

#### ProcessAbilityInput — 프레임 말 일괄 처리

```cpp
// LyraAbilitySystemComponent.cpp:216
void ULyraAbilitySystemComponent::ProcessAbilityInput(float DeltaTime, bool bGamePaused)
{
    // TAG_Gameplay_AbilityInputBlocked 태그가 있으면 모든 입력 무시
    if (HasMatchingGameplayTag(TAG_Gameplay_AbilityInputBlocked)) { ClearAbilityInput(); return; }

    // 1. WhileInputActive 정책: 입력 홀드 중 + 비활성 상태면 활성화
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputHeldSpecHandles)
    {
        if (LyraAbilityCDO->GetActivationPolicy() == ELyraAbilityActivationPolicy::WhileInputActive)
            AbilitiesToActivate.AddUnique(SpecHandle);
    }

    // 2. OnInputTriggered 정책: 이번 프레임에 Press된 것 처리
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputPressedSpecHandles)
    {
        AbilitySpec->InputPressed = true;

        if (AbilitySpec->IsActive())
            AbilitySpecInputPressed(*AbilitySpec);        // 이미 실행 중 → 입력 이벤트만 전달
        else if (ActivationPolicy == OnInputTriggered)
            AbilitiesToActivate.AddUnique(SpecHandle);   // 비활성 → 활성화 큐에 추가
    }

    // 3. 수집된 어빌리티 한꺼번에 활성화
    for (const FGameplayAbilitySpecHandle& Handle : AbilitiesToActivate)
        TryActivateAbility(Handle);

    // 4. Release 처리
    for (const FGameplayAbilitySpecHandle& SpecHandle : InputReleasedSpecHandles) { ... }

    // 5. 큐 비우기
    InputPressedSpecHandles.Reset();
    InputReleasedSpecHandles.Reset();
}
```

**프레임 말 일괄 처리를 하는 이유**: 같은 프레임에 Hold와 Press가 둘 다 들어왔을 때, Hold가 어빌리티를 먼저 활성화하고 Press가 또 InputPressed 이벤트를 보내는 중복을 방지하기 위해서다. 수집을 먼저 하고 한 번에 처리한다.

#### 활성화 정책 — ELyraAbilityActivationPolicy

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationPolicy : uint8
{
    OnInputTriggered,  // 버튼 누를 때 한 번 활성화
    WhileInputActive,  // 버튼 누르는 동안 계속 활성화 유지
    OnSpawn,           // 부여 즉시 활성화 (입력 무관)
};
```

GASDoc 방식은 press 이벤트가 오면 무조건 `TryActivateAbility()`를 호출했다.
Lyra는 어빌리티마다 정책을 달리 설정할 수 있어, 예컨대 달리기(Hold)와 점프(Press)를 동일한 처리 파이프라인에서 구분해서 다룬다.

---

### 입력 태그가 Spec에 들어가는 경위

`DynamicSpecSourceTags`에 InputTag가 들어가야 매칭이 된다.
어빌리티를 부여할 때 `FGameplayAbilitySpec`을 만들면서 `DynamicSpecSourceTags.AddTag(InputTag)`를 호출해주어야 한다.
`ULyraAbilitySet::GiveToAbilitySystem()`에서 이 작업을 처리한다.
