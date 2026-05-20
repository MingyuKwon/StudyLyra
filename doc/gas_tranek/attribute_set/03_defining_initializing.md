# Attribute 선언 & 초기화

> **GASDoc**: 4.4.3~4.4.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-attributes"></a>
#### Attribute를 복제 가능하게 선언하려면 어떤 단계를 거쳐야 하는가?

**`Attribute`는 `AttributeSet`의 헤더 파일에서 C++로만 정의할 수 있다.** 모든 `AttributeSet` 헤더 파일 상단에 다음 매크로 블록을 추가하는 것을 권장한다. 이 매크로는 각 `Attribute`에 대한 getter 및 setter 함수를 자동으로 생성해 준다.

```c++
// Uses macros from AttributeSet.h
#define ATTRIBUTE_ACCESSORS(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_PROPERTY_GETTER(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_GETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_SETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_INITTER(PropertyName)
```

복제 가능한 Health Attribute는 다음과 같이 정의한다:

```c++
UPROPERTY(BlueprintReadOnly, Category = "Health", ReplicatedUsing = OnRep_Health)
FGameplayAttributeData Health;
ATTRIBUTE_ACCESSORS(UGDAttributeSetBase, Health)
```

헤더에 `OnRep` 함수도 선언한다:
```c++
UFUNCTION()
virtual void OnRep_Health(const FGameplayAttributeData& OldHealth);
```

`AttributeSet`의 .cpp 파일에서는 예측 시스템이 사용하는 `GAMEPLAYATTRIBUTE_REPNOTIFY` 매크로로 `OnRep` 함수를 구현한다:
```c++
void UGDAttributeSetBase::OnRep_Health(const FGameplayAttributeData& OldHealth)
{
	GAMEPLAYATTRIBUTE_REPNOTIFY(UGDAttributeSetBase, Health, OldHealth);
}
```

마지막으로 `GetLifetimeReplicatedProps`에 `Attribute`를 추가한다:
```c++
void UGDAttributeSetBase::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);

	DOREPLIFETIME_CONDITION_NOTIFY(UGDAttributeSetBase, Health, COND_None, REPNOTIFY_Always);
}
```

`REPNOTIFY_Always`는 예측으로 인해 로컬 값이 이미 서버에서 복제된 값과 동일한 경우에도 `OnRep` 함수를 발동시키도록 지시한다. 기본적으로는 로컬 값이 서버에서 복제된 값과 동일하면 `OnRep` 함수가 발동되지 않는다.

`Meta Attribute`처럼 복제가 필요 없는 `Attribute`라면 `OnRep`와 `GetLifetimeReplicatedProps` 단계는 생략해도 된다.

<a name="concepts-as-init"></a>
#### Attribute의 초기값을 설정하는 권장 방식은 무엇이며, 왜 Instant GE를 사용하는가?

`Attribute`를 초기화(즉, `BaseValue`와 그에 따른 `CurrentValue`를 초기값으로 설정)하는 방법은 여러 가지가 있다. Epic은 인스턴트 `GameplayEffect`를 사용하는 방식을 권장하며, 샘플 프로젝트에서도 이 방식을 사용한다.

샘플 프로젝트의 `GE_HeroAttributes` 블루프린트를 통해 인스턴트 `GameplayEffect`로 `Attribute`를 초기화하는 방법을 확인할 수 있다. 이 `GameplayEffect`의 적용은 C++에서 이루어진다.

`Attribute`를 정의할 때 `ATTRIBUTE_ACCESSORS` 매크로를 사용했다면, 각 `Attribute`에 대한 초기화 함수가 `AttributeSet`에 자동으로 생성되므로 C++에서 원하는 시점에 직접 호출할 수 있다.

```c++
// InitHealth(float InitialValue) is an automatically generated function for an Attribute 'Health' defined with the `ATTRIBUTE_ACCESSORS` macro
AttributeSet->InitHealth(100.0f);
```

`Attribute`를 초기화하는 더 많은 방법은 `AttributeSet.h`를 참고한다.

> **참고**  
> 언리얼 4.24 이전에는 `FAttributeSetInitterDiscreteLevels`가 `FGameplayAttributeData`와 호환되지 않았다. `Attribute`가 raw float이던 시절에 만들어진 것으로, `FGameplayAttributeData`가 Plain Old Data(`POD`)가 아니라는 오류가 발생했다. 이 문제는 4.24에서 수정되었다: https://issues.unrealengine.com/issue/UE-76557.

---

