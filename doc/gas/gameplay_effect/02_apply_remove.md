# GE 적용 & 제거

> **GASDoc**: 4.5.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-applying"></a>
#### 4.5.2 GameplayEffect 적용

`GameplayEffect`는 [GameplayAbility](#concepts-ga)의 함수나 ASC의 함수를 통해 다양한 방식으로 적용할 수 있으며, 보통 `ApplyGameplayEffectTo` 형태의 함수를 사용한다. 이 함수들은 결국 Target의 `UAbilitySystemComponent::ApplyGameplayEffectSpecToSelf()`를 호출하는 편의 래퍼다.

GameplayAbility 외부(예: 발사체)에서 GE를 적용하려면, Target의 ASC를 직접 가져와 `ApplyGameplayEffectToSelf` 계열 함수를 사용한다.

ASC에 `Duration` 또는 `Infinite` GE가 적용되는 시점을 감지하려면 델리게이트를 바인딩한다.

```c++
AbilitySystemComponent->OnActiveGameplayEffectAddedDelegateToSelf.AddUObject(this, &APACharacterBase::OnActiveGameplayEffectAddedCallback);
```
콜백 함수:
```c++
virtual void OnActiveGameplayEffectAddedCallback(UAbilitySystemComponent* Target, const FGameplayEffectSpec& SpecApplied, FActiveGameplayEffectHandle ActiveHandle);
```

서버는 복제 모드와 무관하게 항상 이 함수를 호출한다. Autonomous Proxy는 `Full` 및 `Mixed` 복제 모드에서 복제된 GameplayEffect에 대해서만 호출된다. Simulated Proxy는 `Full` [복제 모드](#concepts-asc-rm)에서만 호출된다.

<a name="concepts-ga-removing"></a>
#### 4.5.3 GameplayEffect 제거

`GameplayEffect`도 [GameplayAbility](#concepts-ga)의 함수나 ASC의 함수를 통해 다양한 방식으로 제거할 수 있으며, 보통 `RemoveActiveGameplayEffect` 형태의 함수를 사용한다. 이 함수들은 결국 Target의 `FActiveGameplayEffectsContainer::RemoveActiveEffects()`를 호출하는 편의 래퍼다.

GameplayAbility 외부에서 GE를 제거하려면, Target의 ASC를 직접 가져와 해당 함수를 호출한다.

ASC에서 `Duration` 또는 `Infinite` GE가 제거되는 시점을 감지하려면 델리게이트를 바인딩한다.

```c++
AbilitySystemComponent->OnAnyGameplayEffectRemovedDelegate().AddUObject(this, &APACharacterBase::OnRemoveGameplayEffectCallback);
```
콜백 함수:
```c++
virtual void OnRemoveGameplayEffectCallback(const FActiveGameplayEffect& EffectRemoved);
```

서버는 복제 모드와 무관하게 항상 이 함수를 호출한다. Autonomous Proxy는 `Full` 및 `Mixed` 복제 모드에서 복제된 GameplayEffect에 대해서만 호출된다. Simulated Proxy는 `Full` [복제 모드](#concepts-asc-rm)에서만 호출된다.

---

## 내 분석

### ReplicationMode별 동기화 구조

> 소스: `GameplayEffect.cpp:5072`, `GameplayEffect.cpp:4618`

```cpp
// GameplayEffect.cpp:5079
Minimal  →  COND_Never     // FActiveGameplayEffectsContainer 자체를 복제 안 함
Mixed    →  COND_OwnerOnly // Owner(자기 자신)에게만 복제
Full     →  COND_None      // 모든 클라이언트에 복제
```

Minimal / Mixed에서 Simulated Proxy는 `FActiveGameplayEffectsContainer`를 받지 않는다. 대신 두 가지가 별도 복제된다.

- `MinimalReplicationTags` — GE가 부여한 GameplayTag
- `MinimalReplicationGameplayCues` — GameplayCue 이벤트 (RPC)

```cpp
// GameplayEffect.cpp:4618
if (ShouldUseMinimalReplication())
    Owner->AddGameplayCue_MinimalReplication(CueTag, Effect.Spec.GetEffectContext());
```

Lyra는 `Mixed`. 내 캐릭터(Owner)에게는 전체 GE 목록, 다른 플레이어들에게는 Tag + GameplayCue만.

---

### Owner가 GE Spec 전체를 받는 이유 — 예측(Prediction)

> 소스: `GameplayEffect.cpp:2822`

Tag와 Attribute는 서버가 값을 바꾸면 클라로 직접 복제된다. GE Spec 복제는 그것과 별개의 계층이다.

```
Attribute 복제 (UPROPERTY Replicated)  →  "서버 최종 상태" 전달
Tag 복제 (MinimalReplicationTags)      →  "서버 최종 상태" 전달
GE Spec 복제 (FFastArraySerializer)    →  "예측 대조 근거" 전달
```

Simulated Proxy는 다른 플레이어의 행동을 예측할 필요가 없다. Tag + GameplayCue로 "저 캐릭터에 무슨 일이 일어났는지 보여주는 것"으로 충분하다.

Owner는 자기 행동의 결과를 서버 응답 전에 **즉시** 화면에 반영해야 한다.

```
순수 서버 권한 방식:
  버튼 누름 → 서버 전송(50ms) → 서버 처리 → 복제(50ms) → 화면 반응
  총 100ms 지연 → 조작감 망가짐

예측 방식:
  버튼 누름 → GE 로컬 즉시 적용(0ms) → 화면 즉시 반응
              동시에 서버 전송 → 서버 처리 → FActiveGameplayEffect 복제
              → PredictionKey로 대조 → 일치: 확정 / 불일치: 롤백
```

```cpp
// GameplayEffect.cpp:2822 — PostReplicatedAdd에서 예측 대조
bPostPredictObject = PredictionKey.IsLocalClientKey();
if (bPostPredictObject)
{
    if (InArray.HasPredictedEffectWithPredictedKey(PredictionKey))
        ShouldInvokeGameplayCueEvents = false;  // 예측본이 이미 있으면 중복 방지
}
```

GE를 로컬에서 실행하려면 Spec 데이터(Modifiers, Duration 등)가 필요하고, 서버 확인본과 대조할 때도 Spec이 있어야 한다.

---

### 복제 필드 분류

> 소스: `GameplayEffect.h:1406`, `GameplayEffect.cpp:2866`

서버와 클라이언트가 들고 있는 데이터는 동일하지 않다.

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

```cpp
// GameplayEffect.cpp:2866 — PostReplicatedAdd
Handle = FActiveGameplayEffectHandle::GenerateNewHandle(InArray.Owner);
RecomputeStartWorldTime(WorldTimeSeconds, ServerWorldTime);
```

