# GESpec & SetByCaller

> **GASDoc**: 4.5.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-spec"></a>
#### GameplayEffectSpec이란 무엇이며 UGameplayEffect CDO와 어떻게 다른가?

[`GameplayEffectSpec`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayEffectSpec/index.html)(GESpec)은 `GameplayEffect`의 인스턴스화된 표현으로 볼 수 있다. GESpec은 자신이 나타내는 `GameplayEffect` 클래스, 생성 레벨, 생성자 정보를 담고 있다. 디자이너가 런타임 이전에 미리 생성해야 하는 `GameplayEffect`와 달리, GESpec은 런타임에 자유롭게 생성하고 수정한 뒤 적용할 수 있다. `GameplayEffect`를 적용할 때 `GameplayEffect`로부터 `GameplayEffectSpec`이 생성되며, 실제로 적용되는 것은 이 GESpec이다.

`GameplayEffectSpec`은 `UAbilitySystemComponent::MakeOutgoingSpec()`(BlueprintCallable)으로 생성한다. `GameplayEffectSpec`을 즉시 적용하지 않아도 된다. 어빌리티에서 생성된 발사체에 `GameplayEffectSpec`을 전달하여, 발사체가 나중에 맞힌 Target에 적용하는 패턴이 일반적이다. `GameplayEffectSpec`이 성공적으로 적용되면 `FActiveGameplayEffect`라는 새 구조체를 반환한다.

`GameplayEffectSpec`의 주요 구성 요소:
- 이 `GameplayEffectSpec`이 생성된 원본 `GameplayEffect` 클래스
- 이 `GameplayEffectSpec`의 레벨. 보통 생성한 어빌리티의 레벨과 동일하지만 다를 수도 있다
- `GameplayEffectSpec`의 지속 시간. 기본적으로 `GameplayEffect`의 지속 시간을 따르지만 다를 수 있다
- Periodic Effect의 경우 `GameplayEffectSpec`의 주기. 기본적으로 `GameplayEffect`의 주기를 따르지만 다를 수 있다
- 이 `GameplayEffectSpec`의 현재 스택 카운트. 스택 한도는 `GameplayEffect`에 정의된다
- `GameplayEffectContextHandle`은 이 `GameplayEffectSpec`을 누가 생성했는지를 알려준다
- Snapshotting으로 인해 `GameplayEffectSpec` 생성 시점에 캡처된 Attribute 값들
- `DynamicGrantedTags`: `GameplayEffect`가 부여하는 `GameplayTag` 외에 `GameplayEffectSpec`이 Target에 추가로 부여하는 태그
- `DynamicAssetTags`: `GameplayEffect`가 보유한 `AssetTag` 외에 `GameplayEffectSpec`이 추가로 가지는 태그
- `SetByCaller` TMap들

<a name="concepts-ge-spec-setbycaller"></a>
##### SetByCaller란 무엇이며 Modifier로 사용할 때와 EC/MMC에서 직접 읽을 때 어떻게 다른가?

`SetByCaller`는 `GameplayEffectSpec`이 `GameplayTag` 또는 `FName`에 연결된 float 값을 실어 나를 수 있게 한다. 이 값들은 각각 `TMap<FGameplayTag, float>`와 `TMap<FName, float>`로 `GameplayEffectSpec`에 저장된다. 이는 `GameplayEffect`에서 Modifier로 사용하거나, 어빌리티 내부에서 생성된 수치 데이터를 `GameplayEffectExecutionCalculation`이나 `ModifierMagnitudeCalculation`으로 전달하는 일반적인 수단으로 활용된다.

| `SetByCaller` 사용 맥락 | 주의사항 |
| ----------------------- | -------- |
| `Modifier`로 사용 | `GameplayEffect` 클래스에 미리 정의되어야 한다. `GameplayTag` 버전만 사용 가능하다. `GameplayEffect` 클래스에 정의되어 있는데 `GameplayEffectSpec`에 대응하는 태그와 float 값 쌍이 없으면, `GameplayEffectSpec` 적용 시 런타임 에러가 발생하고 0을 반환한다. `Divide` 연산의 경우 이것이 잠재적인 문제가 될 수 있다. `Modifier` 참조 |
| 그 외 (EC/MMC 등) | 어디에도 미리 정의할 필요가 없다. `GameplayEffectSpec`에 존재하지 않는 `SetByCaller`를 읽으면 개발자가 정의한 기본값을 선택적 경고와 함께 반환할 수 있다 |

Blueprint에서 `SetByCaller` 값을 설정하려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 Blueprint 노드를 사용한다.

Blueprint에서 `SetByCaller` 값을 읽으려면 Blueprint Library에 커스텀 노드를 만들어야 한다.

C++에서 `SetByCaller` 값을 설정하려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 함수를 사용한다.

```c++
void FGameplayEffectSpec::SetSetByCallerMagnitude(FName DataName, float Magnitude);
```
```c++
void FGameplayEffectSpec::SetSetByCallerMagnitude(FGameplayTag DataTag, float Magnitude);
```

C++에서 `SetByCaller` 값을 읽으려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 함수를 사용한다.

```c++
float GetSetByCallerMagnitude(FName DataName, bool WarnIfNotFound = true, float DefaultIfNotFound = 0.f) const;
```
```c++
float GetSetByCallerMagnitude(FGameplayTag DataTag, bool WarnIfNotFound = true, float DefaultIfNotFound = 0.f) const;
```

Blueprint에서 오탈자를 방지하기 위해 `FName` 버전보다 `GameplayTag` 버전 사용을 권장한다.

---

---

### GESpec이 UGameplayEffect CDO와 별도로 존재해야 하는 이유는 무엇인가?

#### GESpec이 CDO와 별도로 존재해야 하는 이유는 무엇인가?

> GE가 CDO인 이유와 로직을 넣으면 안 되는 이유: [`01_definition.md`](01_definition.md)

GE는 CDO 하나를 모든 적용이 공유한다. CDO는 수정 불가이므로 "이번 적용에만 해당하는 데이터"를 담을 별도 객체가 필요하다.

| | `UGameplayEffect` (CDO) | `FGameplayEffectSpec` |
|---|---|---|
| 수명 | 에셋 수명 내내 유지 | 적용마다 생성 → Apply 후 FActiveGameplayEffect에 보관 |
| 공유 | 모든 적용이 공유 | 적용마다 각자 하나씩 |
| 역할 | 정적 설계 | 동적 적용 컨텍스트 |

Spec이 담는 데이터: Level, EffectContext(Instigator/HitResult), SetByCaller TMap, Captured Attributes(Snapshot), DynamicGrantedTags/DynamicAssetTags

#### GESpec은 어떤 구조로 복제되며 클라이언트는 어떤 콜백으로 반응하는가?

> 소스: `GameplayEffect.h:1334`, `GameplayEffect.h:1406`, `GameplayEffect.h:1639`, `GameplayEffect.cpp:5153`

GESpec은 직접 전송되지 않는다. Apply 결과물인 `FActiveGameplayEffect` 안에 필드로 담겨, 컨테이너 단위로 델타 복제된다.

```
FActiveGameplayEffectsContainer : FFastArraySerializer  (WithNetDeltaSerializer)
  └─ TArray<FActiveGameplayEffect> GameplayEffects_Internal
        └─ UPROPERTY() FGameplayEffectSpec Spec
```

`NetDeltaSerialize` → `FastArrayDeltaSerialize` → 변경된 항목만 델타 전송. `FGameplayEffectSpec`은 커스텀 `NetSerialize`가 없으므로 표준 UPROPERTY 기반 직렬화를 사용한다.

**클라이언트 반응 콜백** (`FFastArraySerializerItem` 인터페이스):
- `PostReplicatedAdd` — 새 GE 수신 시 (GameplayCue Add, Tag 적용)
- `PostReplicatedChange` — GE 변경 시 (스택 수, Duration 등)
- `PreReplicatedRemove` — GE 제거 직전

**ReplicationMode**: `Minimal`(복제 안 함) / `Mixed`(Owner에게만 전체) / `Full`(모두에게 전체). Lyra는 `Mixed`.

#### Snapshotting이란 무엇이며, bSnapshot과 Source/Target 조합에 따라 캡처 시점이 어떻게 달라지는가?

> 소스: `GameplayEffectAttributeCaptureDefinition.h`, `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

MMC나 Execution이 Attribute 값을 읽을 때 **언제 찍느냐**를 결정하는 것이 Snapshotting이다. `FGameplayEffectAttributeCaptureDefinition` 하나로 표현된다.

```cpp
struct FGameplayEffectAttributeCaptureDefinition
{
    FGameplayAttribute                      AttributeToCapture;
    EGameplayEffectAttributeCaptureSource   AttributeSource;  // Source(공격자) or Target(피격자)
    bool                                    bSnapshot;
};
```

| bSnapshot | Source/Target | 캡처 시점 | Duration/Infinite GE 자동 갱신 |
|---|---|---|---|
| `true` | Source | **Spec 생성 시** | No — 고정값 |
| `true` | Target | Spec 적용 시 | No — 고정값 |
| `false` | Source | Spec 적용 시 | Yes |
| `false` | Target | Spec 적용 시 | Yes |

Source + `bSnapshot=true`만 유일하게 Spec 생성 시점에 캡처된다.

**Lyra 사용 패턴** (`LyraDamageExecution.cpp`):

```cpp
// 1. static으로 캡처 정의 (한 번만 생성)
struct FDamageStatics {
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;
    FDamageStatics() {
        BaseDamageDef = { ULyraCombatSet::GetBaseDamageAttribute(),
                          EGameplayEffectAttributeCaptureSource::Source,
                          true };  // bSnapshot=true: 발사 시점 고정
    }
};

// 2. 생성자에서 등록
ULyraDamageExecution::ULyraDamageExecution() {
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}

// 3. Execute_Implementation에서 읽기
float BaseDamage = 0.0f;
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
    DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);
```

**발사체 패턴**: `bSnapshot=true`면 발사 시점 공격력이 고정된다. 비행 중 버프가 붙어도 명중 시 발사 당시 수치로 계산된다. `bSnapshot=false`면 명중 시점 공격력 사용. 설계 의도에 따라 선택한다.

---

### SetByCaller는 왜 필요하며, Attribute를 공유 상태로 쓰는 대안에 어떤 문제가 있는가?

#### SetByCaller가 필요한 이유는 무엇인가?

> 소스: `LyraGameData.h`, `LyraCheatManager.cpp`, `LyraHealthComponent.cpp`

어빌리티가 런타임에 계산한 수치를 GE에 전달해야 할 때 선택지가 몇 가지 있다.

**대안 1 — 수치마다 별도 GE Blueprint**: `Damage10_GE`, `Damage20_GE`... 런타임에 결정되는 값은 표현 불가.

**대안 2 — Attribute에 먼저 써두고 GE가 읽기**: Apply 전에 `CombatSet.BaseDamage = 50` 세팅 → GE Modifier가 Attribute 참조. Attribute는 ASC에 귀속된 전역 상태라 여러 GE가 동시에 Apply되면 값이 오염된다.

**SetByCaller**: Spec 자체에 키-값을 넣어 운반. Spec은 적용마다 독립적이므로 오염 없음. 범용 GE 하나를 다양한 수치로 재사용할 수 있다.

```
GE Blueprint:  Modifier Magnitude 타입 = SetByCaller(Tag: "Damage")
어빌리티:      Spec 생성 → Spec["Damage"] = 50.0f 주입 → Apply
GE Modifier:   Spec["Damage"] 읽어 50.0f 사용
```

Lyra가 `DamageGameplayEffect_SetByCaller` GE 하나로 모든 데미지 소스를 재사용하는 이유다.

**발사체 패턴**: Spec이 값을 들고 이동하므로 발사 시점 수치가 명중까지 보존된다.

```
발사 시점: Spec["Damage"] = 50 (공격력 50 기준)
비행 중:   공격자 공격력 100으로 증가
명중 시점: Spec["Damage"] = 50 그대로 Apply
```

#### SetByCaller를 GE Modifier로 사용할 때와 Execution에서 직접 읽을 때 어떻게 사용하는가?

> 소스: `LyraCheatManager.cpp`, `LyraHealthComponent.cpp`

**맥락 1 — GE Modifier의 Magnitude**: GE Blueprint에서 Magnitude 타입을 `SetByCaller`로 지정. Lyra 패턴:

```cpp
FGameplayEffectSpecHandle SpecHandle =
    ASC->MakeOutgoingSpec(ULyraGameData::Get().DamageGameplayEffect_SetByCaller, 1.0f, ASC->MakeEffectContext());
SpecHandle.Data->SetSetByCallerMagnitude(LyraGameplayTags::SetByCaller_Damage, DamageAmount);
ASC->ApplyGameplayEffectSpecToSelf(*SpecHandle.Data.Get());
```

**맥락 2 — Execution / MMC에서 직접 읽기**: GE Blueprint 사전 정의 불필요. 없는 키는 기본값 반환.

```cpp
float DamageAmount = Spec.GetSetByCallerMagnitude(
    LyraGameplayTags::SetByCaller_Damage, /*WarnIfNotFound=*/true, /*Default=*/0.f);
```

| | Modifier로 사용 | EC/MMC에서 직접 읽기 |
|---|---|---|
| GE Blueprint 사전 정의 | **필요** | 불필요 |
| 태그-값 쌍 없으면 | 런타임 에러 + 0 반환 | 기본값 반환 (경고 선택적) |

#### SetByCaller TMap은 왜 복제되지 않으며, 클라이언트는 어떤 데이터를 대신 받는가?

> 소스: `GameplayEffect.h:1258`, `GameplayEffect.h:1232`

SetByCaller TMap은 `UPROPERTY` 선언 자체가 없다. 직렬화 대상이 아니므로 클라이언트에 전달되지 않는다.

```cpp
// GameplayEffect.h:1258 — UPROPERTY 없음 → 복제 안 됨
TMap<FName, float>         SetByCallerNameMagnitudes;
TMap<FGameplayTag, float>  SetByCallerTagMagnitudes;

// GameplayEffect.h:1232 — UPROPERTY() 있음 → 복제됨
UPROPERTY()
TArray<FModifierSpec> Modifiers;   // EvaluatedMagnitude (계산된 결과)
```

Apply 시 `CalculateModifierMagnitudes()`가 SetByCaller 값을 읽어 `Modifiers[i].EvaluatedMagnitude`에 저장한다. 클라이언트는 TMap 원본이 아니라 계산 결과를 받는다.

| 시나리오 | 전달 여부 |
|---|---|
| 서버 GE Apply → 클라이언트 복제 | ✓ Modifiers TArray (EvaluatedMagnitude) |
| SetByCaller TMap 자체 | ✗ UPROPERTY 없음 |
| 클라이언트 SetByCaller 설정 | ✗ 로컬 예측에만 쓰임 |
| Spec 핸들 직접 RPC 전송 | ✗ Fatal로 차단 |

데미지 등 민감한 수치는 서버 권한 GA에서 계산해야 한다. 클라이언트 계산값을 서버에 신뢰시킬 방법이 없다.
