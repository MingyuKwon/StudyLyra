# GESpec & SetByCaller

> **GASDoc**: 4.5.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-spec"></a>
#### GameplayEffectSpec이란 무엇이며 UGameplayEffect CDO와 어떻게 다른가?

GESpec은 `GameplayEffect`의 인스턴스화된 표현이다. GE는 CDO 하나를 모든 적용이 공유하므로 "이번 적용에만 해당하는 데이터"를 담을 별도 객체가 필요하다.

| | `UGameplayEffect` (CDO) | `FGameplayEffectSpec` |
|---|---|---|
| 수명 | 에셋 수명 내내 유지 | 적용마다 생성 → Apply 후 FActiveGameplayEffect에 보관 |
| 공유 | 모든 적용이 공유 | 적용마다 각자 하나씩 |
| 역할 | 정적 설계 | 동적 적용 컨텍스트 |

`UAbilitySystemComponent::MakeOutgoingSpec()`(BlueprintCallable)으로 생성한다. Spec을 즉시 적용하지 않아도 되며, 발사체에 Spec을 전달해 나중에 맞힌 Target에 적용하는 패턴이 일반적이다.

Spec이 담는 주요 데이터: Level, EffectContext(Instigator/HitResult), SetByCaller TMap, Captured Attributes(Snapshot), DynamicGrantedTags/DynamicAssetTags.

<a name="concepts-ge-spec-setbycaller"></a>
##### SetByCaller란 무엇이며 Modifier로 사용할 때와 EC/MMC에서 직접 읽을 때 어떻게 다른가?

`SetByCaller`는 `GameplayEffectSpec`이 `GameplayTag` 또는 `FName`에 연결된 float 값을 실어 나를 수 있게 한다. Spec에 `TMap<FGameplayTag, float>` 및 `TMap<FName, float>`로 저장된다.

| 사용 맥락 | 주의사항 |
| --- | -------- |
| `Modifier`로 사용 | GE 클래스에 미리 정의되어야 한다. GameplayTag 버전만 사용 가능. 해당 태그-값 쌍이 없으면 런타임 에러 + 0 반환 |
| EC/MMC에서 직접 읽기 | 사전 정의 불필요. 없는 키는 기본값 반환 (경고 선택적) |

```c++
// 설정
void FGameplayEffectSpec::SetSetByCallerMagnitude(FGameplayTag DataTag, float Magnitude);
// 읽기
float GetSetByCallerMagnitude(FGameplayTag DataTag, bool WarnIfNotFound = true, float DefaultIfNotFound = 0.f) const;
```

Blueprint에서 오탈자를 방지하기 위해 `FName` 버전보다 `GameplayTag` 버전 사용을 권장한다.

---

### GESpec은 어떤 구조로 복제되며 클라이언트는 어떤 콜백으로 반응하는가?

> 소스: `GameplayEffect.h:1334`, `GameplayEffect.h:1406`, `GameplayEffect.h:1639`, `GameplayEffect.cpp:5153`

GESpec은 직접 전송되지 않는다. Apply 결과물인 `FActiveGameplayEffect` 안에 담겨 컨테이너 단위로 델타 복제된다.

```
FActiveGameplayEffectsContainer : FFastArraySerializer
  └─ TArray<FActiveGameplayEffect> GameplayEffects_Internal
        └─ UPROPERTY() FGameplayEffectSpec Spec
```

**클라이언트 반응 콜백:**
- `PostReplicatedAdd` — 새 GE 수신 시 (GameplayCue Add, Tag 적용)
- `PostReplicatedChange` — GE 변경 시 (스택 수, Duration 등)
- `PreReplicatedRemove` — GE 제거 직전

### Snapshotting이란 무엇이며, bSnapshot과 Source/Target 조합에 따라 캡처 시점이 어떻게 달라지는가?

> 소스: `GameplayEffectAttributeCaptureDefinition.h`, `LyraDamageExecution.cpp`

MMC나 Execution이 Attribute 값을 **언제 찍느냐**를 결정하는 것이다.

| bSnapshot | Source/Target | 캡처 시점 | Duration/Infinite GE 자동 갱신 |
|---|---|---|---|
| `true` | Source | **Spec 생성 시** | No — 고정값 |
| `true` | Target | Spec 적용 시 | No — 고정값 |
| `false` | Source | Spec 적용 시 | Yes |
| `false` | Target | Spec 적용 시 | Yes |

Source + `bSnapshot=true`만 유일하게 Spec 생성 시점에 캡처된다.

**발사체 패턴**: `bSnapshot=true`면 발사 시점 공격력이 고정된다. 비행 중 버프가 붙어도 명중 시 발사 당시 수치로 계산된다.

---

### SetByCaller는 왜 필요하며, Attribute를 공유 상태로 쓰는 대안에 어떤 문제가 있는가?

> 소스: `LyraGameData.h`, `LyraCheatManager.cpp`, `LyraHealthComponent.cpp`

어빌리티가 런타임에 계산한 수치를 GE에 전달할 때:

- **대안 1 — GE Blueprint를 수치마다 따로**: 런타임에 결정되는 값은 표현 불가
- **대안 2 — Attribute에 먼저 써두고 GE가 읽기**: Attribute는 전역 상태라 여러 GE가 동시에 Apply되면 값이 오염됨
- **SetByCaller**: Spec 자체에 키-값을 넣어 운반. Spec은 적용마다 독립적이므로 오염 없음

Lyra가 `DamageGameplayEffect_SetByCaller` GE 하나로 모든 데미지 소스를 재사용하는 이유다.

#### SetByCaller를 GE Modifier로 사용할 때와 Execution에서 직접 읽을 때 어떻게 사용하는가?

**Modifier로 사용 (Lyra 패턴):**

```cpp
FGameplayEffectSpecHandle SpecHandle =
    ASC->MakeOutgoingSpec(ULyraGameData::Get().DamageGameplayEffect_SetByCaller, 1.0f, ASC->MakeEffectContext());
SpecHandle.Data->SetSetByCallerMagnitude(LyraGameplayTags::SetByCaller_Damage, DamageAmount);
ASC->ApplyGameplayEffectSpecToSelf(*SpecHandle.Data.Get());
```

**Execution / MMC에서 직접 읽기:**

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

SetByCaller TMap은 `UPROPERTY` 선언이 없어 복제되지 않는다. Apply 시 `CalculateModifierMagnitudes()`가 SetByCaller 값을 읽어 `Modifiers[i].EvaluatedMagnitude`에 저장하고, 클라이언트는 이 계산 결과를 받는다.

| 시나리오 | 전달 여부 |
|---|---|
| 서버 GE Apply → 클라이언트 복제 | O — Modifiers TArray (EvaluatedMagnitude) |
| SetByCaller TMap 자체 | X — UPROPERTY 없음 |
| 클라이언트 SetByCaller 설정 | X — 로컬 예측에만 쓰임 |

데미지 등 민감한 수치는 서버 권한 GA에서 계산해야 한다.
