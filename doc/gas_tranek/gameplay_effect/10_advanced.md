# 고급 GE 기능

> **GASDoc**: 4.5.16~18 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-duration"></a>
#### 이미 적용된 GE의 지속시간을 런타임에 변경하려면 어떻게 해야 하는가?

`Spec.Duration`을 변경하고 시간 관련 필드를 업데이트한 뒤, `MarkItemDirty()`와 `CheckDuration()`을 호출한다. 서버에서 실행하면 `FActiveGameplayEffect`가 dirty로 마킹되어 클라이언트에 복제된다.

```c++
bool UPAAbilitySystemComponent::SetGameplayEffectDurationHandle(FActiveGameplayEffectHandle Handle, float NewDuration)
{
    const FActiveGameplayEffect* ActiveGameplayEffect = GetActiveGameplayEffect(Handle);
    if (!ActiveGameplayEffect) return false;

    FActiveGameplayEffect* AGE = const_cast<FActiveGameplayEffect*>(ActiveGameplayEffect);
    AGE->Spec.Duration = (NewDuration > 0) ? NewDuration : 0.01f;
    AGE->StartServerWorldTime = ActiveGameplayEffects.GetServerWorldTime();
    AGE->CachedStartServerWorldTime = AGE->StartServerWorldTime;
    AGE->StartWorldTime = ActiveGameplayEffects.GetWorldTime();
    ActiveGameplayEffects.MarkItemDirty(*AGE);
    ActiveGameplayEffects.CheckDuration(Handle);

    AGE->EventSet.OnTimeChanged.Broadcast(AGE->Handle, AGE->StartWorldTime, AGE->GetDuration());
    OnGameplayEffectDurationChange(*AGE);
    return true;
}
```

> **주의**: `const_cast`를 사용하며 Epic이 의도한 방법이 아닐 수 있다.

<a name="concepts-ge-dynamic"></a>
#### 런타임에 GE를 동적으로 생성할 수 있는 경우와 없는 경우, 그리고 올바른 대안은 무엇인가?

C++에서 런타임에 처음부터 생성할 수 있는 것은 **`Instant` GE뿐**이다. `Duration`과 `Infinite` GE는 복제 시 존재하지 않는 GE 클래스 정의를 찾기 때문에 런타임 동적 생성이 불가능하다.

`Duration`/`Infinite` GE가 필요하다면: 에디터에서 원형(archetype) GE 클래스를 만들고, 런타임에 `GameplayEffectSpec` 인스턴스를 커스터마이징하는 방식을 사용해야 한다.

##### 런타임 동적 Instant GE 생성의 실제 예시는 어떻게 되는가?

최후의 일격 시 킬러에게 골드와 경험치를 전달하는 예시:

```c++
UGameplayEffect* GEBounty = NewObject<UGameplayEffect>(GetTransientPackage(), FName(TEXT("Bounty")));
GEBounty->DurationPolicy = EGameplayEffectDurationType::Instant;

int32 Idx = GEBounty->Modifiers.Num();
GEBounty->Modifiers.SetNum(Idx + 2);

FGameplayModifierInfo& InfoXP = GEBounty->Modifiers[Idx];
InfoXP.ModifierMagnitude = FScalableFloat(GetXPBounty());
InfoXP.ModifierOp = EGameplayModOp::Additive;
InfoXP.Attribute = UGDAttributeSetBase::GetXPAttribute();

FGameplayModifierInfo& InfoGold = GEBounty->Modifiers[Idx + 1];
InfoGold.ModifierMagnitude = FScalableFloat(GetGoldBounty());
InfoGold.ModifierOp = EGameplayModOp::Additive;
InfoGold.Attribute = UGDAttributeSetBase::GetGoldAttribute();

Source->ApplyGameplayEffectToSelf(GEBounty, 1.0f, Source->MakeEffectContext());
```

로컬 예측 GA 내부에서 사용할 때는 CDO에서 Spec을 생성하지 않도록 GESpec을 직접 생성해야 한다:

```c++
// CDO 기반 Spec 생성을 우회 — 동적 GE이므로 직접 생성
FGameplayEffectSpec* GESpec = new FGameplayEffectSpec(GameplayEffect, {}, 0.f);
ApplyGameplayEffectSpecToOwner(Handle, ActorInfo, ActivationInfo, FGameplayEffectSpecHandle(GESpec));
```

> 사이드 이펙트 가능성이 있으니 주의할 것.

<a name="concepts-ge-containers"></a>
#### GameplayEffectContainer는 무엇이며, GE와 TargetData를 함께 관리할 때 어떤 이점이 있는가?

`FGameplayEffectContainer`는 Epic의 Action RPG Sample Project에서 구현된 구조체로, 기본 GAS에는 포함되지 않는다. GE와 TargetData를 함께 담고, GESpec 생성 및 EffectContext 기본값 설정 등을 자동화해준다.

GA에서 GameplayEffectContainer를 만들어 발사체에 전달하는 패턴에 매우 유용하다. 내부 GESpec에 접근해 SetByCaller 값을 추가하려면, 컨테이너를 분해(break)하고 GESpec 배열에서 인덱스로 접근한다.

자신의 프로젝트에 추가하는 것을 권장한다.
