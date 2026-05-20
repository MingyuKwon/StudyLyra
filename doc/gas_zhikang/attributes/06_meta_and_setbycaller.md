# Meta Attribute와 SetByCaller

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## SetByCaller

GE Spec에 GameplayTag와 연결된 수치 값을 런타임에 주입하는 기능이다. 게임 코드에서 계산된 값을 GE에 전달할 때 사용한다.

예: 충돌 속도에 따라 데미지 값이 결정되는 GE — 데미지를 미리 계산해 SetByCaller로 GE에 전달한다.

```cpp
// Execution Calculation에서 SetByCaller 값 꺼내기
void ULabEffectDamageExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
    const FGameplayTag DamageParamTag =
        FGameplayTag::RequestGameplayTag(FName("Abilities.Parameters.Damage"), true);
    const float DamageRuntimeValue =
        ExecutionParams.GetOwningSpec().GetSetByCallerMagnitude(DamageParamTag, true, 0.0f);
}
```

SetByCaller는 GE의 Attribute Modifier 값이나 동적 지속시간으로도 직접 사용할 수 있다.

---

## Meta Attribute

AttributeSet에서 계산 중간 결과를 임시로 저장하는 Attribute를 가리키는 관용적 표현이다. 데이터 기반 입출력 변수처럼 동작한다.

예: GE가 여러 Modifier와 Execution을 통해 `Damage` Meta Attribute를 계산하고, AttributeSet이 그 값을 받아 Health를 한 번에 차감한다. 계산이 끝나면 AttributeSet이 Meta Attribute를 0으로 초기화해 이후 계산에 영향을 주지 않도록 한다.

Meta Attribute를 사용하면 직접 Attribute를 수정하는 것보다 유연한 계산이 가능하다. GE Attribute 계산 공식의 제약을 받지 않고 Execution Calculation 클래스에서 자유롭게 로직을 구현할 수 있다.

**Lyra/Fortnite 예시 — Damage Meta Attribute**:

```cpp
// Execution에서 Damage meta attribute 설정
void ULyraDamageExecution::Execute_Implementation(...) const
{
    if (DamageDone > 0.0f)
    {
        OutExecutionOutput.AddOutputModifier(
            FGameplayModifierEvaluatedData(
                ULyraHealthSet::GetDamageAttribute(),
                EGameplayModOp::Additive,
                DamageDone));
    }
}

// AttributeSet에서 Damage meta attribute 소비
void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));
        SetDamage(0.0f);
    }
}
```

---

## Meta Attribute vs SetByCaller — 언제 무엇을 쓸까

둘은 배타적인 관계가 아니다. SetByCaller로 Meta Attribute를 설정할 수도 있고, Execution Calculation에서 SetByCaller 값을 읽어 Meta Attribute를 설정할 수도 있다.

| 상황 | 권장 |
|---|---|
| GAS 기본 Attribute 계산 공식 범위 내에서 값 전달 | SetByCaller |
| GE 동적 지속시간 설정 | SetByCaller |
| Execution Calculation에 Meta Attribute 없이 값 전달 | SetByCaller |
| GE·Execution → AttributeSet으로 계산 결과 전달 | Meta Attribute |
| GAS 디버깅 도구에서 중간값 확인 필요 | Meta Attribute (리셋 시점 조절) |

---

## 데미지 타입 구현 — FireDamage / FireResistance 등

FireDamage, FireCritChance, FireResistance처럼 데미지 타입마다 Attribute를 별도로 정의하면 조합이 폭발적으로 늘어난다.

**Fortnite 방식**: 데미지 타입을 GameplayTag(`Damage.Type.Fire` 등)로 표현하고, Attribute는 `Damage`, `CritChance`, `DamageResistance`처럼 타입 무관 범용으로 정의한다. GE에 에셋 태그로 데미지 타입을 명시한다.

```cpp
ULabEffectDamageExecution::ULabEffectDamageExecution()
{
    // DamageResistance Attribute를 캡처 대상으로 등록
    const FGameplayEffectAttributeCaptureDefinition AttributeCaptureDef(
        ULabCombatAttributeSet::GetDamageResistanceAttribute(),
        EGameplayEffectAttributeCaptureSource::Target,
        /*InSnapshot=*/true);
    RelevantAttributesToCapture.Add(AttributeCaptureDef);
}

void ULabEffectDamageExecution::Execute_Implementation(...) const
{
    // 외부 GE의 데미지 타입 태그 확인 후
    // 동일 태그를 가진 GE의 DamageResistance만 고려
}
```

Execution이 외부 GE의 에셋 태그를 확인해, 같은 데미지 타입 태그를 가진 GE의 Modifier만 고려한다.

### 동작 흐름 상세

상황: 캐릭터에 "Cold +30% DamageResistance" GE와 "Fire +30% DamageResistance" GE가 활성화되어 있다.

**Aggregator의 관점**

GAS Aggregator는 `DamageResistance` Attribute에 붙은 모든 Modifier를 합산해 Current 값을 계산한다.
```
DamageResistance Current = Base(0) + Cold(+30%) + Fire(+30%) = 60%
```
`GetDamageResistance()`를 호출하면 60%가 반환된다.

**Execution Calculation의 관점**

Fire 데미지 GE가 적용될 때 Execution이 실행된다. 이 때 단순히 `GetDamageResistance()` 60%를 쓰지 않는다. `FAggregatorEvaluateParameters`에 태그 필터를 걸어 **Aggregator에게 "Fire 태그가 붙은 GE의 Modifier만 합산해서 줘"** 라고 요청한다.

```cpp
FAggregatorEvaluateParameters EvalParams;
EvalParams.AppliedSourceTagFilter = FireTag;  // Fire 태그 GE만 포함

float FireResistance = 0.f;
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
    DamageResistanceDef, EvalParams, FireResistance);
// → 30% 반환 (Cold GE는 필터링됨)
```

결과적으로 Fire 데미지에는 30%만 적용되고, Cold +30%는 무시된다.

**합산값이 의미 없다는 것의 의미**

`GetDamageResistance()`가 반환하는 60%는 어떤 실제 계산에도 직접 쓰이지 않는다. Execution이 항상 태그 필터로 실효 저항값을 그때그때 뽑아 쓰기 때문이다. 60%라는 숫자는 GAS 디버거나 UI에 노출될 뿐 게임플레이 계산의 입력으로는 의미가 없다.

> **주의**: 이 방식에서 Attribute의 합산값은 의미를 잃는다. Cold +30% + Fire +30% = 합산 +60%이지만 이 값 자체는 의미가 없다.
