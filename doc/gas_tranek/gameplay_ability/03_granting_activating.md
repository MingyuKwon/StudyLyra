# GA 부여 & 활성화

> **GASDoc**: 4.6.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-granting"></a>
#### GA를 ASC에 부여(Grant)하는 방법과 서버에서만 해야 하는 이유는 무엇인가?

GA를 ASC에 부여하면 `ActivatableAbilities` 목록에 추가되어 조건이 충족될 때 활성화할 수 있게 된다. 부여는 **서버에서만** 수행하며, `GameplayAbilitySpec`이 owning client로 자동 복제된다. Simulated proxy는 스펙을 받지 않는다.

```c++
void AGDCharacterBase::AddCharacterAbilities()
{
    if (Role != ROLE_Authority || !AbilitySystemComponent.IsValid() || AbilitySystemComponent->bCharacterAbilitiesGiven)
        return;

    for (TSubclassOf<UGDGameplayAbility>& StartupAbility : CharacterAbilities)
    {
        AbilitySystemComponent->GiveAbility(
            FGameplayAbilitySpec(StartupAbility, GetAbilityLevel(StartupAbility.GetDefaultObject()->AbilityID), static_cast<int32>(StartupAbility.GetDefaultObject()->AbilityInputID), this));
    }

    AbilitySystemComponent->bCharacterAbilitiesGiven = true;
}
```

`GameplayAbilitySpec` 생성 시 GA 클래스, 레벨, 입력 바인딩, `SourceObject`(부여 주체)를 담아 전달한다.

<a name="concepts-ga-activating"></a>
#### GA를 활성화하는 방법에는 어떤 것들이 있으며, 로컬 예측 GA는 어떤 순서로 실행되는가?

입력 액션이 할당된 GA는 해당 입력이 눌리고 GameplayTag 요건이 충족되면 자동 활성화된다. 그 외 ASC가 제공하는 4가지 방법:

```c++
bool TryActivateAbilitiesByTag(const FGameplayTagContainer& GameplayTagContainer, bool bAllowRemoteActivation = true);
bool TryActivateAbilityByClass(TSubclassOf<UGameplayAbility> InAbilityToActivate, bool bAllowRemoteActivation = true);
bool TryActivateAbility(FGameplayAbilitySpecHandle AbilityToActivate, bool bAllowRemoteActivation = true);
bool TriggerAbilityFromGameplayEvent(FGameplayAbilitySpecHandle AbilityToTrigger, FGameplayAbilityActorInfo* ActorInfo, FGameplayTag Tag, const FGameplayEventData* Payload, UAbilitySystemComponent& Component);
FGameplayAbilitySpecHandle GiveAbilityAndActivateOnce(const FGameplayAbilitySpec& AbilitySpec, const FGameplayEventData* GameplayEventData);
```

이벤트로 GA를 활성화하려면 GA의 `Triggers`에 GameplayTag를 할당하고 `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor()`로 이벤트를 전송한다. 이벤트로 활성화하면 페이로드 데이터를 함께 전달할 수 있다. GA `Triggers`는 GameplayTag가 추가/제거될 때 활성화하는 것도 지원한다.

> **참고**: Blueprint에서 이벤트로 GA를 활성화할 때는 반드시 `ActivateAbilityFromEvent` 노드를 사용해야 한다.

> **참고**: 패시브 어빌리티가 아니라면 GA가 종료되어야 할 시점에 반드시 `EndAbility()`를 호출해야 한다.

**로컬 예측(locally predicted) GA의 활성화 순서:**

1. **Owning client**가 `TryActivateAbility()` 호출
2. `InternalTryActivateAbility()` 호출
3. `CanActivateAbility()`로 GameplayTag 요건, 코스트, 쿨다운, 중복 활성화 여부 확인
4. `Prediction Key`를 전달하며 `CallServerTryActivateAbility()` 호출
5. `CallActivateAbility()` → `PreActivate()` → `ActivateAbility()` 순으로 실행

**서버**는 `CallServerTryActivateAbility()`를 수신하면:

1. `InternalTryActivateAbility()` → `CanActivateAbility()` 확인
2. 성공 시 `ClientActivateAbilitySucceed()`로 클라이언트에 승인 통보
3. `CallActivateAbility()` → `PreActivate()` → `ActivateAbility()` 실행

서버가 활성화에 실패하면 `ClientActivateAbilityFailed()`를 호출하여 클라이언트의 GA를 즉시 종료하고 예측 변경 사항을 롤백한다.

<a name="concepts-ga-activating-passive"></a>
#### 패시브 GA를 어떻게 구현하며, OnAvatarSet을 사용하는 이유는 무엇인가?

`UGameplayAbility::OnAvatarSet()`을 오버라이드한다. 이 함수는 GA가 부여되고 `AvatarActor`가 설정될 때 자동 호출되므로, 여기서 `TryActivateAbility()`를 호출하면 부여 즉시 자동 활성화된다.

```c++
void UGDGameplayAbility::OnAvatarSet(const FGameplayAbilityActorInfo* ActorInfo, const FGameplayAbilitySpec& Spec)
{
    Super::OnAvatarSet(ActorInfo, Spec);

    if (bActivateAbilityOnGranted)
        ActorInfo->AbilitySystemComponent->TryActivateAbility(Spec.Handle, false);
}
```

패시브 GA는 일반적으로 `Net Execution Policy`를 `Server Only`로 설정한다.

<a name="concepts-ga-activating-failedtags"></a>
#### GA 활성화가 실패했을 때 어떤 GameplayTag로 실패 원인을 진단할 수 있는가?

프로젝트에 실패 원인별 태그를 추가하고 `DefaultGame.ini`에 등록하면, 활성화 실패 시 로그와 `showdebug AbilitySystem` HUD에 원인이 표시된다.

태그 예시:
```
+GameplayTagList=(Tag="Activation.Fail.BlockedByTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.CantAffordCost",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.IsDead",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.MissingTags",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.Networking",DevComment="")
+GameplayTagList=(Tag="Activation.Fail.OnCooldown",DevComment="")
```

`DefaultGame.ini` 설정:
```
[/Script/GameplayAbilities.AbilitySystemGlobals]
ActivateFailIsDeadName=Activation.Fail.IsDead
ActivateFailCooldownName=Activation.Fail.OnCooldown
ActivateFailCostName=Activation.Fail.CantAffordCost
ActivateFailTagsBlockedName=Activation.Fail.BlockedByTags
ActivateFailTagsMissingName=Activation.Fail.MissingTags
ActivateFailNetworkingName=Activation.Fail.Networking
```

로그 출력 예시:
```
LogAbilitySystem: Display: InternalServerTryActivateAbility. Rejecting ClientActivation of Default__GA_FireGun_C. InternalTryActivateAbility failed: Activation.Fail.BlockedByTags
LogAbilitySystem: Display: ClientActivateAbilityFailed_Implementation. PredictionKey :109 Ability: Default__GA_FireGun_C
```

![Activation Failed Tags Displayed in showdebug AbilitySystem](https://github.com/tranek/GASDocumentation/raw/master/Images/activationfailedtags.png)

---
