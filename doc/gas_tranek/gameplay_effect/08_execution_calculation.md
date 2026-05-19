# Execution Calculation

> **GASDoc**: 4.5.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-ec"></a>
#### 4.5.12 Gameplay Effect Execution Calculation

[`GameplayEffectExecutionCalculations`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffectExecutionCalculat-/index.html)(`ExecutionCalculation`, `Execution` — 플러그인 소스 코드에서 이 용어를 자주 볼 수 있다 — 또는 `ExecCalc`)는 `GameplayEffects`가 `ASC`에 변화를 주는 가장 강력한 방법이다. `ModifierMagnitudeCalculations`처럼 `Attributes`를 캡처하고 선택적으로 스냅샷할 수 있다. `MMC`와 달리 이 방식은 하나 이상의 `Attribute`를 변경할 수 있으며, 프로그래머가 원하는 거의 모든 것을 수행할 수 있다. 이러한 강력함과 유연성의 단점은 예측(predicted)이 불가능하고 반드시 C++로 구현해야 한다는 것이다.

`ExecutionCalculations`는 `Instant`와 `Periodic` `GameplayEffects`에서만 사용할 수 있다. 소스 코드에서 'Execute'라는 단어가 포함된 것은 보통 이 두 가지 유형의 `GameplayEffects`를 가리킨다.

스냅샷(Snapshotting)은 `GameplayEffectSpec`이 생성될 때 `Attribute`를 캡처하는 반면, 스냅샷하지 않으면 `GameplayEffectSpec`이 적용될 때 `Attribute`를 캡처한다. `Attributes`를 캡처하면 `ASC`에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산한다. 이 재계산은 `AbilitySet`의 `PreAttributeChange()`를 **실행하지 않으므로**, 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

| Snapshot 여부 | Source/Target | `GameplayEffectSpec` 캡처 시점 |
| ------------- | ------------- | ------------------------------ |
| Yes           | Source        | 생성 시                        |
| Yes           | Target        | 적용 시                        |
| No            | Source        | 적용 시                        |
| No            | Target        | 적용 시                        |

`Attribute` 캡처를 설정하려면, Epic의 ActionRPG Sample Project에서 정립한 패턴을 따른다. `Attributes`를 어떻게 캡처할지 정의하는 구조체를 선언하고, 해당 구조체의 생성자에서 인스턴스를 하나 생성한다. `ExecCalc`마다 이런 구조체가 하나씩 필요하다. **주의:** 각 구조체는 같은 네임스페이스를 공유하기 때문에 반드시 고유한 이름을 가져야 한다. 이름이 충돌하면 `Attributes`를 캡처할 때 잘못된 `Attribute` 값(주로 다른 `Attribute`의 값)을 캡처하는 버그가 발생한다.

`Local Predicted`, `Server Only`, `Server Initiated` `GameplayAbilities`의 경우, `ExecCalc`는 서버에서만 호출된다.

가장 흔한 `ExecCalc` 활용 예는 Source와 Target의 여러 Attribute를 복잡한 공식으로 읽어 받는 데미지를 계산하는 것이다. 샘플 프로젝트에는 `GameplayEffectSpec`의 `SetByCaller`에서 데미지 값을 읽고, Target에서 캡처한 방어구(armor) `Attribute`로 그 값을 경감하는 간단한 `ExecCalc`가 포함되어 있다. `GDDamageExecCalculation.cpp/.h`를 참고하라.

<a name="concepts-ge-ec-senddata"></a>
##### 4.5.12.1 Execution Calculation에 데이터 전달하기

`Attributes`를 캡처하는 것 외에도 `ExecutionCalculation`에 데이터를 전달하는 방법이 몇 가지 있다.

<a name="concepts-ge-ec-senddata-setbycaller"></a>
###### 4.5.12.1.1 SetByCaller

`GameplayEffectSpec`에 설정된 `SetByCallers`는 `ExecutionCalculation`에서 직접 읽을 수 있다.

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
float Damage = FMath::Max<float>(Spec.GetSetByCallerMagnitude(FGameplayTag::RequestGameplayTag(FName("Data.Damage")), false, -1.0f), 0.0f);
```

<a name="concepts-ge-ec-senddata-backingdataattribute"></a>
###### 4.5.12.1.2 Backing Data Attribute Calculation Modifier

`GameplayEffect`에 하드코딩된 값을 전달하고 싶다면, 캡처된 `Attributes` 중 하나를 backing data로 사용하는 `CalculationModifier`를 통해 전달할 수 있다.

아래 스크린샷 예시에서는 캡처된 Damage `Attribute`에 50을 더하고 있다. `Override`로 설정하면 하드코딩된 값만 사용할 수도 있다.

![Backing Data Attribute Calculation Modifier](https://github.com/tranek/GASDocumentation/raw/master/Images/calculationmodifierbackingdataattribute.png)

`ExecutionCalculation`은 `Attribute`를 캡처할 때 이 값을 함께 읽는다.

```c++
float Damage = 0.0f;
// Capture optional damage value set on the damage GE as a CalculationModifier under the ExecutionCalculation
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(DamageStatics().DamageDef, EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-backingdatatempvariable"></a>
###### 4.5.12.1.3 Backing Data Temporary Variable Calculation Modifier

`GameplayEffect`에 하드코딩된 값을 전달하는 또 다른 방법으로, C++에서 `Transient Aggregator`라 불리는 `Temporary Variable`을 `CalculationModifier`의 backing data로 사용할 수 있다. `Temporary Variable`은 `GameplayTag`와 연결된다.

아래 스크린샷 예시에서는 `Data.Damage` `GameplayTag`를 사용해 `Temporary Variable`에 50을 더하고 있다.

![Backing Data Temporary Variable Calculation Modifier](https://github.com/tranek/GASDocumentation/raw/master/Images/calculationmodifierbackingdatatempvariable.png)

`ExecutionCalculation`의 생성자에서 backing `Temporary Variables`를 추가한다:

```c++
ValidTransientAggregatorIdentifiers.AddTag(FGameplayTag::RequestGameplayTag("Data.Damage"));
```

`ExecutionCalculation`은 `Attribute` 캡처 함수와 유사한 전용 캡처 함수로 이 값을 읽는다.

```c++
float Damage = 0.0f;
ExecutionParams.AttemptCalculateTransientAggregatorMagnitude(FGameplayTag::RequestGameplayTag("Data.Damage"), EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-effectcontext"></a>
###### 4.5.12.1.4 Gameplay Effect Context

`GameplayEffectSpec`에 설정된 커스텀 `GameplayEffectContext`를 통해 `ExecutionCalculation`에 데이터를 전달할 수 있다.

`ExecutionCalculation`에서 `FGameplayEffectCustomExecutionParameters`를 통해 `EffectContext`에 접근할 수 있다.

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
FGSGameplayEffectContext* ContextHandle = static_cast<FGSGameplayEffectContext*>(Spec.GetContext().Get());
```

`GameplayEffectSpec` 또는 `EffectContext`의 내용을 변경해야 한다면:

```c++
FGameplayEffectSpec* MutableSpec = ExecutionParams.GetOwningSpecForPreExecuteMod();
FGSGameplayEffectContext* ContextHandle = static_cast<FGSGameplayEffectContext*>(MutableSpec->GetContext().Get());
```

`ExecutionCalculation`에서 `GameplayEffectSpec`을 수정할 때는 주의가 필요하다. `GetOwningSpecForPreExecuteMod()`의 주석을 참고하라.

```c++
/** Non const access. Be careful with this, especially when modifying a spec after attribute capture. */
FGameplayEffectSpec* GetOwningSpecForPreExecuteMod() const;
```

---

### MMC vs ExecCalc — Modifier를 "채우는가" vs "만드는가"

MMC와 ExecCalc의 근본 차이는 GE Blueprint Modifier 항목과의 관계다.

**MMC**: GE Blueprint에 이미 선언된 Modifier 항목 안에 들어간다. **얼마나**만 결정하고, **누구에게·어떤 연산으로**는 GE가 고정한다.

```
GE Blueprint Modifier:
  ├── Target Attribute: Health    ← GE에서 고정
  ├── ModifierOp: Additive        ← GE에서 고정
  └── Magnitude: [MMC 반환값]     ← MMC가 채움
```

**ExecCalc**: Modifier 항목 자체를 코드에서 생성한다. 누구에게·어떤 연산으로·얼마나 전부 자유롭게 결정하고, `AddOutputModifier`를 여러 번 호출해서 여러 Attribute를 동시에 수정할 수 있다.

```cpp
OutExecutionOutput.AddOutputModifier(FGameplayModifierEvaluatedData(
    ULyraHealthSet::GetDamageAttribute(),  // Attribute — 코드에서 결정
    EGameplayModOp::Additive,              // 연산    — 코드에서 결정
    DamageDone));                          // 크기    — 코드에서 결정
```

| | MMC | ExecCalc |
|---|---|---|
| GE Blueprint Modifier 항목 | 반드시 있어야 함 | 없어도 됨 |
| 결정하는 것 | 크기(float) 하나 | Attribute + 연산 + 크기 전부 |
| 수정 Attribute 수 | 항목 하나당 하나 | 한 번에 여러 개 가능 |
| 예측 | 가능 (클라/서버 둘 다 실행) | 불가 (서버만) |
| Target ASC 직접 접근 | X | O (`ExecutionParams`) |

---

### LyraDamageExecution 골격 — 3단계

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

Lyra는 ExecCalc를 두 개(`LyraDamageExecution`, `LyraHealExecution`) 가진다. 골격이 동일하므로 데미지 기준으로 본다.

**1단계 — static 구조체로 캡처 레시피 분리**

```cpp
// LyraDamageExecution.cpp:14
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            true  // bSnapshot: Spec 생성 시점(발사 시점)에 값 고정
        );
    }
};

static FDamageStatics& DamageStatics()
{
    static FDamageStatics Statics;  // 프로세스 전체에서 단 한 번만 생성
    return Statics;
}
```

**2단계 — 생성자에서 캡처 등록**

```cpp
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

GE가 Spec을 생성할 때 이 목록을 보고 해당 Attribute를 미리 캡처한다. 등록이 없으면 `AttemptCalculateCapturedAttributeMagnitude` 호출 시 런타임 에러가 난다.

**3단계 — Execute_Implementation**

전체가 `#if WITH_SERVER_CODE`로 감싸져 있다. 서버에서만 실행되고 클라이언트에서는 빈 함수다.

```cpp
void ULyraDamageExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
#if WITH_SERVER_CODE
    // Context에서 커스텀 데이터 꺼내기
    FLyraGameplayEffectContext* TypedContext =
        FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());

    // 캡처된 BaseDamage 읽기
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    // Context에서 거리·물리 재질 감쇠, 팀 판별
    float DistanceAttenuation = AbilitySource->GetDistanceAttenuation(Distance, ...);
    float PhysMatAttenuation  = AbilitySource->GetPhysicalMaterialAttenuation(PhysMat, ...);
    float TeamMultiplier      = TeamSubsystem->CanCauseDamage(EffectCauser, HitActor) ? 1.0f : 0.0f;

    // 최종 데미지 → Damage Meta Attribute에 출력
    const float DamageDone = FMath::Max(
        BaseDamage * DistanceAttenuation * PhysMatAttenuation * TeamMultiplier, 0.0f);

    OutExecutionOutput.AddOutputModifier(FGameplayModifierEvaluatedData(
        ULyraHealthSet::GetDamageAttribute(), EGameplayModOp::Additive, DamageDone));
#endif
}
```

---

### 캡처 레시피 vs 캡처 값 — Definition과 CaptureSpec

> 소스: `GameplayEffect.h:766`, `GameplayEffect.cpp:3870`, `GameplayEffectAggregator.cpp:579`

`FGameplayEffectAttributeCaptureDefinition`은 **레시피**다 — "Source의 BaseDamage를 Snapshot으로 가져와라"는 방법만 담고, 실제 값은 없다. static 싱글톤으로 만드는 이유는 레시피 자체가 절대 바뀌지 않기 때문이다.

실제 캡처된 값은 Spec마다 독립적으로 저장된다.

```cpp
// GameplayEffect.h:766
struct FGameplayEffectAttributeCaptureSpec
{
    FGameplayEffectAttributeCaptureDefinition BackingDefinition; // 레시피 복사본 (조회 키)
    FAggregatorRef AttributeAggregator;  // 이 Spec에서 실제 캡처된 값 ← Spec마다 다름
};

// FGameplayEffectSpec 안에:
FGameplayEffectAttributeCaptureSpecContainer CapturedRelevantAttributes;
// └── TArray<FGameplayEffectAttributeCaptureSpec>  (Spec마다 독립 인스턴스)
```

`DamageStatics().BaseDamageDef`는 조회 키일 뿐이다. `AttemptCalculateCapturedAttributeMagnitude`가 이 키로 해당 Spec의 `CapturedRelevantAttributes`에서 실제 값을 찾는다. PlayerA와 PlayerB는 같은 레시피를 공유하지만 각자 다른 값을 보관한다.

개념 요약에서 말하는 "구조체 이름 충돌 버그"는 여기서 발생한다. 서로 다른 ExecCalc가 같은 이름의 static 구조체를 쓰면 레시피 키가 겹쳐서 엉뚱한 Spec의 값을 읽는다.

**캡처 대상은 CurrentValue float이 아니라 Aggregator 전체(BaseValue + ModChannels)**다.

```cpp
// GameplayEffect.cpp:3870
void FActiveGameplayEffectsContainer::CaptureAttributeForGameplayEffect(
    OUT FGameplayEffectAttributeCaptureSpec& OutCaptureSpec)
{
    FAggregatorRef& AttributeAggregator = FindOrCreateAttributeAggregator(
        OutCaptureSpec.BackingDefinition.AttributeToCapture);

    if (OutCaptureSpec.BackingDefinition.bSnapshot)
        OutCaptureSpec.AttributeAggregator.TakeSnapshotOf(AttributeAggregator); // 독립 복사
    else
        OutCaptureSpec.AttributeAggregator = AttributeAggregator;               // 원본 참조
}

// GameplayEffectAggregator.cpp:579
void FAggregator::TakeSnapshotOf(const FAggregator& AggToSnapshot)
{
    BaseValue   = AggToSnapshot.BaseValue;   // Additive/Multiplicative Base
    ModChannels = AggToSnapshot.ModChannels; // 채널별 Modifier 목록 전체
}
```

- **bSnapshot=true**: 캡처 시점의 BaseValue + ModChannels를 별도 Aggregator에 복사. 이후 원본이 바뀌어도 캡처값은 불변이다.
- **bSnapshot=false**: 원본 Aggregator 참조만 저장. Execute 시점에 최신 상태가 반영된다.

Aggregator 전체를 캡처하는 이유: `AttemptCalculateCapturedAttributeMagnitude`는 `EvaluateParameters`(SourceTags, TargetTags)를 받아 **태그 조건부 Modifier의 포함 여부를 Execute 시점에 판단**한다. "Status.Burning 태그가 있을 때만 적용되는 +10 Modifier"가 있다면, 미리 CurrentValue로 계산해 버리면 이 조건을 나중에 평가할 수 없다.

```cpp
FAggregatorEvaluateParameters EvaluationParameters;
EvaluationParameters.SourceTags = SourceTags;
EvaluationParameters.TargetTags = TargetTags;

float BaseDamage = 0.0f;
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
    DamageStatics().BaseDamageDef, EvaluationParameters, BaseDamage);
```

---

### Lyra가 ExecCalc를 선택한 이유

**Meta Attribute 패턴** — `Health`를 직접 깎지 않고 `Damage` Meta Attribute에 쓴다. `PostGameplayEffectExecute`가 이를 `Health` 감소로 변환한다. `AddOutputModifier`로 출력 Attribute를 자유롭게 지정할 수 있는 ExecCalc만 이 흐름을 만들 수 있다.

```
ExecCalc → Damage Meta Attribute += DamageDone
         → PostGameplayEffectExecute: Health -= Damage, Damage = 0
```

**서버 권한 보장** — 데미지는 예측하지 않는다. `#if WITH_SERVER_CODE`로 클라이언트 실행을 차단하고, 서버가 계산한 결과를 복제한다. MMC는 클라이언트에서도 실행되므로 서버 전용 시스템(`ULyraTeamSubsystem`) 호출이 위험하다.

**여러 소스의 값 조합** — BaseDamage(Attribute 캡처) × 거리·재질 감쇠·팀 판별(Context) 조합이 필요하다. SetByCaller는 float 하나만 전달하므로 이 구조를 표현할 수 없고, ExecCalc만이 여러 소스의 데이터를 자유롭게 조합할 수 있다.
