# 아이템 Attribute 패턴

> **GASDoc**: 4.4.2.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name=”concepts-as-design-itemattributes”></a>
##### 4.4.2.3 아이템 Attribute (무기 탄약 등)

장착 가능한 아이템(무기 탄약, 방어구 내구도 등)에 `Attribute`를 구현하는 방법은 몇 가지가 있다. 이 접근 방식들은 모두 값을 아이템 자체에 직접 저장한다. 아이템은 생애 동안 여러 플레이어가 장착할 수 있기 때문에 이렇게 해야 한다.

> 1. 아이템에 평범한 float 저장 (**권장**)
> 1. 아이템에 별도 `AttributeSet` 사용
> 1. 아이템에 별도 `ASC` 사용

<a name=”concepts-as-design-itemattributes-plainfloats”></a>
###### 4.4.2.3.1 아이템에 plain float 저장

`Attribute` 대신, 최대 탄창 크기, 현재 탄약, 예비 탄약 등을 총기 클래스 인스턴스에 복제 가능한 float(`COND_OwnerOnly`)로 직접 저장한다. Fortnite와 [GASShooter](https://github.com/tranek/GASShooter)는 총기 탄약을 이 방식으로 처리한다. 무기끼리 예비 탄약을 공유해야 한다면, 예비 탄약은 캐릭터의 공유 탄약 `AttributeSet` 내 `Attribute`로 이동시키면 된다(재장전 GA는 `Cost GE`를 사용하여 예비 탄약에서 총기의 float 탄창 탄약으로 끌어올 수 있다). 현재 탄창 탄약에 `Attribute`를 사용하지 않으므로, `UGameplayAbility`의 일부 함수를 오버라이드하여 총기의 float를 기준으로 탄약 비용을 확인하고 적용해야 한다. GA 부여 시 [`GameplayAbilitySpec`](https://github.com/tranek/GASDocumentation#concepts-ga-spec)에서 총기를 `SourceObject`로 설정하면 GA 내부에서 해당 총기에 접근할 수 있다.

자동 사격 중 서버 복제가 로컬 탄약 값을 덮어쓰는 것을 방지하려면, `PreReplication()`에서 플레이어에게 `IsFiring` `GameplayTag`가 있는 동안 복제를 비활성화한다. 이는 본질적으로 자체적인 로컬 예측을 수행하는 것이다.

```c++
void AGSWeapon::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
{
	Super::PreReplication(ChangedPropertyTracker);

	DOREPLIFETIME_ACTIVE_OVERRIDE(AGSWeapon, PrimaryClipAmmo, (IsValid(AbilitySystemComponent) && !AbilitySystemComponent->HasMatchingGameplayTag(WeaponIsFiringTag)));
	DOREPLIFETIME_ACTIVE_OVERRIDE(AGSWeapon, SecondaryClipAmmo, (IsValid(AbilitySystemComponent) && !AbilitySystemComponent->HasMatchingGameplayTag(WeaponIsFiringTag)));
}
```

장점:
1. `AttributeSet` 사용 시의 제약(아래 참고)을 회피할 수 있다.

단점:
1. 기존 `GameplayEffect` 워크플로우(탄약 사용을 위한 `Cost GE` 등)를 사용할 수 없다.
1. 총기의 float에 대해 탄약 비용을 확인하고 적용하기 위해 `UGameplayAbility`의 핵심 함수들을 오버라이드하는 작업이 필요하다.

<a name=”concepts-as-design-itemattributes-attributeset”></a>
###### 4.4.2.3.2 아이템에 AttributeSet 사용

아이템에 별도 `AttributeSet`을 두고, [플레이어의 인벤토리에 추가될 때 플레이어 ASC에 등록](#concepts-as-design-addremoveruntime)하는 방식은 작동은 하지만 몇 가지 중요한 제약이 있다. 초기 [GASShooter](https://github.com/tranek/GASShooter) 버전에서 무기 탄약에 이 방식을 사용한 적이 있다. 무기는 최대 탄창 크기, 현재 탄약, 예비 탄약 등을 무기 클래스에 있는 `AttributeSet`에 저장한다. 예비 탄약을 공유해야 한다면 캐릭터의 공유 탄약 `AttributeSet`에 두면 된다. 서버에서 무기가 인벤토리에 추가되면, 무기는 자신의 `AttributeSet`을 플레이어 `ASC::SpawnedAttributes`에 추가하고 서버는 이를 클라이언트에 복제한다. 무기가 인벤토리에서 제거되면 `ASC::SpawnedAttributes`에서도 제거된다.

`AttributeSet`이 `OwnerActor`가 아닌 곳(예: 무기)에 위치하면 초기에 컴파일 오류가 발생할 수 있다. 해결책은 생성자 대신 `BeginPlay()`에서 `AttributeSet`을 생성하고, 무기에 `IAbilitySystemInterface`를 구현하여 플레이어 인벤토리에 무기를 추가할 때 ASC 포인터를 설정하는 것이다.

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

이 방식의 실제 구현은 [GASShooter의 구버전](https://github.com/tranek/GASShooter/tree/df5949d0dd992bd3d76d4a728f370f2e2c827735)에서 확인할 수 있다.

장점:
1. 기존 `GameplayAbility`와 `GameplayEffect` 워크플로우(탄약 사용을 위한 `Cost GE` 등)를 활용할 수 있다.
1. 소수의 아이템 종류에 대해서는 설정이 간단하다.

단점:
1. 무기 종류마다 새로운 `AttributeSet` 클래스를 만들어야 한다. `ASC`는 클래스당 하나의 `AttributeSet` 인스턴스만 실질적으로 사용할 수 있는데, 이는 `Attribute`의 변경이 `ASC`의 `SpawnedAttributes` 배열에서 해당 `AttributeSet` 클래스의 첫 번째 인스턴스를 찾기 때문이다. 같은 클래스의 추가 인스턴스는 무시된다.
1. 위의 이유(클래스당 하나의 `AttributeSet` 인스턴스)로 인해 인벤토리에 같은 종류의 무기를 두 개 이상 소지할 수 없다.
1. `AttributeSet`을 제거하는 것은 위험하다. GASShooter에서 플레이어가 로켓으로 자멸했을 때, 플레이어는 즉시 인벤토리에서 로켓 런처를 제거했고(ASC에서 해당 `AttributeSet`도 제거), 서버가 로켓 런처의 탄약 `Attribute` 변경을 복제했을 때 클라이언트 `ASC`에는 해당 `AttributeSet`이 더 이상 존재하지 않아 게임이 크래시되었다.

<a name=”concepts-as-design-itemattributes-asc”></a>
###### 4.4.2.3.3 아이템에 ASC 사용

각 아이템에 `AbilitySystemComponent` 전체를 두는 것은 극단적인 접근 방식이다. 필자는 직접 구현해본 적이 없고 실제로 사용된 사례도 본 적이 없다. 이를 동작하게 만들려면 상당한 엔지니어링 작업이 필요할 것이다.

> 같은 Owner지만 다른 아바타를 가진 여러 AbilitySystemComponent(예: Pawn과 무기/아이템/투사체, Owner는 PlayerState로 설정)를 두는 것이 실현 가능한가?
>
> 첫 번째 문제는 OwningActor에서 `IGameplayTagAssetInterface`와 `IAbilitySystemInterface`를 구현하는 것이다. 전자는 가능할 수 있다: 모든 ASC의 태그를 집계하면 되지만(`HasAllMatchingGameplayTags`는 ASC 간 교차 집계를 통해서만 충족될 수 있으므로, 각 ASC에 호출을 전달하고 결과를 OR로 합치는 것만으로는 부족하다), 후자는 더욱 까다롭다: 어느 ASC가 권위적인가? 누군가 GE를 적용하려 할 때 어느 쪽이 받아야 하는가? 이런 문제들을 해결할 수 있을지도 모르지만, 이 측면이 가장 어렵다: Owner 하나에 여러 ASC가 달려 있는 상황이 되기 때문이다.
>
> Pawn과 무기에 각각 별도 ASC를 두는 것은 그 자체로는 의미가 있을 수 있다. 예를 들어, 무기를 설명하는 태그와 소유 Pawn을 설명하는 태그를 구분하는 것이다. 어쩌면 무기에 부여된 태그가 Owner에도 '적용'되지만 그 반대는 아닌 것(예: Attribute와 GE는 독립적이지만, Owner는 위에서 설명한 것처럼 소유한 태그를 집계)이 말이 될 수도 있다. 이렇게 구현하면 작동할 수 있을 것이다. 하지만 같은 Owner에 여러 ASC를 두는 것은 복잡해질 수 있다.

*Epic의 Dave Ratti가 [커뮤니티 질문 #6](https://epicgames.ent.box.com/s/m1egifkxv3he3u3xezb9hzbgroxyhx89)에 답한 내용*

장점:
1. 기존 `GameplayAbility`와 `GameplayEffect` 워크플로우(탄약 사용을 위한 `Cost GE` 등)를 활용할 수 있다.
1. `AttributeSet` 클래스를 재사용할 수 있다(각 무기의 ASC에 하나씩).

단점:
1. 엔지니어링 비용이 얼마나 들지 알 수 없다.
1. 실현 가능한지조차 불확실하다.

---

## 내 분석
