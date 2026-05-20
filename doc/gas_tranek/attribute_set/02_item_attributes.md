# 아이템 Attribute 패턴

> **GASDoc**: 4.4.2.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-design-itemattributes"></a>
##### 장착형 아이템(무기 탄약 등)에 Attribute를 구현하는 세 가지 방법과 각각의 트레이드오프는?

아이템은 생애 동안 여러 플레이어가 장착할 수 있으므로, 값은 아이템 자체에 저장해야 한다. 세 가지 방법은 다음과 같다.

| 방법 | 권장 여부 | 핵심 특징 |
|------|-----------|-----------|
| plain float 저장 | **권장** | GE 워크플로우 불가, 단순하고 제약 없음 |
| 별도 `AttributeSet` 사용 | 제한적 | GE 워크플로우 가능, 동일 종류 무기 2개 불가 |
| 별도 `ASC` 사용 | 비권장 | 실현 가능성 불확실, 엔지니어링 비용 막대 |

<a name="concepts-as-design-itemattributes-plainfloats"></a>
###### 아이템 Attribute를 plain float으로 저장하는 방식의 장단점은?

탄창 크기, 현재 탄약, 예비 탄약 등을 무기 클래스에 복제 가능한 float(`COND_OwnerOnly`)로 저장한다. Fortnite와 GASShooter가 이 방식을 사용한다.

자동 사격 중 서버 복제가 로컬 탄약 값을 덮어쓰는 것을 방지하려면 `PreReplication()`에서 `IsFiring` 태그가 있는 동안 복제를 비활성화한다.

```c++
void AGSWeapon::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
{
	Super::PreReplication(ChangedPropertyTracker);

	DOREPLIFETIME_ACTIVE_OVERRIDE(AGSWeapon, PrimaryClipAmmo, (IsValid(AbilitySystemComponent) && !AbilitySystemComponent->HasMatchingGameplayTag(WeaponIsFiringTag)));
	DOREPLIFETIME_ACTIVE_OVERRIDE(AGSWeapon, SecondaryClipAmmo, (IsValid(AbilitySystemComponent) && !AbilitySystemComponent->HasMatchingGameplayTag(WeaponIsFiringTag)));
}
```

- **장점**: `AttributeSet` 방식의 제약(동일 종류 무기 2개 불가, 제거 시 크래시)을 모두 회피한다.
- **단점**: Cost GE 등 기존 GE 워크플로우를 사용할 수 없고, `UGameplayAbility`의 핵심 함수들을 오버라이드해야 한다.

<a name="concepts-as-design-itemattributes-attributeset"></a>
###### 아이템에 별도 AttributeSet을 붙이는 방식은 왜 한 종류당 하나만 인벤토리에 둘 수 있는가?

ASC는 동일 클래스의 `AttributeSet`이 여러 개 있을 때 첫 번째 인스턴스만 사용한다. Attribute 변경 시 `SpawnedAttributes` 배열에서 해당 클래스의 첫 번째 인스턴스만 찾기 때문이다. 따라서 같은 종류의 무기를 인벤토리에 두 개 이상 소지할 수 없다.

`AttributeSet`이 `OwnerActor`가 아닌 무기에 위치하면 컴파일 오류가 발생할 수 있다. 생성자 대신 `BeginPlay()`에서 생성해 해결한다.

```c++
void AGSWeapon::BeginPlay()
{
	if (!AttributeSet)
	{
		AttributeSet = NewObject<UGSWeaponAttributeSet>(this);
	}
	//...
}
```

- **장점**: Cost GE 등 기존 GE 워크플로우를 그대로 사용할 수 있다.
- **단점**: 무기 종류마다 `AttributeSet` 클래스가 필요하고, 동일 종류 무기 2개 소지 불가, `AttributeSet` 제거 시 크래시 위험이 있다.

<a name="concepts-as-design-itemattributes-asc"></a>
###### 아이템마다 ASC를 두는 방식이 현실적으로 적용하기 어려운 이유는?

같은 Owner에 여러 ASC가 달리면 `IAbilitySystemInterface` 구현 시 어느 ASC가 권위적인지 결정하기 어렵고, GE 적용 대상을 특정하기 어렵다. Epic의 Dave Ratti도 실현 가능성은 있으나 복잡해질 것이라고 언급했다. 실제 구현 사례가 없고 엔지니어링 비용이 얼마나 들지 알 수 없다.

- **장점**: GE 워크플로우 사용 가능, `AttributeSet` 클래스 재사용 가능.
- **단점**: 엔지니어링 비용과 실현 가능성 모두 불확실하다.

---
