# GE 적용 & 제거

> **GASDoc**: 4.5.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-applying"></a>
#### GameplayEffect를 적용하는 방법과 적용 감지 델리게이트는 어떻게 사용하는가?

GE는 `ApplyGameplayEffectTo` 계열 함수로 적용하며, 결국 Target의 `UAbilitySystemComponent::ApplyGameplayEffectSpecToSelf()`를 호출하는 편의 래퍼다. GA 외부(발사체 등)에서 적용하려면 Target의 ASC를 직접 가져와 호출한다.

`Duration` 또는 `Infinite` GE가 적용되는 시점을 감지하려면:

```c++
AbilitySystemComponent->OnActiveGameplayEffectAddedDelegateToSelf.AddUObject(this, &APACharacterBase::OnActiveGameplayEffectAddedCallback);
```
```c++
virtual void OnActiveGameplayEffectAddedCallback(UAbilitySystemComponent* Target, const FGameplayEffectSpec& SpecApplied, FActiveGameplayEffectHandle ActiveHandle);
```

| 대상 | 호출 조건 |
|---|---|
| 서버 | 복제 모드와 무관하게 항상 호출 |
| Autonomous Proxy | `Full` 및 `Mixed` 복제 모드에서 복제된 GE에 한해 호출 |
| Simulated Proxy | `Full` 복제 모드에서만 호출 |

<a name="concepts-ga-removing"></a>
#### GameplayEffect를 제거하는 방법과 제거 감지 델리게이트는 어떻게 사용하는가?

GE는 `RemoveActiveGameplayEffect` 계열 함수로 제거하며, 결국 Target의 `FActiveGameplayEffectsContainer::RemoveActiveEffects()`를 호출하는 편의 래퍼다. GA 외부에서 제거하려면 Target의 ASC를 직접 가져와 호출한다.

`Duration` 또는 `Infinite` GE가 제거되는 시점을 감지하려면:

```c++
AbilitySystemComponent->OnAnyGameplayEffectRemovedDelegate().AddUObject(this, &APACharacterBase::OnRemoveGameplayEffectCallback);
```
```c++
virtual void OnRemoveGameplayEffectCallback(const FActiveGameplayEffect& EffectRemoved);
```

호출 조건은 적용 감지와 동일하다(서버: 항상 / Autonomous: Full·Mixed / Simulated: Full만).

---

### GE의 ReplicationMode(Minimal / Mixed / Full)에 따라 GE 정보가 어떻게 다르게 복제되는가?

> 소스: `GameplayEffect.cpp:5072`, `GameplayEffect.cpp:4618`

| 복제 모드 | `FActiveGameplayEffectsContainer` 복제 | Simulated Proxy가 받는 것 |
|---|---|---|
| `Minimal` | 복제 안 함 | MinimalReplicationTags + MinimalReplicationGameplayCues |
| `Mixed` | Owner에게만 복제 | MinimalReplicationTags + MinimalReplicationGameplayCues |
| `Full` | 모든 클라이언트에 복제 | 전체 GE 컨테이너 |

Lyra는 `Mixed`. 자기 자신(Owner)에게는 전체 GE 목록, 다른 플레이어들에게는 Tag + GameplayCue만 전달된다.

---

### Owning client가 GE Spec 전체를 받아야 하는 이유는 예측(Prediction)과 어떻게 연결되는가?

> 소스: `GameplayEffect.cpp:2822`

Owner는 자기 행동의 결과를 서버 응답 전에 즉시 화면에 반영해야 한다. 이를 위해 GE를 로컬에서 먼저 실행하고 서버 확인본과 대조한다.

```
예측 방식:
  버튼 누름 → GE 로컬 즉시 적용(0ms) → 화면 즉시 반응
              동시에 서버 전송 → 서버 처리 → FActiveGameplayEffect 복제
              → PredictionKey로 대조 → 일치: 확정 / 불일치: 롤백
```

GE를 로컬에서 실행하려면 Spec 데이터(Modifiers, Duration 등)가 필요하고, 서버 확인본과 대조할 때도 Spec이 있어야 한다. Simulated Proxy는 다른 플레이어의 행동을 예측할 필요가 없으므로 Tag + GameplayCue로 충분하다.

---

### FActiveGameplayEffect에서 복제되는 필드, 클라에서 재구성하는 필드, 클라에 없는 필드는 어떻게 나뉘는가?

> 소스: `GameplayEffect.h:1406`, `GameplayEffect.cpp:2866`

**복제되는 것** — 예측 실행 및 대조에 필요한 데이터

| 필드 | 비고 |
|---|---|
| `Spec.Modifiers` (EvaluatedMagnitude) | Attribute 변경량 |
| `Spec.Duration / Period / Level` | |
| `Spec.EffectContext` | Instigator, HitResult 등 |
| `Spec.DynamicGrantedTags / StackCount` | |
| `StartServerWorldTime` | 서버 기준 시작 시각 |
| `PredictionKey` | 예측 대조 키 |

**클라에서 재구성하는 것** — 로컬 데이터로 충분히 계산 가능

| 필드 | 재구성 방법 |
|---|---|
| `Handle` | `GenerateNewHandle()`로 새 로컬 ID 발급 |
| `bIsInhibited` | 현재 보유 Tag로 재계산 |
| `StartWorldTime` | `StartServerWorldTime`으로 로컬 시계 변환 |

**클라에 없는 것** — Apply 시 이미 소모된 데이터

| 필드 | 이유 |
|---|---|
| `SetByCallerTagMagnitudes` | Apply 때 쓴 입력값. 결과는 Modifiers에 있음 |
| `CapturedSourceTags / TargetTags` | MMC/Execution 계산에 쓰인 스냅샷. 재사용 없음 |
| `DurationHandle / PeriodHandle` | 서버가 타이머 소유. 만료 시 직접 제거 후 복제 |
