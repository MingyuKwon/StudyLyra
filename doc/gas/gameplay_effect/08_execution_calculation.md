# Execution Calculation

> **GASDoc**: 4.5.12 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-ec"></a>
#### 4.5.12 Gameplay Effect Execution Calculation
[`GameplayEffectExecutionCalculations`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffectExecutionCalculat-/index.html) (`ExecutionCalculation`, `Execution` (you will often see this term in the plugin's source code), or `ExecCalc`) are the most powerful way for `GameplayEffects` to make changes to an `ASC`. Like [`ModifierMagnitudeCalculations`](#concepts-ge-mmc), these can capture `Attributes` and optionally snapshot them. Unlike `MMCs`, these can change more than one `Attribute` and essentially do anything else that the programmer wants. The downside to this power and flexibility is that they can not be [predicted](#concepts-p) and they must be implemented in C++.

`ExecutionCalculations` can only be used with `Instant` and `Periodic` `GameplayEffects`. Anything with the word 'Execute' in it typically refers to these two types of `GameplayEffects`.

Snapshotting captures the `Attribute` when the `GameplayEffectSpec` is created whereas not snapshotting captures the `Attribute` when the `GameplayEffectSpec` is applied. Capturing `Attributes` recalculates their `CurrentValue` from existing mods on the `ASC`. This recalculation will **not** run [`PreAttributeChange()`](#concepts-as-preattributechange) in the `AbilitySet` so any clamping must be done here again.

| Snapshot | Source or Target | Captured on `GameplayEffectSpec` |
| -------- | ---------------- | -------------------------------- |
| Yes      | Source           | Creation                         |
| Yes      | Target           | Application                      |
| No       | Source           | Application                      |
| No       | Target           | Application                      |

To set up `Attribute` capture, we follow a pattern set by Epic's ActionRPG Sample Project by defining a struct holding and defining how we capture the `Attributes` and creating one copy of it in the struct's constructor. You will have a struct like this for every `ExecCalc`. **Note:** Each struct needs a unique name as they share the same namespace. Using the same name for the structs will cause incorrect behavior in capturing your `Attributes` (mostly capturing the values of the wrong `Attributes`).

For `Local Predicted`, `Server Only`, and `Server Initiated` [`GameplayAbilities`](#concepts-ga), the `ExecCalc` only calls on the Server.

Calculating damage received based on a complex formula reading from many attributes on the `Source` and the `Target` is the most common example of an `ExecCalc`. The included Sample Project has a simple `ExecCalc` for calculating damage that reads the value of damage from the `GameplayEffectSpec's` [`SetByCaller`](#concepts-ge-spec-setbycaller) and then mitigates that value based on the armor `Attribute` captured from the `Target`. See `GDDamageExecCalculation.cpp/.h`.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ge-ec-senddata"></a>
##### 4.5.12.1 Sending Data to Execution Calculations
There are a few ways to send data to an `ExecutionCalculation` in addition to capturing `Attributes`.

<a name="concepts-ge-ec-senddata-setbycaller"></a>
###### 4.5.12.1.1 SetByCaller
Any [`SetByCallers` set on the `GameplayEffectSpec`](#concepts-ge-spec-setbycaller) can be directly read in the `ExecutionCalculation`.

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
float Damage = FMath::Max<float>(Spec.GetSetByCallerMagnitude(FGameplayTag::RequestGameplayTag(FName("Data.Damage")), false, -1.0f), 0.0f);
```

<a name="concepts-ge-ec-senddata-backingdataattribute"></a>
###### 4.5.12.1.2 Backing Data Attribute Calculation Modifier
If you want to hardcode values to a `GameplayEffect`, you can pass them in using a `CalculationModifier` that uses one of the captured `Attributes` as the backing data.

In this screenshot example, we're adding 50 to the captured Damage `Attribute`. You could also set this to `Override` to just take in only the hardcoded value.

![Backing Data Attribute Calculation Modifier](https://github.com/tranek/GASDocumentation/raw/master/Images/calculationmodifierbackingdataattribute.png)

The `ExecutionCalculation` reads this value in when it captures the `Attribute`.

```c++
float Damage = 0.0f;
// Capture optional damage value set on the damage GE as a CalculationModifier under the ExecutionCalculation
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(DamageStatics().DamageDef, EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-backingdatatempvariable"></a>
###### 4.5.12.1.3 Backing Data Temporary Variable Calculation Modifier
If you want to hardcode values to a `GameplayEffect`, you can pass them in using a `CalculationModifier` that uses a `Temporary Variable` or `Transient Aggregator` as it's called in C++. The `Temporary Variable` is associated with a `GameplayTag`.

In this screenshot example, we're adding 50 to a `Temporary Variable` using the `Data.Damage` `GameplayTag`.

![Backing Data Temporary Variable Calculation Modifier](https://github.com/tranek/GASDocumentation/raw/master/Images/calculationmodifierbackingdatatempvariable.png)

Add backing `Temporary Variables` to your `ExecutionCalculation`'s constructor:

```c++
ValidTransientAggregatorIdentifiers.AddTag(FGameplayTag::RequestGameplayTag("Data.Damage"));
```

The `ExecutionCalculation` reads this value in using special capture functions similar to the `Attribute` capture functions.

```c++
float Damage = 0.0f;
ExecutionParams.AttemptCalculateTransientAggregatorMagnitude(FGameplayTag::RequestGameplayTag("Data.Damage"), EvaluationParameters, Damage);
```

<a name="concepts-ge-ec-senddata-effectcontext"></a>
###### 4.5.12.1.4 Gameplay Effect Context
You can send data to the `ExecutionCalculation` via a custom [`GameplayEffectContext` on the `GameplayEffectSpec`](#concepts-ge-context).

In the `ExecutionCalculation` you can access the `EffectContext` from the `FGameplayEffectCustomExecutionParameters`.

```c++
const FGameplayEffectSpec& Spec = ExecutionParams.GetOwningSpec();
FGSGameplayEffectContext* ContextHandle = static_cast<FGSGameplayEffectContext*>(Spec.GetContext().Get());
```

If you need change something on the `GameplayEffectSpec` or the `EffectContext`:

```c++
FGameplayEffectSpec* MutableSpec = ExecutionParams.GetOwningSpecForPreExecuteMod();
FGSGameplayEffectContext* ContextHandle = static_cast<FGSGameplayEffectContext*>(MutableSpec->GetContext().Get());
```

Use caution if modifying the `GameplayEffectSpec` in the `ExecutionCalculation`. See the comment for `GetOwningSpecForPreExecuteMod()`.

```c++
/** Non const access. Be careful with this, especially when modifying a spec after attribute capture. */
FGameplayEffectSpec* GetOwningSpecForPreExecuteMod() const;
```

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
