# Execution Calculation (ExecCalc)

> 참고: [GAS Doc 캐시](../cache/gas_doc_cache.md) | 소스: `LyraDamageExecution.h/cpp`, `LyraHealExecution.h/cpp`, `LyraGameplayEffectContext.h`

---

## 역할

ExecCalc는 GE(GameplayEffect)에 적용되는 **복잡한 수치 계산 로직**을 C++ 클래스로 캡슐화한다.

- 여러 Attribute를 동시에 읽고 쓸 수 있음
- Source와 Target 양쪽에서 Attribute 캡처 가능
- **서버 전용** (`#if WITH_SERVER_CODE`) — 예측 불가
- GE의 `Executions` 슬롯에 등록

---

## ModifierMagnitudeCalculation(MMC)과의 차이

| | MMC | ExecCalc |
|---|---|---|
| **쓰기 대상** | Modifier 1개 | 여러 Attribute 동시 쓰기 가능 |
| **예측** | 가능 | 불가 (서버 전용) |
| **재계산** | non-snapshot 시 자동 재계산 | 없음 (실행 시점 1회) |
| **용도** | 단순 스케일/보너스 계산 | 데미지/힐 최종 계산, 복잡한 로직 |
| **클래스** | `UGameplayModMagnitudeCalculation` | `UGameplayEffectExecutionCalculation` |

---

## Attribute Capture

ExecCalc는 생성자에서 캡처할 Attribute를 등록한다.

```cpp
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        // CombatSet의 BaseDamage를 Source에서 Snapshot으로 캡처
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,  // Source or Target
            true    // bSnapshot: true=Spec 생성 시점, false=매번 현재값
        );
    }
};

ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

### 캡처 소스

| 소스 | 의미 |
|---|---|
| `Source` | GE를 적용한 쪽(공격자)의 Attribute |
| `Target` | GE를 받는 쪽(피해자)의 Attribute |

### Snapshot 여부

| 옵션 | 의미 |
|---|---|
| `bSnapshot = true` | GESpec 생성 시점의 값 (이후 변화 무시) |
| `bSnapshot = false` | Execute 시점의 현재 값 (Duration GE에서 중요) |

---

## Execute() 구현 패턴

### 전체 구조

```cpp
void ULyraDamageExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
#if WITH_SERVER_CODE    // 서버 전용!
    const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
    
    // 1. Custom Effect Context 추출
    FLyraGameplayEffectContext* TypedContext = 
        FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());
    
    // 2. 태그 수집 (FAggregatorEvaluateParameters용)
    const FGameplayTagContainer* SourceTags = Spec.CapturedSourceTags.GetAggregatedTags();
    const FGameplayTagContainer* TargetTags = Spec.CapturedTargetTags.GetAggregatedTags();
    FAggregatorEvaluateParameters EvaluateParameters;
    EvaluateParameters.SourceTags = SourceTags;
    EvaluateParameters.TargetTags = TargetTags;

    // 3. 캡처된 Attribute 값 읽기
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    // 4. Hit 결과 추출 (있을 때)
    const AActor* EffectCauser = TypedContext->GetEffectCauser();
    const FHitResult* HitActorResult = TypedContext->GetHitResult();
    // ... HitActor, ImpactLocation 등 추출 ...

    // 5. 팀 데미지 필터 (LyraTeamSubsystem)
    float DamageInteractionAllowedMultiplier = 0.0f;
    if (HitActor)
    {
        ULyraTeamSubsystem* TeamSubsystem = HitActor->GetWorld()->GetSubsystem<ULyraTeamSubsystem>();
        DamageInteractionAllowedMultiplier = 
            TeamSubsystem->CanCauseDamage(EffectCauser, HitActor) ? 1.0 : 0.0;
    }

    // 6. 거리 감쇠 + 물리 재질 감쇠
    float PhysicalMaterialAttenuation = 1.0f;
    float DistanceAttenuation = 1.0f;
    if (const ILyraAbilitySourceInterface* AbilitySource = TypedContext->GetAbilitySource())
    {
        if (const UPhysicalMaterial* PhysMat = TypedContext->GetPhysicalMaterial())
        {
            PhysicalMaterialAttenuation = AbilitySource->GetPhysicalMaterialAttenuation(
                PhysMat, SourceTags, TargetTags);
        }
        DistanceAttenuation = AbilitySource->GetDistanceAttenuation(Distance, SourceTags, TargetTags);
    }
    DistanceAttenuation = FMath::Max(DistanceAttenuation, 0.0f);

    // 7. 최종 데미지 계산 및 출력
    const float DamageDone = FMath::Max(
        BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier,
        0.0f);

    if (DamageDone > 0.0f)
    {
        // HealthSet의 Damage Meta Attribute에 가산 (AddOutputModifier)
        OutExecutionOutput.AddOutputModifier(
            FGameplayModifierEvaluatedData(
                ULyraHealthSet::GetDamageAttribute(),
                EGameplayModOp::Additive,
                DamageDone
            )
        );
    }
#endif
}
```

### 데미지 흐름 요약

```
GE(DamageEffect) 적용
    │
    ▼
ULyraDamageExecution::Execute_Implementation()
    │ CombatSet::BaseDamage 캡처
    │ 팀 데미지 체크, 거리 감쇠, 물리 재질 감쇠 적용
    │
    ▼
OutExecutionOutput.AddOutputModifier(HealthSet::Damage, Additive, DamageDone)
    │ Meta Attribute인 Damage에 값 추가
    │
    ▼
ULyraHealthSet::PostGameplayEffectExecute()
    │ Damage 값 소비 → Health 감소
    │ Health <= 0이면 OnOutOfHealth 델리게이트 발행
    │
    ▼
ULyraHealthComponent::HandleOutOfHealth()
    │ StartDeath() 호출
```

---

## FLyraGameplayEffectContext

> 소스: `LyraGameplayEffectContext.h`

GE Context를 확장해 Lyra 전용 데이터를 추가로 담는다.

```cpp
USTRUCT()
struct FLyraGameplayEffectContext : public FGameplayEffectContext
{
    // 탄피 ID (여러 발 동시 발사 시 식별)
    int32 CartridgeID = -1;

    // Ability Source (거리 감쇠, 물리 재질 감쇠 제공 인터페이스)
    TWeakObjectPtr<const UObject> AbilitySourceObject;
};
```

### 주요 기능

```cpp
// Context 추출 (타입 캐스트)
FLyraGameplayEffectContext* TypedContext = 
    FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());

// AbilitySource 설정 (GA::MakeEffectContext()에서 호출)
EffectContext->SetAbilitySource(AbilitySource, SourceLevel);

// 물리 재질 가져오기
const UPhysicalMaterial* PhysMat = TypedContext->GetPhysicalMaterial();

// HitResult 접근
const FHitResult* Hit = TypedContext->GetHitResult();
```

`GetScriptStruct()` 오버라이드 + `WithNetSerializer = true` → 네트워크 직렬화 가능.

---

## 데이터 전달 방법 4가지

ExecCalc에서 외부 데이터를 받는 방법:

| 방법 | 코드 |
|---|---|
| SetByCaller | `Spec.Data->SetByCallerTagMagnitudes.Add(Tag, Value)` |
| Backing Attribute | `ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(...)` |
| Temp Variable | `ExecutionParams.AttemptCalculateCapturedAttributeMagnitudeWithBase(...)` |
| EffectContext | `FLyraGameplayEffectContext* TypedContext = ...ExtractEffectContext(...)` |
