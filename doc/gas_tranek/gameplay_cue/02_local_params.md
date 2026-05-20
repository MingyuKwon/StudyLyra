# Local Cue & Parameters

> **GASDoc**: 4.8.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-local"></a>
#### 로컬 GameplayCue를 쓰는 이유는 무엇이고 어떤 상황에서 써야 하는가?

기본 `GameplayCue` 함수는 멀티캐스트 RPC로 전송되어 대량의 RPC를 유발할 수 있다. GAS는 네트 업데이트당 동일한 GameplayCue RPC를 최대 두 개로 제한한다. **로컬 GameplayCue**는 개별 클라이언트에서만 실행되므로 이 RPC 비용을 없앤다.

로컬 GameplayCue가 적합한 상황:
- 발사체 임팩트
- 근접 충돌 임팩트
- 애니메이션 몽타주에서 발동하는 GameplayCue

ASC 서브클래스에 추가해야 하는 함수 선언:

```c++
UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void ExecuteGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void AddGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

UFUNCTION(BlueprintCallable, Category = "GameplayCue", Meta = (AutoCreateRefTerm = "GameplayCueParameters", GameplayTagFilter = "GameplayCue"))
void RemoveGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);
```

```c++
void UPAAbilitySystemComponent::ExecuteGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters)
{
    UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::Executed, GameplayCueParameters);
}

void UPAAbilitySystemComponent::AddGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters)
{
    UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::OnActive, GameplayCueParameters);
    UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::WhileActive, GameplayCueParameters);
}

void UPAAbilitySystemComponent::RemoveGameplayCueLocal(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters)
{
    UAbilitySystemGlobals::Get().GetGameplayCueManager()->HandleGameplayCue(GetOwner(), GameplayCueTag, EGameplayCueEvent::Type::Removed, GameplayCueParameters);
}
```

> 로컬로 `Added`된 GameplayCue는 반드시 로컬로 `Removed`해야 한다. 복제로 추가된 것은 복제로 제거해야 한다.

<a name="concepts-gc-parameters"></a>
#### FGameplayCueParameters 구조체는 어떤 정보를 담으며 GE 트리거 시 자동으로 채워지는 필드는?

`FGameplayCueParameters`는 GameplayCue가 필요로 하는 추가 정보를 전달하는 구조체다. GameplayAbility 또는 ASC 함수로 수동 트리거할 때는 직접 채워야 하지만, **GameplayEffect로 트리거될 때는 아래 필드가 자동으로 채워진다**:

- `AggregatedSourceTags`
- `AggregatedTargetTags`
- `GameplayEffectLevel`
- `AbilityLevel`
- `EffectContext`
- `Magnitude` (GE에 Magnitude용 Attribute와 해당 Attribute에 영향을 주는 Modifier가 있는 경우)

수동 트리거 시 임의 데이터를 전달하려면 `SourceObject` 필드를 활용하면 된다.

> `EffectContext`를 서브클래싱하면 GE로 트리거되는 GameplayCue에 더 많은 데이터를 전달할 수 있다. `UAbilitySystemGlobals`의 아래 virtual 함수들을 오버라이드하면 자동 채움 항목을 확장할 수 있다:

```c++
virtual void InitGameplayCueParameters(FGameplayCueParameters& CueParameters, const FGameplayEffectSpecForRPC& Spec);
virtual void InitGameplayCueParameters_GESpec(FGameplayCueParameters& CueParameters, const FGameplayEffectSpec& Spec);
virtual void InitGameplayCueParameters(FGameplayCueParameters& CueParameters, const FGameplayEffectContextHandle& EffectContext);
```

---
