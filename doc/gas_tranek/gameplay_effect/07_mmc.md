# Modifier Magnitude Calculation

> **GASDoc**: 4.5.11 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-mmc"></a>
#### MMC(ModifierMagnitudeCalculation)란 무엇이며, ExecCalc와 비교해 어떤 장단점이 있는가?

[`ModifierMagnitudeCalculations`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayModMagnitudeCalculation/index.html)(`ModMagCalc` 또는 `MMC`)는 `GameplayEffects`에서 `Modifiers`로 사용되는 강력한 클래스다. `GameplayEffectExecutionCalculations`와 비슷하게 동작하지만 그보다 기능이 제한적이며, 무엇보다 중요한 장점은 예측(predicted)이 가능하다는 것이다. MMC의 유일한 목적은 `CalculateBaseMagnitude_Implementation()`에서 float 값을 반환하는 것이다. Blueprint와 C++ 모두에서 서브클래스로 만들어 이 함수를 오버라이드할 수 있다.

`MMC`는 `Instant`, `Duration`, `Infinite`, `Periodic` 등 모든 지속 시간 유형의 `GameplayEffects`에서 사용할 수 있다.

`MMC`의 강점은 `GameplayEffect`의 Source 또는 Target에 있는 Attribute 값을 얼마든지 캡처할 수 있으며, `GameplayEffectSpec`에 완전히 접근하여 `GameplayTags`와 `SetByCallers`를 읽을 수 있다는 데 있다. `Attributes`는 스냅샷(snapshotted)으로 캡처하거나 그렇지 않게 캡처할 수 있다. 스냅샷된 `Attributes`는 `GameplayEffectSpec`이 생성될 때 캡처되는 반면, 스냅샷되지 않은 `Attributes`는 `GameplayEffectSpec`이 적용될 때 캡처되며, `Infinite`와 `Duration` `GameplayEffects`에서 `Attribute`가 변경될 때 자동으로 업데이트된다. `Attributes`를 캡처하면 `ASC`에 존재하는 기존 mod들로부터 `CurrentValue`를 재계산한다. 이 재계산은 `AbilitySet`의 `PreAttributeChange()`를 **실행하지 않으므로**, 클램핑이 필요하다면 이 안에서 다시 수행해야 한다.

| Snapshot 여부 | Source/Target | `GameplayEffectSpec` 캡처 시점 | `Infinite`/`Duration` GE에서 Attribute 변경 시 자동 업데이트 |
| ------------- | ------------- | ------------------------------ | ------------------------------------------------------------- |
| Yes           | Source        | 생성 시                        | No                                                            |
| Yes           | Target        | 적용 시                        | No                                                            |
| No            | Source        | 적용 시                        | Yes                                                           |
| No            | Target        | 적용 시                        | Yes                                                           |

`MMC`에서 반환된 float 값은 `GameplayEffect`의 `Modifier`에서 계수(coefficient)와 사전/사후 계수 가산값(pre and post coefficient addition)으로 추가 보정할 수 있다.

Target의 마나 `Attribute`를 캡처하여 독(Poison) 효과로 감소시키는 `MMC` 예시 — Target이 보유한 마나 양과 특정 태그 여부에 따라 감소량이 달라진다:
```c++
UPAMMC_PoisonMana::UPAMMC_PoisonMana()
{

	//ManaDef defined in header FGameplayEffectAttributeCaptureDefinition ManaDef;
	ManaDef.AttributeToCapture = UPAAttributeSetBase::GetManaAttribute();
	ManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
	ManaDef.bSnapshot = false;

	//MaxManaDef defined in header FGameplayEffectAttributeCaptureDefinition MaxManaDef;
	MaxManaDef.AttributeToCapture = UPAAttributeSetBase::GetMaxManaAttribute();
	MaxManaDef.AttributeSource = EGameplayEffectAttributeCaptureSource::Target;
	MaxManaDef.bSnapshot = false;

	RelevantAttributesToCapture.Add(ManaDef);
	RelevantAttributesToCapture.Add(MaxManaDef);
}

float UPAMMC_PoisonMana::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec & Spec) const
{
	// Gather the tags from the source and target as that can affect which buffs should be used
	const FGameplayTagContainer* SourceTags = Spec.CapturedSourceTags.GetAggregatedTags();
	const FGameplayTagContainer* TargetTags = Spec.CapturedTargetTags.GetAggregatedTags();

	FAggregatorEvaluateParameters EvaluationParameters;
	EvaluationParameters.SourceTags = SourceTags;
	EvaluationParameters.TargetTags = TargetTags;

	float Mana = 0.f;
	GetCapturedAttributeMagnitude(ManaDef, Spec, EvaluationParameters, Mana);
	Mana = FMath::Max<float>(Mana, 0.0f);

	float MaxMana = 0.f;
	GetCapturedAttributeMagnitude(MaxManaDef, Spec, EvaluationParameters, MaxMana);
	MaxMana = FMath::Max<float>(MaxMana, 1.0f); // Avoid divide by zero

	float Reduction = -20.0f;
	if (Mana / MaxMana > 0.5f)
	{
		// Double the effect if the target has more than half their mana
		Reduction *= 2;
	}
	
	if (TargetTags->HasTagExact(FGameplayTag::RequestGameplayTag(FName("Status.WeakToPoisonMana"))))
	{
		// Double the effect if the target is weak to PoisonMana
		Reduction *= 2;
	}
	
	return Reduction;
}
```

`MMC` 생성자에서 `FGameplayEffectAttributeCaptureDefinition`을 `RelevantAttributesToCapture`에 추가하지 않은 채로 `Attributes`를 캡처하려 하면, 캡처 시 Spec 누락 오류가 발생한다. `Attributes`를 캡처할 필요가 없다면 `RelevantAttributesToCapture`에 아무것도 추가하지 않아도 된다.

---

### Lyra가 데미지/힐링 계산에 MMC 대신 ExecCalc를 선택한 세 가지 이유는 무엇인가?

> 소스: `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

Lyra C++ 코드베이스에 `UGameplayModMagnitudeCalculation` 서브클래스가 없다. 데미지와 힐링 계산 모두 `UGameplayEffectExecutionCalculation`(ExecCalc)으로 구현됐다. 이 선택이 MMC와 ExecCalc의 차이를 이해하는 핵심이다.

**MMC의 역할**: GE의 Modifier 하나에 대해 float 값 하나를 반환한다. 단일 Attribute 하나를 조작하는 계산에 적합하다.

**ExecCalc의 역할**: 여러 Attribute를 한 번에 조작하고, 출력도 여러 개(`OutExecutionOutput.AddOutputModifier`)를 낼 수 있다.

Lyra의 데미지 계산이 ExecCalc여야 하는 이유:

```cpp
// LyraDamageExecution.cpp:131
const float DamageDone = FMath::Max(
    BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier, 0.0f);

OutExecutionOutput.AddOutputModifier(
    FGameplayModifierEvaluatedData(ULyraHealthSet::GetDamageAttribute(), EGameplayModOp::Additive, DamageDone));
```

1. **Target ASC가 필요하다** — MMC는 `const FGameplayEffectSpec&`만 받는다. Spec의 Context에서 Source/Instigator ASC는 꺼낼 수 있지만, Target ASC는 Spec에 없다. ExecCalc는 `ExecutionParams.GetTargetAbilitySystemComponent()`로 직접 받는다.

    ```cpp
    // LyraDamageExecution.cpp:79 — HitActor 폴백 시 Target ASC 필요
    UAbilitySystemComponent* TargetASC = ExecutionParams.GetTargetAbilitySystemComponent();
    if (!HitActor)
        HitActor = TargetASC ? TargetASC->GetAvatarActor_Direct() : nullptr;
    ```

2. **서버 전용 코드** — MMC는 예측 가능하므로 클라이언트에서도 실행된다. `ULyraTeamSubsystem`처럼 서버에만 존재하는 시스템을 MMC에서 호출하면 클라이언트에서 null이 된다. ExecCalc는 서버만 실행하므로 안전하다. Lyra가 `#if WITH_SERVER_CODE`로 감싼 이유다.

3. **예측이 불필요하다** — 데미지는 서버 권한으로만 처리한다. MMC의 예측 가능 특성이 여기선 오히려 불필요한 클라이언트 실행을 유발한다.

---

### MMC/ExecCalc에서 Attribute 캡처 정의를 static 싱글톤으로 만드는 이유는 무엇인가?

> 소스: `LyraDamageExecution.cpp:14`, `LyraHealExecution.cpp:11`

MMC든 ExecCalc든 Attribute 캡처 정의 방식은 동일하다. Lyra의 패턴:

```cpp
// LyraDamageExecution.cpp:14
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        // Source의 BaseDamage를, Snapshot=true로 캡처
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            true  // bSnapshot: Spec 생성 시점(발사 시점) 고정
        );
    }
};

static FDamageStatics& DamageStatics()
{
    static FDamageStatics Statics;  // 프로세스 전체에서 단 한 번만 생성
    return Statics;
}
```

`static` 지역변수로 만든 이유: `FGameplayEffectAttributeCaptureDefinition`은 생성 비용이 있는데, 모든 데미지 적용마다 새로 만드는 건 낭비다. 한 번만 만들고 계속 재사용한다. MMC 예시 코드에서도 동일한 패턴을 권장한다.

생성자에서 `RelevantAttributesToCapture`에 등록하는 것도 필수다:

```cpp
// LyraDamageExecution.cpp:31
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}
```

이 등록이 없으면 `AttemptCalculateCapturedAttributeMagnitude` 호출 시 "Spec에 캡처 정의가 없다"는 오류가 난다. MMC에서 `GetCapturedAttributeMagnitude`를 쓸 때도 동일하다.

---

### MMC와 ExecCalc는 "Modifier를 채우는가" vs "만드는가" 관점에서 어떻게 다르며, 각각 언제 써야 하는가?

> 소스: `GameplayEffect.h`, `GameplayEffectExecutionCalculation.h`

두 클래스의 핵심 차이:

| | MMC | ExecCalc |
|---|---|---|
| 반환 | float 하나 (Modifier 하나) | 여러 Modifier 출력 가능 |
| 예측 | 가능 — 클라/서버 둘 다 실행 | 불가능 — 서버만 실행 |
| Target ASC 직접 접근 | X — Spec에 없음 | O — `ExecutionParams.GetTargetAbilitySystemComponent()` |
| 서버 전용 시스템 호출 | 위험 — 클라에서도 실행되므로 null 가능 | 안전 |
| 용도 | "이 Modifier의 크기를 동적으로 계산" | "이 GE가 발생시키는 모든 결과를 계산" |

MMC도 `Spec.GetContext().GetInstigator()->GetWorld()->GetSubsystem<>()`처럼 외부 시스템에 접근하는 것 자체는 가능하다. 제약은 "접근 불가"가 아니라 **클라이언트에서도 실행된다**는 점이다. 서버 전용 시스템을 호출하면 클라이언트 쪽에서 null을 반환하거나 크래시가 난다.

**MMC가 적합한 경우**: 예측이 필요한 버프/디버프, 단일 Modifier를 다른 Attribute 값으로 동적 계산 (예: "MaxHealth의 10%만큼 방어막"). 클라이언트에서도 안전하게 실행 가능한 계산.

**ExecCalc가 적합한 경우**: 서버 권한 계산(데미지, 힐링), 여러 Attribute 동시 수정, Target ASC 직접 접근이 필요한 경우, 서버 전용 시스템(팀 판별 등) 호출이 필요한 경우.

Lyra의 데미지는 Target ASC 접근 + 팀 판별 서브시스템 + 서버 전용 처리가 모두 필요하므로 ExecCalc가 올바른 선택이다.
