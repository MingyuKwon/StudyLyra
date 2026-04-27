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

### 서버 GE 적용 후 클라이언트 동기화 구조

> 소스: `GameplayEffect.cpp:2764`, `GameplayEffect.cpp:5072`, `AbilitySystemComponent.h:889`

서버에서 GE가 적용되면 `FActiveGameplayEffect`가 컨테이너에 추가되고, `FFastArraySerializer`가 변경을 클라이언트로 델타 복제한다. 단, **서버와 클라이언트가 들고 있는 데이터가 동일하지 않다.**

#### 복제되는 것 vs 복제되지 않는 것

| 필드 | 복제 여부 | 비고 |
|---|---|---|
| `Spec.Modifiers` (EvaluatedMagnitude) | ✓ | 계산된 Modifier 수치 |
| `Spec.Duration / Period / Level` | ✓ | |
| `Spec.EffectContext` | ✓ | Instigator, HitResult 등 |
| `Spec.DynamicGrantedTags / StackCount` | ✓ | |
| `StartServerWorldTime` | ✓ | 서버 기준 시작 시각 |
| `PredictionKey` | ✓ | |
| `Handle` | ✗ NotReplicated | 클라에서 `GenerateNewHandle()`로 재발급 |
| `bIsInhibited` | ✗ NotReplicated | 클라가 현재 태그 상태로 재계산 |
| `StartWorldTime` | ✗ NotReplicated | `StartServerWorldTime`으로 로컬 시계 기준 재계산 |
| `SetByCallerTagMagnitudes` | ✗ UPROPERTY 없음 | 클라에는 빈 TMap |
| `CapturedSourceTags / TargetTags` | ✗ NotReplicated | |
| `DurationHandle / PeriodHandle` | ✗ (타이머) | 서버만 소유 |

```cpp
// GameplayEffect.cpp:2866 — PostReplicatedAdd 에서 클라이언트 재구성
Handle = FActiveGameplayEffectHandle::GenerateNewHandle(InArray.Owner);  // Handle 재발급
RecomputeStartWorldTime(WorldTimeSeconds, ServerWorldTime);              // 로컬 시간 재계산
```

#### ReplicationMode에 따라 구조 자체가 달라진다

```cpp
// GameplayEffect.cpp:5079
Minimal  →  COND_Never    // FActiveGameplayEffectsContainer 자체가 복제 안 됨
Mixed    →  COND_OwnerOnly // Owner에게만 복제
Full     →  COND_None     // 모든 클라이언트에 복제
```

Minimal / Mixed 모드에서 **Simulated Proxy(다른 플레이어)**는 `FActiveGameplayEffectsContainer`를 받지 않는다. 대신 두 가지가 별도로 복제된다:

- `MinimalReplicationTags` — GE가 부여한 GameplayTag 목록
- `MinimalReplicationGameplayCues` — GameplayCue 이벤트 (RPC)

```cpp
// GameplayEffect.cpp:4618 — Simulated Proxy에는 Cue만
if (ShouldUseMinimalReplication())
    Owner->AddGameplayCue_MinimalReplication(CueTag, Effect.Spec.GetEffectContext());
```

Lyra는 `Mixed` 모드. 내 캐릭터(Owner)에게는 전체 GE 목록이 복제되고, 다른 플레이어들에게는 태그와 GameplayCue만 전달된다.

#### 최종 정리

```
서버:
  FActiveGameplayEffect 완전체
  (Handle, Timers, SetByCaller TMap, CapturedTags, bIsInhibited 등 전부)

클라이언트 Owner (Mixed/Full):
  Spec 핵심 데이터 수신
  Handle 재발급 / bIsInhibited 재계산 / StartWorldTime 재계산
  SetByCaller TMap, Timers, CapturedTags 없음

Simulated Proxy (Mixed 모드):
  FActiveGameplayEffect 없음
  MinimalReplicationTags + GameplayCue 이벤트만 수신
```

