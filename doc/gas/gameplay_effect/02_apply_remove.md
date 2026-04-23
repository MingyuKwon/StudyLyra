# GE 적용 & 제거

> **GASDoc**: 4.5.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-applying"></a>
#### 4.5.2 GameplayEffect 적용

`GameplayEffect`는 [GameplayAbility](#concepts-ga)의 함수나 ASC의 함수를 통해 다양한 방식으로 적용할 수 있으며, 보통 `ApplyGameplayEffectTo` 형태의 함수를 사용한다. 이 함수들은 결국 Target의 `UAbilitySystemComponent::ApplyGameplayEffectSpecToSelf()`를 호출하는 편의 래퍼다.

GameplayAbility 외부(예: 발사체)에서 GE를 적용하려면, Target의 ASC를 직접 가져와 `ApplyGameplayEffectToSelf` 계열 함수를 사용한다.

ASC에 `Duration` 또는 `Infinite` GE가 적용되는 시점을 감지하려면 델리게이트를 바인딩한다.

```c++
AbilitySystemComponent->OnActiveGameplayEffectAddedDelegateToSelf.AddUObject(this, &APACharacterBase::OnActiveGameplayEffectAddedCallback);
```
콜백 함수:
```c++
virtual void OnActiveGameplayEffectAddedCallback(UAbilitySystemComponent* Target, const FGameplayEffectSpec& SpecApplied, FActiveGameplayEffectHandle ActiveHandle);
```

서버는 복제 모드와 무관하게 항상 이 함수를 호출한다. Autonomous Proxy는 `Full` 및 `Mixed` 복제 모드에서 복제된 GameplayEffect에 대해서만 호출된다. Simulated Proxy는 `Full` [복제 모드](#concepts-asc-rm)에서만 호출된다.

<a name="concepts-ga-removing"></a>
#### 4.5.3 GameplayEffect 제거

`GameplayEffect`도 [GameplayAbility](#concepts-ga)의 함수나 ASC의 함수를 통해 다양한 방식으로 제거할 수 있으며, 보통 `RemoveActiveGameplayEffect` 형태의 함수를 사용한다. 이 함수들은 결국 Target의 `FActiveGameplayEffectsContainer::RemoveActiveEffects()`를 호출하는 편의 래퍼다.

GameplayAbility 외부에서 GE를 제거하려면, Target의 ASC를 직접 가져와 해당 함수를 호출한다.

ASC에서 `Duration` 또는 `Infinite` GE가 제거되는 시점을 감지하려면 델리게이트를 바인딩한다.

```c++
AbilitySystemComponent->OnAnyGameplayEffectRemovedDelegate().AddUObject(this, &APACharacterBase::OnRemoveGameplayEffectCallback);
```
콜백 함수:
```c++
virtual void OnRemoveGameplayEffectCallback(const FActiveGameplayEffect& EffectRemoved);
```

서버는 복제 모드와 무관하게 항상 이 함수를 호출한다. Autonomous Proxy는 `Full` 및 `Mixed` 복제 모드에서 복제된 GameplayEffect에 대해서만 호출된다. Simulated Proxy는 `Full` [복제 모드](#concepts-asc-rm)에서만 호출된다.

---

## 내 분석
