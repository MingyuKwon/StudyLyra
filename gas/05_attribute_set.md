# Attribute & AttributeSet

## FGameplayAttribute vs FGameplayAttributeData

### 한 줄 요약

- **`FGameplayAttributeData`** = 값을 **저장**하는 그릇 (BaseValue, CurrentValue)
- **`FGameplayAttribute`** = 그 그릇을 **가리키는 식별자/핸들** (어느 AttributeSet의 어느 프로퍼티인지)

### FGameplayAttributeData — 데이터 저장소

```cpp
// AttributeSet 클래스 안에 멤버 변수로 선언
UPROPERTY()
FGameplayAttributeData Health;  // 실제 float 값 두 개를 들고 있음
```

그 자체로는 "나는 Health다"라는 정체성이 없다. 그냥 float 두 개짜리 구조체다.

### FGameplayAttribute — 식별자/핸들

```cpp
struct FGameplayAttribute
{
    TFieldPath<FProperty> Attribute;      // 핵심: 어느 클래스의 어느 변수인지 가리키는 FProperty*
    TObjectPtr<UStruct>   AttributeOwner; // 소유 AttributeSet 클래스
    FString               AttributeName;
};
```

`FProperty*`를 감싼 래퍼다. "**ULyraHealthSet 클래스의 Health 변수**"를 런타임에 식별하는 키다.

### ATTRIBUTE_ACCESSORS 매크로로 보는 관계

```cpp
ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)
// 이 한 줄이 아래 세 함수를 만들어냄

// FGameplayAttributeData에서 float 읽기
float GetHealth() const { return Health.GetCurrentValue(); }

// FGameplayAttribute (식별자) 반환
static FGameplayAttribute GetHealthAttribute()
{
    static FProperty* Property = FindFieldChecked<FProperty>(
        ULyraHealthSet::StaticClass(), GET_MEMBER_NAME_CHECKED(ULyraHealthSet, Health)
    );
    return FGameplayAttribute(Property);
}

// FGameplayAttribute를 키로 ASC에 요청 → 내부적으로 FGameplayAttributeData 수정
void SetHealth(float NewVal) { ASC->SetNumericAttributeBase(GetHealthAttribute(), NewVal); }
```

### 어디서 각각 쓰이는가

| 용도 | 타입 |
|------|------|
| GE Modifier 타겟 지정 ("Health를 수정해라") | `FGameplayAttribute` |
| ASC에서 값 조회/설정 (`GetNumericAttribute`) | `FGameplayAttribute` (키) |
| `AttributeAggregatorMap`의 키 | `FGameplayAttribute` |
| `OnAttributeChanged` 델리게이트 바인딩 | `FGameplayAttribute` |
| 실제 float 값 읽기/쓰기 | `FGameplayAttributeData` |
| 복제 (`OnRep_Health` 파라미터) | `FGameplayAttributeData` |

> **비유:** `FGameplayAttributeData`는 메모리에 있는 **실제 박스**, `FGameplayAttribute`는 그 박스의 **주소가 적힌 라벨**.
> GAS 시스템이 "Health를 수정해라"는 명령을 주고받을 때는 항상 라벨(`FGameplayAttribute`)을 들고 다니다가,
> 실제로 값을 건드릴 때만 박스(`FGameplayAttributeData`)를 연다.

---

## FGameplayAttributeData 구조

```cpp
USTRUCT(BlueprintType)
struct FGameplayAttributeData
{
    float BaseValue;    // 영구적인 기본값
    float CurrentValue; // 버프/디버프 포함 실제값
};
```

## BaseValue vs CurrentValue - 왜 나눠지는가?

**핵심 개념:** GAS는 Attribute 수치 변화를 "영구"와 "임시"로 분리해서 관리한다.

| | BaseValue | CurrentValue |
|---|---|---|
| 의미 | 영구적인 기반 수치 | 버프/디버프까지 반영한 실제 수치 |
| 변경 시점 | Instant GE 적용, 직접 SetBase 호출 | Duration/Infinite GE 적용/만료 시 Aggregator가 재계산 |
| 예시 | 기본 공격력 100, 아이템으로 +20 | 버프 발동 중 150, 버프 만료 후 120 |

### 시나리오로 이해하기

```
초기 상태
  BaseValue  = 100
  CurrentValue = 100

→ Instant GE (+20 영구 강화)
  BaseValue  = 120   ← 직접 변경 (영구)
  CurrentValue = 120

→ Duration GE (버프, +50% 공격력, 10초)
  BaseValue  = 120   ← 그대로
  CurrentValue = 180  ← Aggregator가 재계산: 120 * 1.5

→ 버프 만료
  BaseValue  = 120   ← 그대로
  CurrentValue = 120  ← Aggregator 재계산, 버프 modifier 제거됨
```

## GameplayEffect 종류에 따른 내부 동작

### Instant GE → BaseValue 직접 변경 (영구)

엔진 코드(`GameplayEffect.cpp`)에서 Instant GE는 `InternalExecuteMod` →
`ApplyModToAttribute` → `SetAttributeBaseValue`를 호출해 BaseValue를 직접 수정한다.

```
InternalExecuteMod()
  └─ ApplyModToAttribute()
        ├─ GetAttributeBaseValue()       // 현재 BaseValue 읽기
        ├─ StaticExecModOnBaseValue()    // 연산 (Add / Multiply / Override)
        └─ SetAttributeBaseValue()       // BaseValue 영구 변경
```

### Duration / Infinite GE → Aggregator에 Modifier 추가 (임시)

BaseValue는 건드리지 않고, `FAggregator`에 Modifier를 등록한다.
GE가 유효한 동안 CurrentValue는 Aggregator가 매번 다음 공식으로 재계산한다.

```
CurrentValue = ((BaseValue + Additive) * Multiplicative / Division) + FinalAdd
```

GE가 만료되면 Modifier만 제거되고, CurrentValue는 자동으로 BaseValue 기반으로 복원된다.

## BaseValue 변경 → CurrentValue 동기화 콜체인

BaseValue가 바뀔 때 CurrentValue도 따라 바뀌는 흐름은 `SetAttributeBaseValue` 내부에서
**Aggregator 존재 여부**에 따라 경로가 갈린다.

### Aggregator가 없는 경우 (활성 Duration/Infinite GE 없음)

BaseValue → CurrentValue가 동일 값으로 바로 기록된다.

```
SetAttributeBaseValue(Attribute, NewBaseValue)
  ├─ DataPtr->SetBaseValue(NewBaseValue)       // ① BaseValue 기록
  └─ InternalUpdateNumericalAttribute()        // ② Aggregator 없으므로 바로 진행
        └─ SetNumericAttribute_Internal()
              └─ SetNumericValueChecked()
                    └─ DataPtr->SetCurrentValue(NewBaseValue)  // ③ CurrentValue = BaseValue
```

### Aggregator가 있는 경우 (Duration/Infinite GE 활성 중)

BaseValue 변경이 dirty 이벤트를 통해 Aggregator 재계산을 트리거하고,
`BaseValue + 모든 Modifier`를 합산한 결과가 CurrentValue에 들어간다.

```
SetAttributeBaseValue(Attribute, NewBaseValue)
  ├─ DataPtr->SetBaseValue(NewBaseValue)       // ① BaseValue 기록
  └─ Aggregator->SetBaseValue(NewBaseValue)
        └─ BroadcastOnDirty()                  // ② dirty 이벤트 발생
              └─ OnDirty 델리게이트 발동
                    └─ ASC::OnAttributeAggregatorDirty()
                          └─ Aggregator->Evaluate()    // ③ BaseValue + 모든 Modifier 재계산
                                └─ InternalUpdateNumericalAttribute(NewValue)
                                      └─ SetNumericAttribute_Internal()
                                            └─ SetNumericValueChecked()
                                                  └─ DataPtr->SetCurrentValue(NewValue)  // ④ CurrentValue 갱신
```

### Aggregator가 언제 생성되는가?

이 Attribute에 처음 Duration/Infinite GE가 적용되는 순간 `AttributeAggregatorMap`에 생성된다.
생성 시 ASC의 `OnAttributeAggregatorDirty`를 `OnDirty` 델리게이트에 등록해두기 때문에
이후 BaseValue가 바뀔 때마다 Aggregator가 자동으로 CurrentValue를 재계산할 수 있다.

```cpp
// GameplayEffect.cpp
NewAttributeAggregator->OnDirty.AddUObject(
    Owner,
    &UAbilitySystemComponent::OnAttributeAggregatorDirty,
    Attribute, false
);
```

> **결론:** 두 경로 모두 최종적으로 `DataPtr->SetCurrentValue()`를 호출한다.
> BaseValue를 바꾸면 CurrentValue는 항상 자동으로 갱신되며, 버프가 걸려있어도 버프 효과는 보존된 채 재계산된다.

## 코드에서 설정하는 방법

### ATTRIBUTE_ACCESSORS 매크로가 생성하는 3가지 함수

`ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)` 한 줄이 아래 세 함수를 자동 생성한다.

```cpp
// 1. Getter: CurrentValue 반환 (실제 게임에서 쓰는 값)
float GetHealth() const
{
    return Health.GetCurrentValue();
}

// 2. Setter: ASC를 통해 BaseValue 변경
void SetHealth(float NewVal)
{
    AbilityComp->SetNumericAttributeBase(GetHealthAttribute(), NewVal);
}

// 3. Initter: BaseValue와 CurrentValue 둘 다 직접 설정 (초기화 전용)
void InitHealth(float NewVal)
{
    Health.SetBaseValue(NewVal);
    Health.SetCurrentValue(NewVal);
}
```

> **SetHealth vs InitHealth 차이:**
> - `SetHealth` → ASC + Aggregator를 통해 설정. Duration GE modifier가 있으면 CurrentValue가 재계산됨.
> - `InitHealth` → 자료구조를 직접 쓴다. ASC나 Aggregator를 건너뜀. **초기화할 때만 사용.**

### 생성자에서 초기값 설정

```cpp
// LyraHealthSet.cpp
ULyraHealthSet::ULyraHealthSet()
    : Health(100.0f)     // FGameplayAttributeData(100.f) → BaseValue = CurrentValue = 100
    , MaxHealth(100.0f)
{}
```

`FGameplayAttributeData(float DefaultValue)` 생성자가 BaseValue와 CurrentValue를 동시에 설정한다.

### PostGameplayEffectExecute에서의 실제 사용

```cpp
// LyraHealthSet.cpp - Damage Meta Attribute 처리
if (Data.EvaluatedData.Attribute == GetDamageAttribute())
{
    // GetHealth()     → Health.GetCurrentValue() 읽기
    // GetDamage()     → Damage.GetCurrentValue() 읽기
    // SetHealth(...)  → ASC->SetNumericAttributeBase() → BaseValue 변경
    SetHealth(FMath::Clamp(GetHealth() - GetDamage(), 0.0f, GetMaxHealth()));
    SetDamage(0.0f);  // Meta Attribute 초기화
}
```

## Clamp는 어디서 하는가?

GAS에서 Clamp를 처리하는 콜백은 두 개다.

| 콜백 | 언제 호출 | 용도 |
|------|----------|------|
| `PreAttributeChange` | CurrentValue 변경 직전 (Duration GE modifier 재계산 시) | 임시값 Clamp |
| `PreAttributeBaseChange` | BaseValue 변경 직전 (Instant GE, SetHealth 호출 시) | 영구값 Clamp |

```cpp
// LyraHealthSet.cpp
void ULyraHealthSet::ClampAttribute(const FGameplayAttribute& Attribute, float& NewValue) const
{
    if (Attribute == GetHealthAttribute())
    {
        NewValue = FMath::Clamp(NewValue, 0.0f, GetMaxHealth());
    }
    else if (Attribute == GetMaxHealthAttribute())
    {
        NewValue = FMath::Max(NewValue, 1.0f);
    }
}
```

## Meta Attribute 패턴

### 왜 필요한가?

`Health`를 GE가 직접 수정하게 두면 중간에 끼어들 자리가 없다.
예를 들어 데미지 면역, 팀킬 방지, 피격 이벤트 브로드캐스트 같은 로직을 넣으려면
GE 계산 결과를 **한 번 가로채서 처리**할 중간 단계가 필요하다.

그 중간 단계 역할을 하는 것이 Meta Attribute다.

```
GE 적용
  └─ ExecCalc에서 최종 데미지량 계산
        └─ Damage (Meta Attribute) 에 값을 씀   ← 중간 단계
              └─ PostGameplayEffectExecute 호출
                    ├─ 면역 체크, 팀 체크 등 추가 로직
                    ├─ Health -= Damage           ← 실제 반영
                    ├─ 피격 이벤트 브로드캐스트
                    └─ Damage = 0.0f             ← 초기화
```

### 특징

| 항목 | 일반 Attribute | Meta Attribute |
|------|--------------|----------------|
| 복제 | O (클라이언트에도 전달) | X (서버 전용) |
| 영속성 | 값이 유지됨 | 처리 후 반드시 0으로 초기화 |
| GE Modifier 노출 | O | `HideFromModifiers`로 숨김 |
| 용도 | 실제 게임 상태 표현 | 계산 결과의 임시 전달용 |

### 선언 (LyraHealthSet.h)

```cpp
// 일반 Attribute — 복제됨, 클라이언트도 이 값을 봄
UPROPERTY(BlueprintReadOnly, ReplicatedUsing = OnRep_Health, Category = "Lyra|Health",
    Meta = (HideFromModifiers, AllowPrivateAccess = true))
FGameplayAttributeData Health;

// Meta Attribute — 복제 없음, HideFromModifiers로 GE 에디터에서 숨김
// ExecCalc가 결과를 여기에 쓰고, PostGameplayEffectExecute에서 Health에 반영 후 0으로 초기화
UPROPERTY(BlueprintReadOnly, Category="Lyra|Health",
    Meta=(HideFromModifiers, AllowPrivateAccess=true))
FGameplayAttributeData Damage;

UPROPERTY(BlueprintReadOnly, Category="Lyra|Health",
    Meta=(AllowPrivateAccess=true))
FGameplayAttributeData Healing;
```

### ExecCalc에서 Meta Attribute에 쓰기 (LyraDamageExecution.cpp)

ExecCalc는 Source(공격자)의 `BaseDamage`를 Capture해서 거리/물리재질 감쇠, 팀 체크 등을
적용한 뒤, 최종값을 Target(피격자)의 `Damage` Meta Attribute에 출력한다.

```cpp
// LyraDamageExecution.cpp

// ① Source의 BaseDamage Attribute를 Capture하겠다고 등록
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        // Source ASC의 BaseDamage를, Spec 생성 시점의 스냅샷으로 캡처
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            /*bSnapshot=*/true
        );
    }
};

void ULyraDamageExecution::Execute_Implementation(...) const
{
    // ② 캡처된 BaseDamage 값 읽기
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    // ③ 거리 감쇠, 물리재질 감쇠, 팀 체크 등 계산
    float DamageDone = BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation
                       * DamageInteractionAllowedMultiplier;

    // ④ 최종값을 Damage (Meta Attribute) 에 출력
    //    Health를 직접 건드리지 않고 Damage에 쓰는 것이 핵심
    if (DamageDone > 0.0f)
    {
        OutExecutionOutput.AddOutputModifier(
            FGameplayModifierEvaluatedData(
                ULyraHealthSet::GetDamageAttribute(),  // Meta Attribute
                EGameplayModOp::Additive,
                DamageDone
            )
        );
    }
}
```

> `BaseDamage`(CombatSet)와 `Damage`(HealthSet)는 다른 Attribute다.
> - `BaseDamage`: 공격자가 보유한 "공격력" 수치. 아이템/버프로 변할 수 있고 복제된다.
> - `Damage`: 피격자가 이번 GE에서 받을 데미지량. 순간적인 임시값이고 복제하지 않는다.

### PostGameplayEffectExecute에서 처리 (LyraHealthSet.cpp)

ExecCalc가 `Damage`에 값을 쓰면 즉시 `PostGameplayEffectExecute`가 호출된다.
여기서 실제 `Health` 반영, 이벤트 브로드캐스트, 사망 처리를 모두 수행하고 `Damage`를 0으로 초기화한다.

```cpp
// LyraHealthSet.cpp

void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // 피격 메시지 브로드캐스트 (UI 히트마커, 킬피드 등에서 수신)
        if (Data.EvaluatedData.Magnitude > 0.0f)
        {
            FLyraVerbMessage Message;
            Message.Verb      = TAG_Lyra_Damage_Message;
            Message.Instigator = Data.EffectSpec.GetEffectContext().GetEffectCauser();
            Message.Magnitude  = Data.EvaluatedData.Magnitude;
            UGameplayMessageSubsystem::Get(GetWorld()).BroadcastMessage(Message.Verb, Message);
        }

        // Health에서 Damage만큼 차감하고 클램프
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));

        // Meta Attribute 반드시 0으로 초기화 — 다음 GE에 누적되면 안 됨
        SetDamage(0.0f);
    }
    else if (Data.EvaluatedData.Attribute == GetHealingAttribute())
    {
        SetHealth(FMath::Clamp(GetHealth() + GetHealing(), MinimumHealth, GetMaxHealth()));
        SetHealing(0.0f);  // 동일하게 초기화
    }

    // 사망 감지
    if ((GetHealth() <= 0.0f) && !bOutOfHealth)
    {
        OnOutOfHealth.Broadcast(...);
    }
    bOutOfHealth = (GetHealth() <= 0.0f);
}
```

### 전체 데미지 흐름 요약

```
[공격자 ASC]                         [피격자 ASC]
CombatSet::BaseDamage = 50           HealthSet::Health = 100
                                     HealthSet::Damage = 0  (Meta)

GE 발동
  └─ LyraDamageExecution::Execute()
        ├─ Source의 BaseDamage(50) Capture
        ├─ DistanceAttenuation(0.8) 적용
        ├─ 팀 체크 통과 (multiplier = 1.0)
        └─ DamageDone = 40.0
              └─ Damage Meta Attribute += 40   → Damage = 40

PostGameplayEffectExecute 호출
  ├─ 피격 메시지 브로드캐스트 (Magnitude = 40)
  ├─ Health = Clamp(100 - 40, 0, 100) = 60
  └─ Damage = 0.0f  ← 초기화

결과: Health = 60, Damage = 0
```

## 파생 Attribute (Derived Attribute)

GAS는 "다른 Attribute 값을 바라보며 자동으로 갱신되는" 파생 Attribute를 세 가지 방식으로 구현한다.
진정한 의미의 자동 연동은 **방법 1(AttributeBased GE)** 만이고,
나머지는 코드로 수동 연동하는 패턴이다.

---

### 방법 1. AttributeBased GE Modifier — 살아있는 자동 연동

GE의 Modifier Magnitude 타입을 `AttributeBased`로 설정하면,
지정한 Backing Attribute의 현재값을 기반으로 Modifier 크기를 계산한다.

**에디터에서 설정하는 구조:**

```
GE_Modifier
  └─ MagnitudeCalculationType: AttributeBased
        └─ FAttributeBasedFloat
              ├─ BackingAttribute: Source의 Strength (캡처 대상 Attribute)
              ├─ AttributeCalculationType: AttributeMagnitude  (CurrentValue 사용)
              ├─ Coefficient: 0.5                             (최종값 = 0.5 * Strength)
              ├─ PreMultiplyAdditiveValue: 0.0
              └─ PostMultiplyAdditiveValue: 0.0
```

**수식:**
```
ModifierMagnitude = Coefficient * (PreAdd + [BackingAttribute값]) + PostAdd
```

**Duration/Infinite GE일 때 자동 갱신:**

Backing Attribute의 Aggregator가 dirty될 때마다 이 Modifier의 크기가 재계산되고,
타겟 Attribute의 CurrentValue도 자동으로 갱신된다.

```
Strength(BaseValue) = 100
  └─ GE(Infinite): AttackPower += 0.5 * Strength  →  AttackPower CurrentValue += 50

Strength가 120으로 변경됨
  └─ Strength Aggregator dirty
        └─ AttackPower Modifier 재계산: 0.5 * 120 = 60
              └─ AttackPower CurrentValue 자동 갱신
```

> **Instant GE일 때는 자동 갱신 없음.** GE 적용 시점의 Attribute 값만 스냅샷으로 찍어 사용한다.

**`EAttributeBasedFloatCalculationType` 옵션:**

| 타입 | 의미 |
|------|------|
| `AttributeMagnitude` | CurrentValue 사용 (버프 포함) |
| `AttributeBaseValue` | BaseValue만 사용 (버프 제외) |
| `AttributeBonusMagnitude` | CurrentValue - BaseValue (버프 양만) |

---

### 방법 2. PostAttributeChange 콜백 — 코드 수동 연동

AttributeSet의 `PostAttributeChange`에서 한 Attribute가 바뀌면
다른 Attribute를 직접 조정하는 패턴.

**Lyra 실제 예시: MaxHealth가 줄면 Health도 클램프**

```cpp
// LyraHealthSet.cpp
void ULyraHealthSet::PostAttributeChange(
    const FGameplayAttribute& Attribute, float OldValue, float NewValue)
{
    if (Attribute == GetMaxHealthAttribute())
    {
        // MaxHealth가 낮아져서 현재 Health가 새 MaxHealth를 초과하면 강제 클램프
        if (GetHealth() > NewValue)
        {
            // ASC를 통해 Health의 BaseValue를 직접 수정
            ULyraAbilitySystemComponent* LyraASC = GetLyraAbilitySystemComponent();
            LyraASC->ApplyModToAttribute(
                GetHealthAttribute(),
                EGameplayModOp::Override,
                NewValue   // Health = NewMaxHealth 로 덮어씀
            );
        }
    }
}
```

```
MaxHealth = 100, Health = 80

MaxHealth가 60으로 감소
  └─ PostAttributeChange 호출
        └─ Health(80) > MaxHealth(60) 감지
              └─ Health를 60으로 강제 Override
```

`PostAttributeChange`는 **CurrentValue** 변경 후 호출되고,
`PostAttributeBaseChange`는 **BaseValue** 변경 후 호출된다.

---

### 방법 3. MMC (ModMagnitudeCalculation) — 복잡한 다중 Attribute 연산

`UGameplayModMagnitudeCalculation`을 상속해 `CalculateBaseMagnitude()`를 구현하면
여러 Attribute를 동시에 참조하는 복잡한 파생 계산을 GE Modifier에 연결할 수 있다.

```cpp
// 예: MaxHealth = BaseHP + Vitality * 10 + Level * 5 구현

UCLASS()
class UMaxHealthMMC : public UGameplayModMagnitudeCalculation
{
    GENERATED_BODY()

    FGameplayEffectAttributeCaptureDefinition VitalityDef;
    FGameplayEffectAttributeCaptureDefinition LevelDef;

public:
    UMaxHealthMMC()
    {
        // 참조할 Attribute들을 캡처 목록에 등록
        VitalityDef = FGameplayEffectAttributeCaptureDefinition(
            UMyStatSet::GetVitalityAttribute(),
            EGameplayEffectAttributeCaptureSource::Target, false);
        LevelDef = FGameplayEffectAttributeCaptureDefinition(
            UMyStatSet::GetLevelAttribute(),
            EGameplayEffectAttributeCaptureSource::Target, false);

        RelevantAttributesToCapture.Add(VitalityDef);
        RelevantAttributesToCapture.Add(LevelDef);
    }

    float CalculateBaseMagnitude(const FGameplayEffectSpec& Spec) const override
    {
        FAggregatorEvaluateParameters Params;

        float Vitality = 0.f;
        GetCapturedAttributeMagnitude(VitalityDef, Spec, Params, Vitality);

        float Level = 0.f;
        GetCapturedAttributeMagnitude(LevelDef, Spec, Params, Level);

        return Vitality * 10.f + Level * 5.f;  // 이 값이 Modifier 크기가 됨
    }
};
```

GE 에디터에서 Modifier Magnitude 타입을 `CustomCalculationClass`로 설정하고
이 클래스를 지정하면 된다.

---

### 세 가지 방법 비교

| | AttributeBased GE | PostAttributeChange | MMC |
|---|---|---|---|
| 자동 갱신 | Duration/Infinite GE에서 O | 수동 호출 | Duration/Infinite GE에서 O |
| 참조 Attribute 수 | 1개 | 제한 없음 (코드) | 여러 개 |
| 설정 위치 | GE 에디터 | AttributeSet 코드 | C++ 클래스 + GE 에디터 |
| 복잡도 | 낮음 | 중간 | 높음 |
| Lyra 사용 여부 | X (직접 사용 없음) | O (`MaxHealth→Health` 클램프) | X (직접 사용 없음) |

## Lyra에서의 참고 파일

- `Source/LyraGame/AbilitySystem/Attributes/LyraHealthSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraCombatSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraAttributeSet.h`
