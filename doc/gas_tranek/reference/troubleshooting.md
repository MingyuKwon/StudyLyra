# 트러블슈팅

> **GASDoc**: 9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="troubleshooting"></a>
## 9. 트러블슈팅

<a name="troubleshooting-notlocal"></a>
### 9.1 `LogAbilitySystem: Warning: Can't activate LocalOnly or LocalPredicted ability %s when not local!`

클라이언트에서 ASC 초기화가 누락된 경우에 발생한다. 클라이언트 측 ASC 셋업을 확인한다.

<a name="troubleshooting-scriptstructcache"></a>
### 9.2 `ScriptStructCache` 오류

`UAbilitySystemGlobals::InitGlobalData()`가 호출되지 않아서 발생한다. 프로젝트 초기화 시 반드시 호출해야 한다.

<a name="troubleshooting-replicatinganimmontages"></a>
### 9.3 애니메이션 몽타주가 클라이언트에 복제되지 않음

GameplayAbility 내부에서 `PlayMontage` 노드 대신 `PlayMontageAndWait` Blueprint 노드를 사용해야 한다. 이 AbilityTask는 ASC를 통해 몽타주를 자동으로 복제하지만, `PlayMontage` 노드는 그렇지 않다.

<a name="troubleshooting-duplicatingblueprintactors"></a>
### 9.4 블루프린트 액터 복제 시 AttributeSet 포인터가 nullptr이 되는 문제

기존 블루프린트 액터 클래스를 복제(Duplicate)하면 해당 클래스의 AttributeSet 포인터가 nullptr로 설정되는 [언리얼 엔진 버그](https://issues.unrealengine.com/issue/UE-81109)가 있다. 몇 가지 해결 방법이 있는데, 필자가 효과를 확인한 방법은 클래스에 별도의 AttributeSet 포인터를 선언하지 않는 것이다(.h에 포인터 선언 없음, 생성자에서 `CreateDefaultSubobject` 미호출). 대신 `PostInitializeComponents()`에서 AttributeSet을 ASC에 직접 추가한다(샘플 프로젝트에는 나와 있지 않음). 복제된 AttributeSet은 ASC의 `SpawnedAttributes` 배열에 계속 유지된다. 코드 예시는 다음과 같다:

```c++
void AGDPlayerState::PostInitializeComponents()
{
	Super::PostInitializeComponents();

	if (AbilitySystemComponent)
	{
		AbilitySystemComponent->AddSet<UGDAttributeSetBase>();
		// ... any other AttributeSets that you may have
	}
}
```

이 방식에서는 매크로로 생성된 AttributeSet의 함수를 사용하는 대신, ASC의 함수를 통해 AttributeSet의 값을 읽고 쓴다.

```c++
/** Returns current (final) value of an attribute */
float GetNumericAttribute(const FGameplayAttribute &Attribute) const;

/** Sets the base value of an attribute. Existing active modifiers are NOT cleared and will act upon the new base value. */
void SetNumericAttributeBase(const FGameplayAttribute &Attribute, float NewBaseValue);
```

예를 들어 `GetHealth()`는 다음과 같이 구현할 수 있다:

```c++
float AGDPlayerState::GetHealth() const
{
	if (AbilitySystemComponent)
	{
		return AbilitySystemComponent->GetNumericAttribute(UGDAttributeSetBase::GetHealthAttribute());
	}

	return 0.0f;
}
```

체력 Attribute를 설정(초기화)하는 코드는 다음과 같다:

```c++
const float NewHealth = 100.0f;
if (AbilitySystemComponent)
{
	AbilitySystemComponent->SetNumericAttributeBase(UGDAttributeSetBase::GetHealthAttribute(), NewHealth);
}
```

참고로 ASC는 AttributeSet 클래스당 최대 하나의 객체만 허용한다.

<a name="troubleshooting-unresolvedexternalsymbolmarkpropertydirty"></a>
### 9.5 링커 오류: `UEPushModelPrivate::MarkPropertyDirty(int,int)` unresolved external symbol

다음과 같은 컴파일 오류가 발생하는 경우:

```
error LNK2019: unresolved external symbol "__declspec(dllimport) void __cdecl UEPushModelPrivate::MarkPropertyDirty(int,int)" (__imp_?MarkPropertyDirty@UEPushModelPrivate@@YAXHH@Z) referenced in function "public: void __cdecl FFastArraySerializer::IncrementArrayReplicationKey(void)" (?IncrementArrayReplicationKey@FFastArraySerializer@@QEAAXXZ)
```

이 오류는 `FFastArraySerializer`에서 `MarkItemDirty()`를 호출할 때 발생한다. 쿨다운 지속 시간 업데이트 등 `ActiveGameplayEffect`를 갱신하는 경우에 주로 나타난다.

```c++
ActiveGameplayEffects.MarkItemDirty(*AGE);
```

원인은 `WITH_PUSH_MODEL` 매크로가 여러 곳에서 서로 다른 값으로 정의되는 것이다. `PushModelMacros.h`에서는 0으로 정의하지만, 다른 여러 곳에서는 1로 정의한다. `PushModel.h`는 1로 인식하지만 `PushModel.cpp`는 0으로 인식한다.

해결책은 프로젝트의 `Build.cs`에서 `PublicDependencyModuleNames`에 `NetCore`를 추가하는 것이다.

<a name="troubleshooting-enumnamesarenowpathnames"></a>
### 9.6 Enum 이름이 이제 경로명으로 표현됨 (UE 5.1+)

다음과 같은 컴파일 경고가 발생하는 경우:

```
warning C4996: 'FGameplayAbilityInputBinds::FGameplayAbilityInputBinds': Enum names are now represented by path names. Please use a version of FGameplayAbilityInputBinds constructor that accepts FTopLevelAssetPath. Please update your code to the new API before upgrading to the next release, otherwise your project will no longer compile.
```

UE 5.1부터 `BindAbilityActivationToInputComponent()`의 생성자에서 `FString`을 사용하는 방식이 deprecated되었다. 대신 `FTopLevelAssetPath`를 사용해야 한다.

기존 방식 (deprecated):
```c++
AbilitySystemComponent->BindAbilityActivationToInputComponent(InputComponent, FGameplayAbilityInputBinds(FString("ConfirmTarget"),
	FString("CancelTarget"), FString("EGDAbilityInputID"), static_cast<int32>(EGDAbilityInputID::Confirm), static_cast<int32>(EGDAbilityInputID::Cancel)));
```

신규 방식:
```c++
FTopLevelAssetPath AbilityEnumAssetPath = FTopLevelAssetPath(FName("/Script/GASDocumentation"), FName("EGDAbilityInputID"));
AbilitySystemComponent->BindAbilityActivationToInputComponent(InputComponent, FGameplayAbilityInputBinds(FString("ConfirmTarget"),
	FString("CancelTarget"), AbilityEnumAssetPath, static_cast<int32>(EGDAbilityInputID::Confirm), static_cast<int32>(EGDAbilityInputID::Cancel)));
```

자세한 내용은 `Engine\Source\Runtime\CoreUObject\Public\UObject\TopLevelAssetPath.h`를 참조한다.

---

