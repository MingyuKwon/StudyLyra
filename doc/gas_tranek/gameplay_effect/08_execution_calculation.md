# Execution Calculation

> **GASDoc**: 4.5.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-ec"></a>
#### ExecCalc(ExecutionCalculation)란 무엇이며 예측이 불가능하고 C++로만 구현해야 하는 이유는?

ExecCalc는 GE가 ASC에 변화를 주는 가장 강력한 방법이다. MMC처럼 Attribute를 캡처하고 선택적으로 스냅샷할 수 있으며, MMC와 달리 하나 이상의 Attribute를 변경하고 프로그래머가 원하는 거의 모든 것을 수행할 수 있다. 이 강력함의 대가로 **예측이 불가능하고 반드시 C++로 구현해야 한다**.

ExecCalc는 `Instant`와 `Periodic` GE에서만 사용할 수 있다.

| Snapshot 여부 | Source/Target | 캡처 시점 |
| --- | --- | --- |
| Yes | Source | Spec 생성 시 |
| Yes | Target | Spec 적용 시 |
| No | Source | Spec 적용 시 |
| No | Target | Spec 적용 시 |

Attribute 캡처는 ASC에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산하지만, `PreAttributeChange()`는 실행되지 않으므로 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

`Local Predicted`, `Server Only`, `Server Initiated` GA의 경우 ExecCalc는 서버에서만 호출된다.

<a name="concepts-ge-ec-senddata"></a>
##### ExecCalc에 Attribute 캡처 외의 데이터를 전달하는 방법에는 무엇이 있는가?

<a name="concepts-ge-ec-senddata-setbycaller"></a>
###### ExecCalc에서 GESpec의 SetByCaller 값을 어떻게 읽는가?

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
float Damage = FMath::Max<float>(Spec.GetSetByCallerMagnitude(FGameplayTag::RequestGameplayTag(FName("Data.Damage")), false, -1.0f), 0.0f);
```

<a name="concepts-ge-ec-senddata-backingdataattribute"></a>
###### Backing Data Attribute를 CalculationModifier로 사용해 ExecCalc에 하드코딩 값을 전달하는 방법은?

GE에 캡처된 Attribute 중 하나를 backing data로 사용하는 `CalculationModifier`를 추가하면 된다. ExecCalc가 해당 Attribute를 캡처할 때 이 값을 함께 읽는다.

```c++
float Damage = 0.0f;
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(DamageStatics().DamageDef, EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-backingdatatempvariable"></a>
###### Temporary Variable(Transient Aggregator)을 CalculationModifier로 사용하는 방법은?

`GameplayTag`와 연결된 Temporary Variable을 `CalculationModifier`의 backing data로 사용할 수 있다.

생성자에서 등록:

```c++
ValidTransientAggregatorIdentifiers.AddTag(FGameplayTag::RequestGameplayTag("Data.Damage"));
```

읽기:

```c++
float Damage = 0.0f;
ExecutionParams.AttemptCalculateTransientAggregatorMagnitude(FGameplayTag::RequestGameplayTag("Data.Damage"), EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-effectcontext"></a>
###### 커스텀 GameplayEffectContext를 통해 ExecCalc에 데이터를 전달하는 방법은?

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
FGSGameplayEffectContext* ContextHandle = static_cast<FGSGameplayEffectContext*>(Spec.GetContext().Get());
```

Spec 또는 Context를 수정해야 한다면:

```c++
FGameplayEffectSpec* MutableSpec = ExecutionParams.GetOwningSpecForPreExecuteMod();
// 주의: Attribute 캡처 이후 Spec을 수정할 때는 각별히 주의 필요
```

---

### MMC는 GE Blueprint Modifier를 "채우는" 역할이고 ExecCalc는 Modifier를 "만드는" 역할인데, 그 차이는 무엇인가?

**MMC**: GE Blueprint에 이미 선언된 Modifier 항목 안에 들어간다. 크기(얼마나)만 결정하고, 누구에게·어떤 연산으로는 GE가 고정한다.

**ExecCalc**: Modifier 항목 자체를 코드에서 생성한다. `AddOutputModifier`를 여러 번 호출해 여러 Attribute를 동시에 수정할 수 있다.

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
| 예측 | 가능 (클라/서버 둘 다) | 불가 (서버만) |
| Target ASC 직접 접근 | X | O |

---

### Lyra의 LyraDamageExecution은 어떤 3단계 구조로 ExecCalc를 구현하는가?

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

**1단계 — static 구조체로 캡처 레시피 분리**

```cpp
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;
    FDamageStatics()
    {
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            true  // bSnapshot: 발사 시점에 값 고정
        );
    }
};
static FDamageStatics& DamageStatics() { static FDamageStatics Statics; return Statics; }
```

**2단계 — 생성자에서 캡처 등록**

```cpp
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

등록이 없으면 `AttemptCalculateCapturedAttributeMagnitude` 호출 시 런타임 에러가 난다.

**3단계 — Execute_Implementation (전체가 `#if WITH_SERVER_CODE`로 감싸짐)**

```cpp
void ULyraDamageExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
#if WITH_SERVER_CODE
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    float DamageDone = FMath::Max(
        BaseDamage * DistanceAttenuation * PhysMatAttenuation * TeamMultiplier, 0.0f);

    OutExecutionOutput.AddOutputModifier(FGameplayModifierEvaluatedData(
        ULyraHealthSet::GetDamageAttribute(), EGameplayModOp::Additive, DamageDone));
#endif
}
```

---

### FGameplayEffectAttributeCaptureDefinition(레시피)과 FGameplayEffectAttributeCaptureSpec(값)은 어떻게 다른가?

> 소스: `GameplayEffect.h:766`, `GameplayEffect.cpp:3870`, `GameplayEffectAggregator.cpp:579`

`FGameplayEffectAttributeCaptureDefinition`은 **레시피** — "Source의 BaseDamage를 Snapshot으로 가져와라"는 방법만 담는다. 실제 값은 Spec마다 독립적인 `FGameplayEffectAttributeCaptureSpec`에 저장된다.

```cpp
struct FGameplayEffectAttributeCaptureSpec
{
    FGameplayEffectAttributeCaptureDefinition BackingDefinition; // 레시피 (조회 키)
    FAggregatorRef AttributeAggregator;  // Spec마다 다른 실제 캡처 값
};
```

`DamageStatics().BaseDamageDef`는 조회 키일 뿐이다. `AttemptCalculateCapturedAttributeMagnitude`가 이 키로 해당 Spec의 `CapturedRelevantAttributes`에서 실제 값을 찾는다.

> **구조체 이름 충돌 버그**: 서로 다른 ExecCalc가 같은 이름의 static 구조체를 쓰면 레시피 키가 겹쳐서 엉뚱한 Spec의 값을 읽는다.

캡처 대상은 CurrentValue float이 아니라 **Aggregator 전체**다. `bSnapshot=true`면 Aggregator를 독립 복사, `bSnapshot=false`면 원본 참조를 저장한다. Aggregator 전체를 캡처하는 이유는 Execute 시점에 태그 조건부 Modifier의 포함 여부를 평가할 수 있어야 하기 때문이다.

---

### Lyra의 데미지 시스템이 Meta Attribute 패턴과 서버 권한 보장을 위해 ExecCalc를 선택한 이유는?

**Meta Attribute 패턴**: `Health`를 직접 깎지 않고 `Damage` Meta Attribute에 쓴다. `PostGameplayEffectExecute`가 이를 `Health` 감소로 변환한다. `AddOutputModifier`로 출력 Attribute를 자유롭게 지정할 수 있는 ExecCalc만 이 흐름을 만들 수 있다.

```
ExecCalc → Damage Meta Attribute += DamageDone
         → PostGameplayEffectExecute: Health -= Damage, Damage = 0
```

**서버 권한 보장**: `#if WITH_SERVER_CODE`로 클라이언트 실행을 차단. MMC는 클라이언트에서도 실행되므로 서버 전용 시스템(`ULyraTeamSubsystem`) 호출이 위험하다.

**여러 소스의 값 조합**: BaseDamage(Attribute 캡처) × 거리·재질 감쇠·팀 판별(Context) 조합이 필요하다. ExecCalc만이 여러 소스의 데이터를 자유롭게 조합할 수 있다.
