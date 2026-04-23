# GA 부여 & 활성화

> **GASDoc**: 4.6.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-granting"></a>
#### 4.6.3 GA 부여 (Granting)

GA를 ASC에 부여하면 ASC의 `ActivatableAbilities` 목록에 추가되어, 조건이 충족될 때 해당 GA를 활성화할 수 있게 된다.

GA 부여는 **서버에서만** 수행하며, [`GameplayAbilitySpec`](#concepts-ga-spec)이 owning client로 자동 복제된다. 다른 클라이언트(simulated proxy)는 GameplayAbilitySpec을 받지 않는다.

샘플 프로젝트는 Character 클래스에 `TArray<TSubclassOf<UGDGameplayAbility>>`를 저장해두고 게임 시작 시 읽어서 부여한다:
```c++
void AGDCharacterBase::AddCharacterAbilities()
{
	// Grant abilities, but only on the server	
	if (Role != ROLE_Authority || !AbilitySystemComponent.IsValid() || AbilitySystemComponent->bCharacterAbilitiesGiven)
	{
		return;
	}

	for (TSubclassOf<UGDGameplayAbility>& StartupAbility : CharacterAbilities)
	{
		AbilitySystemComponent->GiveAbility(
			FGameplayAbilitySpec(StartupAbility, GetAbilityLevel(StartupAbility.GetDefaultObject()->AbilityID), static_cast<int32>(StartupAbility.GetDefaultObject()->AbilityInputID), this));
	}

	AbilitySystemComponent->bCharacterAbilitiesGiven = true;
}
```

GA를 부여할 때, `UGameplayAbility` 클래스, 어빌리티 레벨, 바인딩할 입력, 그리고 이 GA를 해당 ASC에 부여한 주체인 `SourceObject`를 담은 `GameplayAbilitySpec`을 생성하여 전달한다.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-activating"></a>
#### 4.6.4 GA 활성화 (Activating)

입력 액션이 할당된 GA는 해당 입력이 눌리고 GameplayTag 요건이 충족되면 자동으로 활성화된다. 하지만 이것이 항상 원하는 방식은 아닐 수 있다. ASC는 GA를 활성화하는 네 가지 추가 방법을 제공한다: GameplayTag, GameplayAbility 클래스, GameplayAbilitySpec 핸들, 그리고 이벤트. 이벤트로 GA를 활성화하면 [이벤트와 함께 페이로드 데이터를 전달](#concepts-ga-data)할 수 있다.

```c++
UFUNCTION(BlueprintCallable, Category = "Abilities")
bool TryActivateAbilitiesByTag(const FGameplayTagContainer& GameplayTagContainer, bool bAllowRemoteActivation = true);

UFUNCTION(BlueprintCallable, Category = "Abilities")
bool TryActivateAbilityByClass(TSubclassOf<UGameplayAbility> InAbilityToActivate, bool bAllowRemoteActivation = true);

bool TryActivateAbility(FGameplayAbilitySpecHandle AbilityToActivate, bool bAllowRemoteActivation = true);

bool TriggerAbilityFromGameplayEvent(FGameplayAbilitySpecHandle AbilityToTrigger, FGameplayAbilityActorInfo* ActorInfo, FGameplayTag Tag, const FGameplayEventData* Payload, UAbilitySystemComponent& Component);

FGameplayAbilitySpecHandle GiveAbilityAndActivateOnce(const FGameplayAbilitySpec& AbilitySpec, const FGameplayEventData* GameplayEventData);
```

이벤트로 GA를 활성화하려면, GA의 `Triggers`에 GameplayTag를 할당하고 GameplayEvent 옵션을 선택해야 한다. 이벤트를 전송하려면 `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor(AActor* Actor, FGameplayTag EventTag, FGameplayEventData Payload)` 함수를 사용한다. 이벤트로 GA를 활성화하면 페이로드에 데이터를 담아 전달할 수 있다.

GA `Triggers`는 GameplayTag가 추가되거나 제거될 때 GA를 활성화하는 것도 지원한다.

**참고:** Blueprint에서 이벤트로 GA를 활성화할 때는 반드시 `ActivateAbilityFromEvent` 노드를 사용해야 한다.

**참고:** 패시브 어빌리티처럼 항상 실행 상태를 유지하는 GA가 아니라면, GA가 종료되어야 할 시점에 반드시 `EndAbility()`를 호출하는 것을 잊지 말 것.

**로컬 예측(locally predicted) GA의 활성화 순서:**
1. **Owning client**가 `TryActivateAbility()`를 호출
1. `InternalTryActivateAbility()`를 호출
1. `CanActivateAbility()`를 호출하여 GameplayTag 요건 충족 여부, ASC의 코스트 지불 가능 여부, GA의 쿨다운 여부, 다른 인스턴스가 현재 활성 중인지 등을 반환
1. 생성한 `Prediction Key`를 전달하며 `CallServerTryActivateAbility()`를 호출
1. `CallActivateAbility()`를 호출
1. `PreActivate()`를 호출 — Epic은 이를 "boilerplate init stuff(초기화 보일러플레이트)"라고 표현
1. 최종적으로 `ActivateAbility()`를 호출하여 어빌리티 활성화

**서버**는 `CallServerTryActivateAbility()`를 수신하면:
1. `ServerTryActivateAbility()`를 호출
1. `InternalServerTryActivateAbility()`를 호출
1. `InternalTryActivateAbility()`를 호출
1. `CanActivateAbility()`를 호출하여 GameplayTag 요건 충족 여부, ASC의 코스트 지불 가능 여부, GA의 쿨다운 여부, 다른 인스턴스가 현재 활성 중인지 등을 반환
1. 성공 시 `ClientActivateAbilitySucceed()`를 호출하여 `ActivationInfo`를 업데이트하고 서버가 활성화를 승인했음을 알리며 `OnConfirmDelegate` 델리게이트를 브로드캐스트 (이는 입력 확인과는 다름)
1. `CallActivateAbility()`를 호출
1. `PreActivate()`를 호출 — Epic은 이를 "boilerplate init stuff(초기화 보일러플레이트)"라고 표현
1. 최종적으로 `ActivateAbility()`를 호출하여 어빌리티 활성화

서버가 활성화에 실패하면 `ClientActivateAbilityFailed()`를 호출하여 클라이언트의 GA를 즉시 종료하고 예측으로 인한 변경 사항을 롤백한다.

<a name="concepts-ga-activating-passive"></a>
#### 4.6.4.1 패시브 GA

자동으로 활성화되어 지속 실행되는 패시브 GA를 구현하려면, `UGameplayAbility::OnAvatarSet()`을 오버라이드한다. 이 함수는 GA가 부여되고 `AvatarActor`가 설정될 때 자동으로 호출되며, 여기서 `TryActivateAbility()`를 호출하면 된다.

커스텀 `UGameplayAbility` 클래스에 GA 부여 시 자동 활성화 여부를 지정하는 `bool` 변수를 추가하는 것을 권장한다. 샘플 프로젝트에서는 패시브 방어구 중첩 어빌리티에 이 방식을 사용한다.

패시브 GA는 일반적으로 [`Net Execution Policy`](#concepts-ga-net)를 `Server Only`로 설정한다.

```c++
void UGDGameplayAbility::OnAvatarSet(const FGameplayAbilityActorInfo * ActorInfo, const FGameplayAbilitySpec & Spec)
{
	Super::OnAvatarSet(ActorInfo, Spec);

	if (bActivateAbilityOnGranted)
	{
		ActorInfo->AbilitySystemComponent->TryActivateAbility(Spec.Handle, false);
	}
}
```

Epic은 이 함수를 패시브 어빌리티를 시작하고 `BeginPlay`에서 처리할 법한 작업을 수행하기에 적합한 위치로 설명한다.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-activating-failedtags"></a>
#### 4.6.4.2 활성화 실패 태그

어빌리티에는 활성화 실패 원인을 알려주는 기본 로직이 내장되어 있다. 이를 활성화하려면 기본 실패 케이스에 대응하는 GameplayTag를 설정해야 한다.

프로젝트에 아래 태그(또는 본인의 네이밍 컨벤션)를 추가한다:
```
+GameplayTagList=(Tag="Activation.Fail.BlockedByTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.CantAffordCost",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.IsDead",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.MissingTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.Networking",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.OnCooldown",DevComment="")
```

그런 다음 [`GASDocumentation\Config\DefaultGame.ini`](https://github.com/tranek/GASDocumentation/blob/master/Config/DefaultGame.ini#L8-L13)에 추가한다:
```
[/Script/GameplayAbilities.AbilitySystemGlobals]
ActivateFailIsDeadName=Activation.Fail.IsDead
ActivateFailCooldownName=Activation.Fail.OnCooldown
ActivateFailCostName=Activation.Fail.CantAffordCost
ActivateFailTagsBlockedName=Activation.Fail.BlockedByTags
ActivateFailTagsMissingName=Activation.Fail.MissingTags
ActivateFailNetworkingName=Activation.Fail.Networking
```

이제 어빌리티 활성화가 실패할 때마다 해당하는 GameplayTag가 출력 로그 메시지에 포함되거나 `showdebug AbilitySystem` HUD에 표시된다.
```
LogAbilitySystem: Display: InternalServerTryActivateAbility. Rejecting ClientActivation of Default__GA_FireGun_C. InternalTryActivateAbility failed: Activation.Fail.BlockedByTags
LogAbilitySystem: Display: ClientActivateAbilityFailed_Implementation. PredictionKey :109 Ability: Default__GA_FireGun_C
```

![Activation Failed Tags Displayed in showdebug AbilitySystem](https://github.com/tranek/GASDocumentation/raw/master/Images/activationfailedtags.png)

**[⬆ Back to Top](#table-of-contents)**
---

## 내 분석
