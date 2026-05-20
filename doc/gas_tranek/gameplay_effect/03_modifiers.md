# GE Modifier

> **GASDoc**: 4.5.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-mods"></a>
#### GE Modifier의 네 가지 연산(Add / Multiply / Divide / Override)과 네 가지 타입은 각각 어떻게 동작하는가?

Modifier는 Attribute를 예측적으로 변경할 수 있는 **유일한 방법**이다. `CurrentValue`는 `BaseValue`에 모든 Modifier를 집산한 결과다.

```c++
// GameplayEffectAggregator.cpp
((InlineBaseValue + Additive) * Multiplicitive) / Division
```

| 연산 | 설명 |
| ---------- | ---- |
| `Add` | 결과값을 더한다. 음수면 빼기 |
| `Multiply` | 결과값을 곱한다 |
| `Divide` | 결과값으로 나눈다 |
| `Override` | 결과값으로 덮어쓴다. 마지막으로 적용된 Modifier가 우선 |

**Modifier 타입 4종:**

| 타입 | 설명 |
| --- | ---- |
| `Scalable Float` | DataTable을 참조하는 구조체. 어빌리티 레벨에 해당하는 값을 읽는다. DataTable 없이 계수만으로 고정값 하드코딩 가능 |
| `Attribute Based` | Source 또는 Target의 특정 Attribute 값을 가져와 계수를 추가 적용한다. Snapshotting 선택 가능 |
| `Custom Calculation Class` | `ModifierMagnitudeCalculation`(MMC) 클래스를 사용해 복잡한 계산을 수행한다 |
| `Set By Caller` | GE 외부에서 런타임에 `GameplayEffectSpec`에 직접 설정하는 값. `TMap<FGameplayTag, float>`로 저장. **Modifier에서는 GameplayTag 버전만 사용 가능** |

> 퍼센트 기반 변경은 덧셈 이후에 처리되도록 반드시 `Multiply`를 사용해야 한다.

<a name="concepts-ge-mods-multiplydivide"></a>
##### Multiply Modifier 여러 개가 적용될 때 직관과 다르게 합산되는 이유는 무엇인가?

모든 `Multiply`와 `Divide` Modifier는 BaseValue에 곱하기 전에 **서로 더해진다**.

```c++
float Sum = Bias;  // Multiply의 Bias = 1
for (const FAggregatorMod& Mod : InMods)
{
    if (Mod.Qualifies())
        Sum += (Mod.EvaluatedMagnitude - Bias);
}
// 결과: 1 + (Mod1 - 1) + (Mod2 - 1) + ...
```

`1.5` 두 개의 Multiply Modifier가 있을 때 `1.5 × 1.5 = 2.25`가 아니라 `1 + 0.5 + 0.5 = 2.0`이 곱해진다. 50% + 50% = 100% 증가로 처리된다.

**주요 제약 (Paragon 기준 설계):**
- 1 미만의 값은 최대 1개만 사용
- [1, 2) 범위 값은 여러 개 가능
- 2 이상의 값은 1개만 사용

실제 곱셈이 필요하다면 `FAggregatorModChannel::EvaluateWithBase()`의 엔진 코드를 직접 수정해야 한다.

<a name="concepts-ge-mods-gameplaytags"></a>
##### Modifier의 GameplayTag 조건은 언제 평가되며, Infinite GE에서 주의해야 할 점은 무엇인가?

태그 조건은 **GE가 처음 적용되는 시점에만 평가**된다. 주기적으로 실행되는 Infinite GE의 경우 최초 적용 시에는 태그 조건을 고려하지만, 이후 각 주기 실행 시에는 재검사하지 않는다.

적용 이후 태그 변화에 반응하려면 Modifier 태그 조건이 아닌 `OngoingTagRequirements`(GE 전체를 켜고 끄는 것)를 사용해야 한다.

---

### Aggregator란 무엇이며 Attribute 하나당 하나가 존재하는 이유는 무엇인가?

> 소스: `GameplayEffectAggregator.h:278`, `GameplayEffect.h:1960`

**Attribute 하나당 Aggregator 하나**가 존재한다. 그 Attribute에 영향을 주는 모든 Duration/Infinite GE의 Modifier를 모아두고, 요청 시 `BaseValue + 모든 Mod`를 집산해서 `CurrentValue`를 계산한다.

```cpp
// GameplayEffect.h:1960
TMap<FGameplayAttribute, FAggregatorRef> AttributeAggregatorMap;
```

#### Aggregator의 내부 구조는 어떻게 구성되어 있는가?

```cpp
struct FAggregator
{
    float BaseValue;                            // Instant GE가 영구 수정하는 기준값
    FAggregatorModChannelContainer ModChannels; // 쌓인 Modifier들 (연산별로 분류)
    TArray<FActiveGameplayEffectHandle> Dependents; // 변화 구독 GE 목록
    FOnAggregatorDirty OnDirty;                 // 값 변경 시 알림 델리게이트
};
```

#### GE를 적용/제거할 때 Aggregator는 어떻게 반응하며 Instant GE와 Duration GE는 어떻게 다른가?

```
GE Apply  → AddAggregatorMod()    → Mod 추가 → OnDirty → CurrentValue 재계산
GE Remove → RemoveAggregatorMod() → Mod 제거 → OnDirty → CurrentValue 재계산
```

Instant GE는 Aggregator를 거치지 않고 `BaseValue`를 직접 영구 수정한다. Duration/Infinite GE만 Aggregator에 Modifier를 등록하며, 제거될 때 함께 빠진다.

#### Aggregator가 CurrentValue를 계산하는 흐름은 어떻게 되는가?

```
Aggregator.Evaluate()
  → UpdateQualifiesOnAllMods()    태그 조건 체크 → IsQualified 갱신
  → ModChannels.EvaluateWithBase(BaseValue)
       Channel0 → Channel1 → ... 순서대로 순차 계산
  → 반환값 = CurrentValue
```

---

### UE 5.x에서 추가된 MultiplyCompound와 AddFinal을 포함한 집산 공식 전체는 어떻게 되는가?

> 소스: `GameplayEffectTypes.h:112`, `GameplayEffectAggregator.cpp:76`

```cpp
// GameplayEffectTypes.h:116
((BaseValue + AddBase) * MultiplyAdditive / DivideAdditive * MultiplyCompound) + AddFinal
```

| 연산 | 동작 | 비고 |
|---|---|---|
| `AddBase` | BaseValue에 더함. 먼저 처리 | 구버전: `Additive` |
| `MultiplyAdditive` | 더해진 뒤 한 번에 곱함 (1.5 + 1.5 = ×2.0) | 구버전: `Multiplicitive` |
| `DivideAdditive` | 더해진 뒤 한 번에 나눔 | 구버전: `Division` |
| `Override` | 결과를 즉시 덮어씀 | |
| `MultiplyCompound` | **진짜 곱셈** (1.5 × 1.5 = ×2.25) | UE 5.x 신규 |
| `AddFinal` | 모든 곱셈 후 마지막에 덧셈 | UE 5.x 신규 |

#### Override Modifier가 Add/Multiply 계산 전체를 건너뛰는 동작 방식과 여러 개일 때의 우선순위는?

```cpp
// GameplayEffectAggregator.cpp:78
for (const FAggregatorMod& Mod : Mods[EGameplayModOp::Override])
{
    if (Mod.Qualifies())
        return Mod.EvaluatedMagnitude;  // 즉시 반환 — AddBase/Multiply 계산 안 함
}
```

Qualify된 Override가 하나라도 있으면 Add/Multiply/AddFinal 계산 전체를 건너뛴다. Override가 여러 개면 **먼저 Apply된 것(배열 앞쪽)**이 이긴다.

---

### Modifier Channel이란 무엇이며 여러 채널을 사용하면 어떤 효과가 있는가?

> 소스: `GameplayEffectAggregator.h:181`, `GameplayEffectAggregator.cpp:250`

기본적으로 모든 Modifier는 Channel0에 들어간다. 채널을 여러 개 쓰면 **이전 채널의 계산 결과가 다음 채널의 BaseValue**가 된다.

```
BaseValue=100
  Channel0: Add+50        → 150
  Channel1: Override=200  → 200   ← Channel0 결과(150) 무시
  Channel2: Add+10        → 210   ← Override된 200에 추가 보정
```

Override는 같은 Channel 안의 계산만 건너뛴다. 다음 Channel의 계산은 막지 못한다. Channel0~Channel9까지 10개 슬롯이 있으며 `AbilitySystemGlobals`에서 활성화해야 사용 가능하다.

---

### Modifier와 GameplayTag는 어떤 두 가지 방식으로 상호작용하는가?

> 소스: `GameplayEffectAggregator.h:55`, `GameplayEffectAggregator.cpp:28`

#### Source/Target 태그 조건으로 Modifier의 집산 포함 여부를 어떻게 제어하는가?

`FAggregatorMod`는 `SourceTagReqs`와 `TargetTagReqs`를 갖는다. `UpdateQualifies()`가 현재 태그를 조건과 비교해 `IsQualified`를 결정하고, 집산 시 `SumMods()`는 `Qualifies()`가 true인 Modifier만 합산에 포함한다.

**사용 예**: "독 상태(Tag: Status.Poisoned)일 때만 방어력 감소 Modifier 적용"

#### AttributeBased Modifier의 TagFilter는 어떻게 특정 GE 기반 Modifier만 선별적으로 포함/제외하는가?

`Attribute Based` Modifier가 Source Attribute 값을 읽을 때, 그 Attribute에 영향을 주는 Modifier 중 특정 태그를 가진 것만 포함하거나 제외하는 필터다.

**사용 예**: "내 공격력 계산 시 장비 버프 GE에서 온 Modifier만 제외하고 계산"

#### Modifier의 태그 조건은 GE Apply 시점에만 평가되는데, 이후 태그 변화에 반응하려면 어떻게 해야 하는가?

Modifier의 태그 조건은 **GE Apply 시점에 한 번만 평가**된다. 이후 태그가 바뀌어도 `IsQualified`는 재계산되지 않는다.

적용 이후 태그 변화에 반응하려면 Modifier 태그 조건이 아니라 `OngoingTagRequirements`를 사용해야 한다.
