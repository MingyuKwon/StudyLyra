# GESpec & SetByCaller

> 참고: [GAS Doc 캐시](../gas_doc_cache.md) | 소스: `LyraGameplayAbility.cpp`, `LyraGameplayEffectContext.h`

---

## FGameplayEffectSpec

GE 클래스(CDO)를 기반으로 만든 **실제 적용 가능한 인스턴스 데이터**다.

```
UGameplayEffect (CDO)
    → FGameplayEffectSpec (런타임 인스턴스)
        → FGameplayEffectSpecHandle (스마트 포인터 래퍼)
```

### 생성

```cpp
// GA에서 GESpec 생성
FGameplayEffectSpecHandle SpecHandle = MakeOutgoingSpec(
    GameplayEffectClass,   // GE 클래스
    Level,                 // 레벨 (커브 테이블 인덱스)
    MakeEffectContext()    // EffectContext (Instigator, HitResult 등 포함)
);
FGameplayEffectSpec* Spec = SpecHandle.Data.Get();
```

### 적용

```cpp
// 자신에게 적용
ASC->ApplyGameplayEffectSpecToSelf(*Spec);

// 타겟에게 적용
TargetASC->ApplyGameplayEffectSpecToTarget(*Spec, TargetASC);

// ASC 없이 적용 (내부에서 타겟 ASC 찾음)
UAbilitySystemBlueprintLibrary::ApplyGameplayEffectSpecToTarget(Handle, TargetActor);
```

---

## SetByCaller

GESpec 생성 후 런타임에 Magnitude 값을 주입하는 방법.

### Tag 기반 (권장)

```cpp
// Spec에 Tag → Value 쌍 추가
Spec->SetByCallerTagMagnitudes.Add(DamageTag, DamageValue);

// GE 에디터에서: Modifier의 Magnitude Type = Set By Caller, Tag = DamageTag
```

### Name 기반

```cpp
Spec->SetByCallerNameMagnitudes.Add(FName("Damage"), DamageValue);
```

### 쿨다운에 SetByCaller 적용

```cpp
// GA에서 쿨다운 시간을 런타임에 설정
FGameplayEffectSpecHandle CooldownSpec = MakeOutgoingSpec(CooldownGE, 1.0f, MakeEffectContext());
CooldownSpec.Data->SetByCallerTagMagnitudes.Add(
    LyraGameplayTags::SetByCaller_Duration, 
    CooldownDuration
);
ApplyGameplayEffectSpecToOwner(CooldownSpec);
```

---

## FGameplayEffectContext — Lyra 확장

GESpec에는 Context가 포함되어 있어 추가 데이터를 전달할 수 있다.

### 기본 Context 데이터

```cpp
struct FGameplayEffectContext
{
    TWeakObjectPtr<AActor> Instigator;    // 원인이 된 Actor (PlayerState 등)
    TWeakObjectPtr<AActor> EffectCauser; // 실제 피해를 준 Actor (Character)
    TWeakObjectPtr<UObject> SourceObject; // GA의 SourceObject (장비 등)
    TSharedPtr<FHitResult> HitResult;     // 히트 결과 (충격 위치, 노멀 등)
};
```

### FLyraGameplayEffectContext — Lyra 전용 확장

```cpp
USTRUCT()
struct FLyraGameplayEffectContext : public FGameplayEffectContext
{
    int32 CartridgeID = -1;                      // 총기 탄피 ID (여러 발 동시 식별)
    TWeakObjectPtr<const UObject> AbilitySourceObject;  // ILyraAbilitySourceInterface 구현체
};
```

### 설정 방법 — MakeEffectContext 오버라이드

```cpp
// LyraGameplayAbility::MakeEffectContext()에서
FGameplayEffectContextHandle ULyraGameplayAbility::MakeEffectContext(...) const
{
    FGameplayEffectContextHandle ContextHandle = Super::MakeEffectContext(Handle, ActorInfo);
    FLyraGameplayEffectContext* EffectContext = FLyraGameplayEffectContext::ExtractEffectContext(ContextHandle);
    
    EffectContext->SetAbilitySource(AbilitySource, SourceLevel);
    EffectContext->AddInstigator(Instigator, EffectCauser);
    EffectContext->AddSourceObject(SourceObject);
    
    return ContextHandle;
}
```

### 읽는 방법 — ExecCalc에서

```cpp
// LyraDamageExecution::Execute_Implementation()에서
FLyraGameplayEffectContext* TypedContext = 
    FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());

const AActor* EffectCauser = TypedContext->GetEffectCauser();
const FHitResult* HitResult = TypedContext->GetHitResult();
const ILyraAbilitySourceInterface* AbilitySource = TypedContext->GetAbilitySource();
```

---

## Projectile 패턴 (GESpec 전달)

발사체에 GESpec을 실어 보내는 패턴:

```cpp
// GA에서 발사체 스폰 시 GESpec 전달
AMyProjectile* Projectile = SpawnProjectile(...);
Projectile->DamageEffectSpecHandle = MakeOutgoingSpec(DamageGE, Level, MakeEffectContext());
Projectile->DamageEffectSpecHandle.Data->SetByCallerTagMagnitudes.Add(DamageTag, DamageValue);

// 발사체 충돌 시
void AMyProjectile::OnHit(AActor* HitActor)
{
    if (UAbilitySystemComponent* TargetASC = GetASCFromActor(HitActor))
    {
        // FHitResult를 Context에 추가
        DamageEffectSpecHandle.Data->GetContext().AddHitResult(HitResult);
        TargetASC->ApplyGameplayEffectSpecToSelf(*DamageEffectSpecHandle.Data.Get());
    }
}
```

이 패턴을 Lyra는 `ULyraGameplayAbility_RangedWeapon`에서 사용한다.

---

## 동적 GE 런타임 생성

**Instant GE만** 런타임에 `NewObject`로 생성 가능.

```cpp
UGameplayEffect* GELifesteal = NewObject<UGameplayEffect>(GetTransientPackage(), TEXT("Lifesteal"));
GELifesteal->DurationPolicy = EGameplayEffectDurationType::Instant;

// Modifier 추가
FGameplayModifierInfo ModInfo;
ModInfo.Attribute = UMyAttributeSet::GetHealthAttribute();
ModInfo.ModifierOp = EGameplayModOp::Additive;
ModInfo.ModifierMagnitude = FScalableFloat(LifestealAmount);
GELifesteal->Modifiers.Add(ModInfo);

SourceASC->ApplyGameplayEffectToSelf(GELifesteal, 1.0f, SourceASC->MakeEffectContext());
```

Duration/Infinite는 CDO 기반이라 런타임 생성 불안정 → 사용 금지.
