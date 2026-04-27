# Local Cue & Parameters

> **GASDoc**: 4.8.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gc-local"></a>
#### 4.8.3 로컬 GameplayCue

`GameplayAbility`와 ASC에서 `GameplayCue`를 발동하는 노출된 함수들은 기본적으로 복제된다. 각 `GameplayCue` 이벤트는 멀티캐스트 RPC로 전송된다. 이로 인해 대량의 RPC가 발생할 수 있다. GAS는 또한 네트 업데이트당 동일한 `GameplayCue` RPC를 최대 두 개로 제한한다. 가능한 경우 로컬 `GameplayCue`를 사용하여 이를 방지한다. 로컬 `GameplayCue`는 개별 클라이언트에서만 `Execute`, `Add`, `Remove`가 실행된다.

로컬 `GameplayCue`를 사용할 수 있는 상황:
* 발사체 임팩트
* 근접 충돌 임팩트
* 애니메이션 몽타주에서 발동하는 `GameplayCue`

ASC 서브클래스에 추가해야 하는 로컬 `GameplayCue` 함수:

```c++
UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void ExecuteGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void AddGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void RemoveGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);
```

```c++
void UPAAbilitySystemComponent::ExecuteGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters & GameplayCueParameters)
{
	UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::Executed, GameplayCueParameters);
}

void UPAAbilitySystemComponent::AddGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters & GameplayCueParameters)
{
	UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::OnActive, GameplayCueParameters);
	UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::WhileActive, GameplayCueParameters);
}

void UPAAbilitySystemComponent::RemoveGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters & GameplayCueParameters)
{
	UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::Removed, GameplayCueParameters);
}
```

`GameplayCue`가 로컬로 `Added`되었다면 반드시 로컬로 `Removed`해야 한다. 복제를 통해 `Added`되었다면 복제를 통해 `Removed`해야 한다.

<a name="concepts-gc-parameters"></a>
#### 4.8.4 GameplayCue Parameters

`GameplayCue`는 파라미터로 `FGameplayCueParameters` 구조체를 받아 `GameplayCue`에 필요한 추가 정보를 전달한다. `GameplayAbility` 또는 ASC의 함수를 통해 `GameplayCue`를 수동으로 트리거하는 경우 `GameplayCue`에 전달되는 `GameplayCueParameters` 구조체를 직접 채워야 한다. `GameplayCue`가 `GameplayEffect`에 의해 트리거되는 경우에는 `GameplayCueParameters` 구조체의 다음 변수들이 자동으로 채워진다:

* AggregatedSourceTags
* AggregatedTargetTags
* GameplayEffectLevel
* AbilityLevel
* EffectContext
* Magnitude (`GameplayEffect`에 드롭다운에서 선택한 Magnitude용 `Attribute`가 있고, 해당 `Attribute`에 영향을 주는 `Modifier`가 있는 경우)

`GameplayCue`를 수동으로 트리거할 때 임의 데이터를 `GameplayCue`에 전달하기에 `GameplayCueParameters` 구조체의 `SourceObject` 변수가 적합한 위치가 될 수 있다.

> **참고**  
> 파라미터 구조체의 `Instigator` 같은 일부 변수는 이미 `EffectContext`에 존재할 수 있다. `EffectContext`는 `GameplayCue`가 월드에서 스폰될 위치 정보로 `FHitResult`를 포함할 수도 있다. `EffectContext`를 서브클래싱하는 것은 특히 `GameplayEffect`에 의해 트리거되는 `GameplayCue`에 더 많은 데이터를 전달하는 좋은 방법이 될 수 있다.

`GameplayCueParameters` 구조체를 채우는 `UAbilitySystemGlobals`의 세 가지 함수를 참고하라. 이 함수들은 virtual이므로 더 많은 정보를 자동으로 채우도록 오버라이드할 수 있다.

```c++
/** Initialize GameplayCue Parameters */
virtual void InitGameplayCueParameters(FGameplayCueParameters& CueParameters, const FGameplayEffectSpecForRPC &Spec);
virtual void InitGameplayCueParameters_GESpec(FGameplayCueParameters& CueParameters, const FGameplayEffectSpec &Spec);
virtual void InitGameplayCueParameters(FGameplayCueParameters& CueParameters, const FGameplayEffectContextHandle& EffectContext);
```

---

## 내 분석
