# GAS — GameplayEffect

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 4. GE → Attribute 수정 메커니즘

### 4개 ModifierOp (EGameplayModOp)
- `Additive`: += Magnitude
- `Multiplicitive` (오탈자 주의): *= Magnitude
- `Division`: /= Magnitude
- `Override`: = Magnitude (Aggregator 있어도 마지막 Override 값으로 덮어씀)

### Instant GE → BaseValue 영구 변경
흐름: `InternalExecuteMod → ApplyModToAttribute → SetAttributeBaseValue`
`StaticExecModOnBaseValue(BaseValue, ModOp, Magnitude)` 로 직접 연산

### Duration/Infinite GE → Aggregator에 Modifier 등록 (임시)
흐름: Aggregator에 Modifier 추가 → `BroadcastOnDirty` → `Evaluate()` → `SetCurrentValue(NewValue)`
계산식: `((BaseValue + Additive) * Multiplicitive / Division)` + Override 처리

### BaseValue 변경 → CurrentValue 동기화 콜체인
- **Aggregator 없을 때**: `SetBaseValue → InternalUpdateNumericalAttribute → SetNumericAttribute_Internal → SetNumericValueChecked → DataPtr->SetCurrentValue(NewBaseValue)`
- **Aggregator 있을 때**: `SetBaseValue → Aggregator->SetBaseValue → BroadcastOnDirty → OnDirty델리게이트 → ASC::OnAttributeAggregatorDirty → Aggregator->Evaluate → InternalUpdateNumericalAttribute → ... → SetCurrentValue(재계산값)`

Aggregator는 이 Attribute에 처음 Duration/Infinite GE 적용 시 생성됨.

### AttributeBased GE Modifier
`FAttributeBasedFloat` 구조: BackingAttribute, Coefficient, PreAdd, PostAdd
수식: `Coefficient * (PreAdd + BackingAttributeValue) + PostAdd`
Duration/Infinite GE면 BackingAttribute Aggregator dirty 시 자동 재계산.
`EAttributeBasedFloatCalculationType`: AttributeMagnitude(CurrentValue) / AttributeBaseValue / AttributeBonusMagnitude

---

## 6. 데미지 실행 흐름 (LyraDamageExecution)

**출처**: `Source/LyraGame/AbilitySystem/Executions/LyraDamageExecution.cpp`

```
[공격자 ASC: CombatSet::BaseDamage]
  └─ FDamageStatics: GetBaseDamageAttribute() Capture (Source, bSnapshot=true)

Execute_Implementation():
  TypedContext = FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext())
  HitActorResult = TypedContext->GetHitResult()   ← TargetData에서 흘러온 FHitResult
  HitActor       = CurHitResult.HitObjectHandle.FetchActor()
  ImpactLocation = CurHitResult.ImpactPoint
  (HitResult 없으면 TargetASC->GetAvatarActor() 위치로 폴백)

  CanCauseDamage(EffectCauser, HitActor) → DamageInteractionAllowedMultiplier (팀킬 방지)
  Distance = Dist(TypedContext->GetOrigin(), ImpactLocation)
  AbilitySource->GetDistanceAttenuation(Distance) → DistanceAttenuation
  TypedContext->GetPhysicalMaterial()              ← HitResult 내부 PhysicalMaterial
  AbilitySource->GetPhysicalMaterialAttenuation(PhysMat) → PhysicalMaterialAttenuation
  DamageDone = BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier
  AddOutputModifier(GetDamageAttribute(), Additive, DamageDone)
  → [피격자 ASC: HealthSet::Damage(Meta)]
```
`#if WITH_SERVER_CODE` 가드로 서버 전용.
힐(`LyraHealExecution`)은 동일 패턴, `BaseHeal → Healing(Meta)`.

**TargetData 연결**: HitResult(피격 위치·재질)가 TargetData → Context → ExecCalc 순서로 흘러야 거리 감쇠와 재질 감쇠가 동작한다. TargetData 없이 GE를 직접 적용하면 두 감쇠 모두 폴백값(거리 WORLD_MAX, 재질 없음)으로 처리된다.

---

## 22. GE를 통해서만 Attribute를 수정해야 하는 이유 — PredictionKey와 롤백

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayPrediction.h:64-208`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayEffect.h:1410`

### 예측(Prediction) — 클라이언트 선행 실행

서버 응답 대기 없이 클라이언트가 먼저 결과를 적용하고, 이후 서버와 맞추는 방식.

```
클라이언트: GA 발동 → GE로 Attribute 즉시 변경 + 서버에 RPC
서버: 수신 → 유효하면 동일 GE 적용, 아니면 거부
클라이언트: 확인 수신 → 일치하면 유지, 거부면 롤백
```

### FPredictionKey — 예측 추적 단위

클라이언트가 예측 행동마다 발급하는 고유 ID.
GE 적용 시 함께 담긴다.

```cpp
FActiveGameplayEffect {
    FGameplayEffectSpec Spec;
    FPredictionKey PredictionKey;  // GameplayEffect.h:1410
}
```

- 서버 복제본이 도착할 때 PredictionKey 대조
- **일치**: 예측 확인 → 클라이언트 GE 유지
- **거부**: `NewRejectedDelegate` 발동 → 해당 키의 GE 전부 롤백

### 직접 수정이 예측 불가능한 이유

```cpp
AttributeSet->Stamina = AttributeSet->Stamina - 10;  // PredictionKey 없음
// → 거부 시 롤백 대상을 식별할 수 없음
```

GE를 거쳐야 변경이 PredictionKey에 묶여 추적·롤백 가능.
직접 수정은 메모리 덮어쓰기라 엔진이 추적할 방법이 없다.

---

## 32. Ongoing Tag Requirements — GE 억제(Inhibit) 메커니즘

> 소스 경로 (UE 5.7):
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayEffectComponents/TargetTagRequirementsGameplayEffectComponent.cpp`
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent.cpp` (line 283~333)
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayEffect.cpp` (line 4491~4508, 4664~, 3561~)

### 핵심 플래그: `FActiveGameplayEffect::bIsInhibited`

```
bIsInhibited = false  →  GE 활성 (Modifier + Tag 적용 중)
bIsInhibited = true   →  GE 억제 (Modifier + Tag 제거. FActiveGameplayEffect는 컨테이너에 잔류)
```

### UE 5.3+ 구조 변경

UE 5.3부터 `OngoingTagRequirements`는 `UTargetTagRequirementsGameplayEffectComponent`가 처리.
`FActiveGameplayEffect::CheckOngoingTagRequirements`는 현재 빈 함수.

**GE 추가 시** (`OnActiveGameplayEffectAdded`):
- `OngoingTagRequirements`의 모든 태그에 `RegisterGameplayTagEvent` 구독
- 초기 활성 여부 = `OngoingTagRequirements.RequirementsMet(TagContainer)`

**태그 변경 시** (`OnTagChanged`):
- `RemovalTagRequirements` 충족 → `RemoveActiveGameplayEffect` (영구 제거)
- `OngoingTagRequirements` 불충족 → `SetActiveGameplayEffectInhibit(..., true)` (억제)
- `OngoingTagRequirements` 재충족 → `SetActiveGameplayEffectInhibit(..., false)` (재활성)

**GE 제거 시** (`OnGameplayEffectRemoved`): 모든 태그 이벤트 구독 해제.

### `SetActiveGameplayEffectInhibit` 동작

```cpp
if (ActiveGE->bIsInhibited != bInhibit)  // 상태 변화 시에만 처리
{
    if (bInhibit)
        RemoveActiveGameplayEffectGrantedTagsAndModifiers(...)  // Modifier 제거 + Tag 해제 + GameplayCue Remove
    else
        AddActiveGameplayEffectGrantedTagsAndModifiers(...)     // Modifier 재등록 + Tag 재적용 + GameplayCue Add

    EventSet.OnInhibitionChanged.Broadcast(Handle, bIsInhibited);
}
```

### `bIsInhibited` 영향 범위

| 코드 | 동작 |
|---|---|
| `InternalExecutePeriodicGameplayEffect` | 억제 중이면 틱 실행 안 함 |
| `UpdateAllAggregatorModMagnitudes` | 억제 중이면 Modifier 재계산 건너뜀 |
| `InternalOnActiveGameplayEffectRemoved` | 억제 중인 GE 제거 시 Tag/Modifier 정리 불필요 |
| `GetActiveEffectCount(bEnforceOnGoingCheck=true)` | 억제 중인 GE를 카운트에서 제외 |

### 초기화 트릭 (GameplayEffect.cpp:4501)

```cpp
Effect.bIsInhibited = true;  // 강제로 억제 상태로 시작
Owner->SetActiveGameplayEffectInhibit(Handle, !bActive, bInvokeGameplayCueEvents);
// bActive=true → !bActive=false → 억제 해제(켜기) 경로 실행
// → 모든 초기 추가가 동일한 코드 경로를 타도록 보장
```

---

## 33. UGameplayEffect 함수 구조 및 CDO 호출 패턴

> 소스: `Engine/.../GameplayAbilities/Public/GameplayEffect.h:2096`, `Private/GameplayEffect.cpp:937~991`

### 함수 분류

| 종류 | 예시 |
|---|---|
| UObject 라이프사이클 | `PostLoad`, `PostCDOCompiled`, `PreSave` |
| GAS 프레임워크 훅 | `CanApply`, `OnAddedToActiveContainer`, `OnExecuted`, `OnApplied` |
| 읽기 전용 Accessor | `GetGrantedTags`, `GetAssetTags`, `FindComponent<T>` |
| Deprecated 변환 헬퍼 (private) | `ConvertTagRequirementsComponent` 등 (UE 5.3 마이그레이션용) |

### GAS 프레임워크 훅은 GEComponents 위임만 함

```cpp
bool UGameplayEffect::CanApply(...) const
{
    for (const UGameplayEffectComponent* GEComponent : GEComponents)
        if (!GEComponent->CanGameplayEffectApply(...)) return false;
    return true;
}
// OnAddedToActiveContainer, OnExecuted, OnApplied 모두 동일한 패턴
```

### CDO 직접 호출 구조

`FGameplayEffectSpec::Def`가 항상 CDO를 가리킴. 프레임워크가 CDO 메서드를 직접 호출:

```
Spec.Def->CanApply(...)
Spec.Def->OnAddedToActiveContainer(...)
Spec.Def->OnExecuted(...)   // GameplayEffect.cpp:3308
Spec.Def->OnApplied(...)
```

"GE에 로직을 넣지 말라" = `UGameplayEffect` 서브클래싱해서 훅을 오버라이드하지 말라는 의미.
실제 로직은 `GEComponents` 안의 `UGameplayEffectComponent` 서브클래스에 넣는다.

---

## FGameplayEffectContext::SourceObject 복제 조건

> 소스: `GameplayAbilities/Public/GameplayEffectTypes.h:339,467`, `Private/GameplayEffectTypes.cpp:269~325`

`SourceObject`는 `NetSerialize`에 포함되어 있으나, `bReplicateSourceObject` 플래그가 `true`일 때만 실제로 직렬화된다.

```cpp
// 저장 시 (서버)
if (bReplicateSourceObject && SourceObject.IsValid())
    RepBits |= 1 << 3;

if (RepBits & (1 << 3))
    Ar << SourceObject;
```

`bReplicateSourceObject` 기본값은 `false`. `AddSourceObject()`를 통해서만 `true`로 설정된다:

```cpp
virtual void AddSourceObject(const UObject* NewSourceObject)
{
    SourceObject = MakeWeakObjectPtr(const_cast<UObject*>(NewSourceObject));
    bReplicateSourceObject = NewSourceObject && NewSourceObject->IsSupportedForNetworking();
}
```

| 상황 | 복제 여부 |
|---|---|
| `AddSourceObject(네트워크 지원 오브젝트)` | O |
| `AddSourceObject(네트워크 미지원 오브젝트)` | X — `IsSupportedForNetworking()` 실패 |
| `SourceObject = ...` 직접 할당 | X — `bReplicateSourceObject` false 그대로 |

`TWeakObjectPtr` 타입은 복제 여부와 무관. 복제는 `bReplicateSourceObject` 플래그가 결정한다.

---

## 커스텀 FGameplayEffectContext 서브클래스에서 필드 복제하기

> 소스: `Source/LyraGame/AbilitySystem/LyraGameplayEffectContext.h/.cpp`

### 복제하려면 NetSerialize 오버라이드 필수

```cpp
bool FLyraGameplayEffectContext::NetSerialize(FArchive& Ar, class UPackageMap* Map, bool& bOutSuccess)
{
    FGameplayEffectContext::NetSerialize(Ar, Map, bOutSuccess);  // 부모 필드 먼저
    // 추가 필드를 여기서 Ar << 로 직렬화
    return true;
}
```

### NetSerialize 외에 반드시 함께 구현해야 할 것들

```cpp
// 1. GAS 타입 식별
virtual UScriptStruct* GetScriptStruct() const override
{ return FLyraGameplayEffectContext::StaticStruct(); }

// 2. 복사 시 커스텀 필드 포함
virtual FGameplayEffectContext* Duplicate() const override { ... }

// 3. TStructOpsTypeTraits 특수화
template<>
struct TStructOpsTypeTraits<FLyraGameplayEffectContext>
    : public TStructOpsTypeTraitsBase2<FLyraGameplayEffectContext>
{
    enum { WithNetSerializer = true, WithCopy = true };
};
```

### Lyra의 실제 선택 — 추가 필드 둘 다 복제 안 함

- `CartridgeID (int32)`: "Not serialized for post-activation use" — 발사 시점에만 의미 있어 이후 불필요
- `AbilitySourceObject (TWeakObjectPtr)`: "NOT replicated currently" — 서버 전용으로만 사용

### Iris 복제 주의사항

`NetSerialize()`에 실제로 추가 필드를 넣으면 Iris용 커스텀 NetSerializer도 별도 구현해야 한다.
Lyra가 두 필드를 복제하지 않는 이유 중 하나가 이 Iris 부담을 피하기 위한 것으로 보인다.

```cpp
// NetSerialize를 기본 그대로 두면 이 포워딩 매크로로 Iris 지원 가능
UE_NET_IMPLEMENT_FORWARDING_NETSERIALIZER_AND_REGISTRY_DELEGATES(LyraGameplayEffectContext, FGameplayEffectContextNetSerializer);
// NetSerialize를 수정하면 위 매크로 대신 커스텀 Iris NetSerializer 직접 구현 필요
```
