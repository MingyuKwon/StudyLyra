# 입력 바인딩

> **GASDoc**: 4.6.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-input"></a>
#### 4.6.2 ASC에 입력 바인딩

ASC는 입력 액션을 직접 바인딩하여, 부여된 GA에 해당 입력을 할당할 수 있다. 입력 액션이 할당된 GA는 GameplayTag 요건이 충족된 상태에서 해당 입력이 눌리면 자동으로 활성화된다. 또한 입력에 반응하는 내장 AbilityTask를 사용하려면 이 입력 할당이 필요하다.

GA 활성화용 입력 외에도, ASC는 범용 `Confirm`과 `Cancel` 입력을 별도로 받는다. 이는 [`Target Actor`](#concepts-targeting-actors) 확인이나 취소와 같은 AbilityTask 기능에 사용된다.

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

**참고:** 샘플 프로젝트의 enum에서 `Confirm`과 `Cancel`은 프로젝트 설정의 InputAction 이름(`ConfirmTarget`, `CancelTarget`)과 일치하지 않지만, `BindAbilityActivationToInputComponent()`에서 직접 매핑을 제공한다. 이 두 항목은 특수 케이스로 매핑을 직접 지정하기 때문에 이름이 달라도 된다(물론 같아도 된다). 나머지 입력 항목들은 프로젝트 설정의 InputAction 이름과 반드시 일치해야 한다.

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

**[⬆ Back to Top](#table-of-contents)**
---

## 내 분석
