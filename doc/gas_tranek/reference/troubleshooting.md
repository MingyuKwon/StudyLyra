# 트러블슈팅

> **GASDoc**: 9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="troubleshooting"></a>
## GAS 개발 중 자주 만나는 오류와 해결 방법은 무엇인가?

<a name="troubleshooting-notlocal"></a>
### "Can't activate LocalOnly or LocalPredicted ability when not local" 경고는 무엇이 원인인가?

클라이언트 측 ASC 초기화가 누락된 경우다. 클라이언트 측 ASC 셋업 코드를 확인한다.

<a name="troubleshooting-scriptstructcache"></a>
### ScriptStructCache 오류로 클라이언트 연결이 끊기는 원인과 해결책은?

`UAbilitySystemGlobals::InitGlobalData()`가 호출되지 않은 경우다. 프로젝트 초기화 시 반드시 호출해야 한다.

<a name="troubleshooting-replicatinganimmontages"></a>
### GA 내에서 PlayMontage 노드를 써도 몽타주가 클라이언트에 복제되지 않는 이유는?

`PlayMontage` 노드는 ASC를 통한 복제를 하지 않는다. GameplayAbility 내부에서는 반드시 `PlayMontageAndWait` AbilityTask를 사용해야 한다. 이 노드는 ASC를 통해 몽타주를 자동으로 복제한다.

<a name="troubleshooting-duplicatingblueprintactors"></a>
### 블루프린트 액터를 Duplicate하면 AttributeSet 포인터가 nullptr이 되는 버그는 어떻게 해결하는가?

기존 블루프린트 액터를 복제(Duplicate)하면 AttributeSet 포인터가 nullptr로 설정되는 언리얼 엔진 버그다. 해결 방법은 헤더에 AttributeSet 포인터를 선언하지 않고 생성자에서 `CreateDefaultSubobject`도 호출하지 않는 것이다. 대신 `PostInitializeComponents()`에서 ASC에 직접 추가한다.

```c++
void AGDPlayerState::PostInitializeComponents()
{
    Super::PostInitializeComponents();

    if (AbilitySystemComponent)
    {
        AbilitySystemComponent->AddSet<UGDAttributeSetBase>();
    }
}
```

이 방식에서는 ASC의 함수를 통해 Attribute 값을 읽고 쓴다.

```c++
// 읽기
float GetNumericAttribute(const FGameplayAttribute &Attribute) const;

// 쓰기 (기존 Modifier는 유지됨)
void SetNumericAttributeBase(const FGameplayAttribute &Attribute, float NewBaseValue);
```

사용 예시:

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

ASC는 AttributeSet 클래스당 최대 하나의 객체만 허용한다.

<a name="troubleshooting-unresolvedexternalsymbolmarkpropertydirty"></a>
### MarkPropertyDirty unresolved external symbol 링커 오류는 왜 발생하며 어떻게 수정하는가?

```
error LNK2019: unresolved external symbol "__declspec(dllimport) void __cdecl UEPushModelPrivate::MarkPropertyDirty(int,int)"
```

`FFastArraySerializer::MarkItemDirty()`를 호출할 때 발생한다. `WITH_PUSH_MODEL` 매크로가 파일마다 서로 다른 값으로 정의되어 링커 불일치가 생기는 것이 원인이다.

해결: 프로젝트 `Build.cs`의 `PublicDependencyModuleNames`에 `NetCore`를 추가한다.

<a name="troubleshooting-enumnamesarenowpathnames"></a>
### UE 5.1 이상에서 Enum 이름 경로명 deprecated 경고가 발생하면 어떻게 코드를 수정해야 하는가?

```
warning C4996: Enum names are now represented by path names. Please use a version of FGameplayAbilityInputBinds constructor that accepts FTopLevelAssetPath.
```

UE 5.1부터 `BindAbilityActivationToInputComponent()`에서 `FString` 기반 생성자가 deprecated됐다. `FTopLevelAssetPath`로 교체해야 한다.

기존 (deprecated):
```c++
AbilitySystemComponent->BindAbilityActivationToInputComponent(InputComponent,
    FGameplayAbilityInputBinds(FString("ConfirmTarget"), FString("CancelTarget"),
        FString("EGDAbilityInputID"),
        static_cast<int32>(EGDAbilityInputID::Confirm),
        static_cast<int32>(EGDAbilityInputID::Cancel)));
```

신규:
```c++
FTopLevelAssetPath AbilityEnumAssetPath =
    FTopLevelAssetPath(FName("/Script/GASDocumentation"), FName("EGDAbilityInputID"));
AbilitySystemComponent->BindAbilityActivationToInputComponent(InputComponent,
    FGameplayAbilityInputBinds(FString("ConfirmTarget"), FString("CancelTarget"),
        AbilityEnumAssetPath,
        static_cast<int32>(EGDAbilityInputID::Confirm),
        static_cast<int32>(EGDAbilityInputID::Cancel)));
```

---
