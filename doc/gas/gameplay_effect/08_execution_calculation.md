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
