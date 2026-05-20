# Attribute 선언 & 초기화

> **GASDoc**: 4.4.3~4.4.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-attributes"></a>
#### Attribute를 복제 가능하게 선언하려면 어떤 단계를 거쳐야 하는가?

헤더 파일 상단에 `ATTRIBUTE_ACCESSORS` 매크로 블록을 추가한다. 이 매크로는 getter/setter/initter 함수를 자동 생성한다.

```c++
#define ATTRIBUTE_ACCESSORS(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_PROPERTY_GETTER(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_GETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_SETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_INITTER(PropertyName)
```

복제 가능한 Attribute 선언은 총 4단계로 구성된다.

**1단계 — 헤더에 프로퍼티와 OnRep 선언**
```c++
UPROPERTY(BlueprintReadOnly, Category = "Health", ReplicatedUsing = OnRep_Health)
FGameplayAttributeData Health;
ATTRIBUTE_ACCESSORS(UGDAttributeSetBase, Health)

UFUNCTION()
virtual void OnRep_Health(const FGameplayAttributeData& OldHealth);
```

**2단계 — .cpp에서 OnRep 구현** (예측 시스템과 연동하는 `GAMEPLAYATTRIBUTE_REPNOTIFY` 매크로 사용)
```c++
void UGDAttributeSetBase::OnRep_Health(const FGameplayAttributeData& OldHealth)
{
	GAMEPLAYATTRIBUTE_REPNOTIFY(UGDAttributeSetBase, Health, OldHealth);
}
```

**3단계 — GetLifetimeReplicatedProps에 등록**
```c++
void UGDAttributeSetBase::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);

	DOREPLIFETIME_CONDITION_NOTIFY(UGDAttributeSetBase, Health, COND_None, REPNOTIFY_Always);
}
```

`REPNOTIFY_Always`를 사용하는 이유: 예측으로 인해 로컬 값이 이미 서버 값과 동일한 경우에도 `OnRep`가 반드시 발동되도록 강제하기 위함이다. 기본값은 동일하면 발동하지 않는다.

Meta Attribute처럼 복제가 필요 없는 Attribute는 OnRep와 GetLifetimeReplicatedProps 단계를 생략한다.

<a name="concepts-as-init"></a>
#### Attribute의 초기값을 설정하는 권장 방식은 무엇이며, 왜 Instant GE를 사용하는가?

Epic 권장 방식은 **Instant `GameplayEffect`**를 사용하는 것이다. 샘플 프로젝트의 `GE_HeroAttributes`가 이 방식의 예시다.

Instant GE를 권장하는 이유는 GAS의 Attribute 변경 파이프라인(`PreAttributeChange`, `PostGameplayEffectExecute` 등)을 정상적으로 통과하기 때문이다.

`ATTRIBUTE_ACCESSORS` 매크로를 사용했다면 각 Attribute마다 initter 함수가 자동 생성되므로, C++에서 직접 호출하는 것도 가능하다.

```c++
// ATTRIBUTE_ACCESSORS 매크로로 자동 생성된 초기화 함수
AttributeSet->InitHealth(100.0f);
```

> **참고**: UE 4.24 이전에는 `FAttributeSetInitterDiscreteLevels`가 `FGameplayAttributeData`와 호환되지 않았다. 4.24에서 수정되었다(UE-76557).

---
