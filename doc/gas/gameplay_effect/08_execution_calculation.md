# Execution Calculation

> **GASDoc**: 4.5.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-ec"></a>
#### 4.5.12 Gameplay Effect Execution Calculation

[`GameplayEffectExecutionCalculations`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffectExecutionCalculat-/index.html)(`ExecutionCalculation`, `Execution` — 플러그인 소스 코드에서 이 용어를 자주 볼 수 있다 — 또는 `ExecCalc`)는 `GameplayEffects`가 `ASC`에 변화를 주는 가장 강력한 방법이다. [`ModifierMagnitudeCalculations`](#concepts-ge-mmc)처럼 `Attributes`를 캡처하고 선택적으로 스냅샷할 수 있다. `MMC`와 달리 이 방식은 하나 이상의 `Attribute`를 변경할 수 있으며, 프로그래머가 원하는 거의 모든 것을 수행할 수 있다. 이러한 강력함과 유연성의 단점은 [예측(predicted)](#concepts-p)이 불가능하고 반드시 C++로 구현해야 한다는 것이다.

`ExecutionCalculations`는 `Instant`와 `Periodic` `GameplayEffects`에서만 사용할 수 있다. 소스 코드에서 'Execute'라는 단어가 포함된 것은 보통 이 두 가지 유형의 `GameplayEffects`를 가리킨다.

스냅샷(Snapshotting)은 `GameplayEffectSpec`이 생성될 때 `Attribute`를 캡처하는 반면, 스냅샷하지 않으면 `GameplayEffectSpec`이 적용될 때 `Attribute`를 캡처한다. `Attributes`를 캡처하면 `ASC`에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산한다. 이 재계산은 `AbilitySet`의 [`PreAttributeChange()`](#concepts-as-preattributechange)를 **실행하지 않으므로**, 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

| Snapshot 여부 | Source/Target | `GameplayEffectSpec` 캡처 시점 |
| ------------- | ------------- | ------------------------------ |
| Yes           | Source        | 생성 시                        |
| Yes           | Target        | 적용 시                        |
| No            | Source        | 적용 시                        |
| No            | Target        | 적용 시                        |

`Attribute` 캡처를 설정하려면, Epic의 ActionRPG Sample Project에서 정립한 패턴을 따른다. `Attributes`를 어떻게 캡처할지 정의하는 구조체를 선언하고, 해당 구조체의 생성자에서 인스턴스를 하나 생성한다. `ExecCalc`마다 이런 구조체가 하나씩 필요하다. **주의:** 각 구조체는 같은 네임스페이스를 공유하기 때문에 반드시 고유한 이름을 가져야 한다. 이름이 충돌하면 `Attributes`를 캡처할 때 잘못된 `Attribute` 값(주로 다른 `Attribute`의 값)을 캡처하는 버그가 발생한다.

`Local Predicted`, `Server Only`, `Server Initiated` [`GameplayAbilities`](#concepts-ga)의 경우, `ExecCalc`는 서버에서만 호출된다.

가장 흔한 `ExecCalc` 활용 예는 Source와 Target의 여러 Attribute를 복잡한 공식으로 읽어 받는 데미지를 계산하는 것이다. 샘플 프로젝트에는 `GameplayEffectSpec`의 [`SetByCaller`](#concepts-ge-spec-setbycaller)에서 데미지 값을 읽고, Target에서 캡처한 방어구(armor) `Attribute`로 그 값을 경감하는 간단한 `ExecCalc`가 포함되어 있다. `GDDamageExecCalculation.cpp/.h`를 참고하라.

<a name="concepts-ge-ec-senddata"></a>
##### 4.5.12.1 Execution Calculation에 데이터 전달하기

`Attributes`를 캡처하는 것 외에도 `ExecutionCalculation`에 데이터를 전달하는 방법이 몇 가지 있다.

<a name="concepts-ge-ec-senddata-setbycaller"></a>
###### 4.5.12.1.1 SetByCaller

`GameplayEffectSpec`에 설정된 [`SetByCallers`](#concepts-ge-spec-setbycaller)는 `ExecutionCalculation`에서 직접 읽을 수 있다.

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

`GameplayEffectSpec`에 설정된 커스텀 [`GameplayEffectContext`](#concepts-ge-context)를 통해 `ExecutionCalculation`에 데이터를 전달할 수 있다.

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

## 내 분석

### Lyra ExecCalc 구조 — LyraDamageExecution / LyraHealExecution

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

Lyra는 ExecCalc를 두 개 가지고 있다. 둘의 골격이 동일하므로 데미지 기준으로 전체 구조를 본다.

#### 1단계 — Attribute 캡처 정의를 static 구조체로 분리

```cpp
// LyraDamageExecution.cpp:14
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,  // 공격자(Source)의 Attribute
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

개념 요약에서 말하는 "Epic의 ActionRPG 패턴"이 이것이다. 구조체 이름이 충돌하면 다른 Attribute 값을 잘못 읽는 버그가 생기므로, Lyra는 `FDamageStatics` / `FHealStatics`로 명확히 구분한다.

#### 2단계 — 생성자에서 캡처 등록

```cpp
// LyraDamageExecution.cpp:31
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

이 등록이 없으면 `AttemptCalculateCapturedAttributeMagnitude` 호출 시 런타임 에러가 난다. GE가 Spec을 만들 때 `RelevantAttributesToCapture` 목록을 보고 해당 Attribute들을 미리 캡처하기 때문이다.

#### 3단계 — Execute_Implementation

전체 계산이 `#if WITH_SERVER_CODE`로 감싸져 있다. 서버에서만 실행되고 클라이언트에서는 빈 함수다.

```cpp
// LyraDamageExecution.cpp:36
void ULyraDamageExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
#if WITH_SERVER_CODE
    const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();

    // 1. Context에서 커스텀 데이터 꺼내기
    FLyraGameplayEffectContext* TypedContext =
        FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());

    // 2. Attribute 캡처값 읽기
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    // 3. 거리 감쇠, 물리 재질 감쇠 계산 (AbilitySource 인터페이스 통해)
    float DistanceAttenuation    = AbilitySource->GetDistanceAttenuation(Distance, ...);
    float PhysMatAttenuation     = AbilitySource->GetPhysicalMaterialAttenuation(PhysMat, ...);

    // 4. 팀 판별 — 아군이면 0, 적이면 1
    float DamageInteractionAllowedMultiplier =
        TeamSubsystem->CanCauseDamage(EffectCauser, HitActor) ? 1.0 : 0.0;

    // 5. 최종 데미지 계산 및 출력
    const float DamageDone = FMath::Max(
        BaseDamage * DistanceAttenuation * PhysMatAttenuation * DamageInteractionAllowedMultiplier, 0.0f);

    OutExecutionOutput.AddOutputModifier(
        FGameplayModifierEvaluatedData(
            ULyraHealthSet::GetDamageAttribute(),
            EGameplayModOp::Additive,
            DamageDone));
#endif
}
```

---

### 데이터 전달 경로 — Lyra가 사용하는 방식

개념 요약에서 나열한 4가지 데이터 전달 방법 중 Lyra는 **Attribute 캡처**와 **Context** 두 가지를 쓴다.

**Attribute 캡처**: `CombatSet.BaseDamage`(Source)를 캡처해서 데미지 기준값으로 사용한다.

```cpp
// 공격자(Source)의 BaseDamage Attribute를 Spec 생성 시점에 스냅샷
BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
    ULyraCombatSet::GetBaseDamageAttribute(),
    EGameplayEffectAttributeCaptureSource::Source,
    true  // bSnapshot
);
```

**Context**: `FLyraGameplayEffectContext`에서 HitResult, 거리, 물리 재질, AbilitySource를 꺼낸다. SetByCaller를 쓰지 않는 이유는 이 데이터들이 float 하나로 표현되지 않기 때문이다.

```cpp
const AActor*    EffectCauser  = TypedContext->GetEffectCauser();
const FHitResult* HitResult    = TypedContext->GetHitResult();
const ILyraAbilitySourceInterface* AbilitySource = TypedContext->GetAbilitySource();
```

---

### Lyra가 ExecCalc를 선호하는 이유

Lyra의 GE 적용 방식을 보면 데미지와 힐링 모두 단순히 값을 넣는 게 아니라, 계산 과정에 여러 외부 요소가 개입한다.

**1. 서버 권한 보장**

데미지 계산은 예측하지 않는다. 클라이언트가 "내가 50 데미지를 입혔다"고 선언하는 게 아니라, 서버가 직접 계산해서 결과를 복제한다. `#if WITH_SERVER_CODE`가 그 의도를 코드로 표현한다.

**2. Meta Attribute 패턴과의 연계**

Lyra의 데미지 파이프라인은 `Health`를 직접 깎지 않는다. 대신 `Damage` Meta Attribute에 값을 쓰고, `PostGameplayEffectExecute`에서 이를 `Health` 감소로 변환한다.

```
ExecCalc → Damage Meta Attribute에 AddOutputModifier
         → PostGameplayEffectExecute: Health -= Damage
         → Damage를 0으로 리셋
```

이 패턴은 ExecCalc의 `AddOutputModifier`가 있어야 가능하다. MMC는 float 하나를 Modifier 크기로만 반환하므로 이 흐름을 만들 수 없다.

**3. 여러 입력값의 곱셈 조합**

```
최종 데미지 = BaseDamage × DistanceAttenuation × PhysMatAttenuation × TeamMultiplier
```

이 계산에서 거리·물리 재질·팀은 Context에서, BaseDamage는 Attribute 캡처에서 온다. 서로 다른 소스에서 온 값들을 조합해서 최종 값 하나를 만드는 구조 자체가 ExecCalc를 요구한다.

---

### MMC vs ExecCalc — Modifier를 "채우는가" vs "만드는가"

MMC와 ExecCalc의 근본적인 차이는 GE Blueprint의 Modifier 항목과의 관계에 있다.

**MMC**: GE Blueprint에 이미 선언된 Modifier 항목 안에 들어간다.

```
GE Blueprint의 Modifier 항목:
  ├── Target Attribute: Health    ← GE에서 고정
  ├── ModifierOp: Additive        ← GE에서 고정
  └── Magnitude: [MMC 반환값]     ← 여기만 MMC가 채움
```

MMC는 **얼마나**만 결정한다. **누구에게, 어떤 연산으로**는 GE Blueprint가 고정한다. 반환한 float이 Aggregator 파이프라인에 Modifier로 들어가 기존 집산 공식을 그대로 탄다.

**ExecCalc**: GE Blueprint의 Modifier 목록을 완전히 무시하고, `AddOutputModifier`로 Modifier 항목 자체를 코드에서 생성한다.

```cpp
OutExecutionOutput.AddOutputModifier(
    FGameplayModifierEvaluatedData(
        ULyraHealthSet::GetDamageAttribute(),  // 어떤 Attribute — 코드에서 결정
        EGameplayModOp::Additive,              // 어떤 연산 — 코드에서 결정
        DamageDone));                          // 얼마나 — 코드에서 결정
```

**누구에게, 어떤 연산으로, 얼마나** 모두 코드에서 자유롭게 결정한다. `AddOutputModifier`를 여러 번 호출해서 다른 Attribute들을 동시에 수정하는 것도 가능하다.

| | MMC | ExecCalc |
|---|---|---|
| GE Blueprint Modifier 항목 | 반드시 있어야 함 (MMC가 그 안에 들어감) | 없어도 됨 (ExecCalc가 Modifier 자체를 생성) |
| 결정하는 것 | 크기(float) 하나 | Attribute + 연산 + 크기 전부 |
| 수정 가능한 Attribute 수 | Modifier 항목 하나당 하나 | 한 번에 여러 개 가능 |

Lyra의 `Damage → Health` Meta Attribute 패턴이 ExecCalc를 요구하는 이유가 여기 있다. MMC는 GE에 미리 선언된 Attribute 하나의 크기만 결정할 수 있으므로, `Damage` Meta Attribute를 직접 지정해서 쓰는 구조를 만들 수 없다.
