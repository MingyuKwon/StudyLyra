# GE 정의

> **GASDoc**: 4.5.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-definition"></a>
#### 4.5.1 GameplayEffect 정의

[`GameplayEffect`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayEffect/index.html)(GE)는 어빌리티가 자신 또는 다른 대상의 [Attribute](#concepts-a)와 [GameplayTag](#concepts-gt)를 변경하는 수단이다. 즉각적인 데미지·힐링부터 이동 속도 버프나 스턴 같은 장기 지속 상태 이상까지 모두 GE로 표현할 수 있다. `UGameplayEffect` 클래스는 **데이터 전용 클래스**로 설계되었으며, 단일 게임플레이 효과를 정의한다. GE에 별도의 로직을 추가해서는 안 된다. 일반적으로 디자이너는 `UGameplayEffect`의 Blueprint 자식 클래스를 다수 만들어 사용한다.

GE는 [Modifier](#concepts-ge-mods)와 [Execution(`GameplayEffectExecutionCalculation`)](#concepts-ge-ec)을 통해 Attribute를 변경한다.

GE에는 세 가지 지속 시간 유형이 있다: `Instant`, `Duration`, `Infinite`.

또한 GE는 [GameplayCue](#concepts-gc)를 추가하거나 실행할 수 있다. `Instant` GE는 GameplayCue GameplayTag에 대해 `Execute`를 호출하며, `Duration` 또는 `Infinite` GE는 `Add`와 `Remove`를 호출한다.

| Duration Type | GameplayCue 이벤트 | 사용 시점 |
| ------------- | ----------------- | --------- |
| `Instant`     | Execute           | Attribute의 BaseValue를 즉시 영구적으로 변경할 때. GameplayTag는 단 한 프레임도 적용되지 않음 |
| `Duration`    | Add & Remove      | Attribute의 CurrentValue를 일시적으로 변경하거나, GE가 만료되거나 수동으로 제거될 때 함께 해제되는 GameplayTag를 부여할 때. 지속 시간은 `UGameplayEffect` 클래스/Blueprint에서 지정 |
| `Infinite`    | Add & Remove      | Attribute의 CurrentValue를 일시적으로 변경하거나, GE가 제거될 때 함께 해제되는 GameplayTag를 부여할 때. 자동으로 만료되지 않으며, 어빌리티나 ASC가 직접 제거해야 함 |

`Duration`과 `Infinite` GE는 `Periodic Effect`를 적용하는 옵션을 제공한다.
Periodic Effect는 `Period`로 지정된 초마다 Modifier와 Execution을 실행한다.
Attribute의 BaseValue를 변경하고 GameplayCue를 Execute하는 측면에서 `Instant` GE와 동일하게 취급된다.
지속 데미지(DoT) 같은 효과에 유용하다.

> **참고**  
> Periodic Effect는 [예측(Prediction)](#concepts-p)이 불가능하다.

`Duration`과 `Infinite` GE는 `Ongoing Tag Requirements`를 충족하지 못하는 경우 적용 이후에도 일시적으로 켜고 끌 수 있다([Gameplay Effect Tags](#concepts-ge-tags) 참조). GE를 끄면 Modifier와 적용된 GameplayTag의 효과는 제거되지만, GE 자체가 제거되지는 않는다. GE를 다시 켜면 Modifier와 GameplayTag가 재적용된다.

Attribute에서 유래하지 않는 데이터를 사용하는 MMC를 가진 `Duration` 또는 `Infinite` GE의 Modifier를 수동으로 재계산해야 할 경우, `UAbilitySystemComponent::ActiveGameplayEffects.SetActiveGameplayEffectLevel(FActiveGameplayEffectHandle ActiveHandle, int32 NewLevel)`을 현재와 동일한 레벨 값으로 호출하면 된다. 현재 레벨은 `UAbilitySystemComponent::ActiveGameplayEffects.GetActiveGameplayEffect(ActiveHandle).Spec.GetLevel()`로 가져올 수 있다. Backing Attribute에 기반하는 Modifier는 해당 Attribute가 업데이트될 때 자동으로 갱신된다. `SetActiveGameplayEffectLevel()`이 Modifier를 업데이트하는 핵심 함수는 다음과 같다.

```C++
MarkItemDirty(Effect);
Effect.Spec.CalculateModifierMagnitudes();
// Private function otherwise we'd call these three functions without needing to set the level to what it already is
UpdateAllAggregatorModMagnitudes(Effect);
```

GE는 일반적으로 직접 인스턴스화되지 않는다. 어빌리티나 ASC가 GE를 적용하고자 할 때, GE의 `ClassDefaultObject`로부터 [`GameplayEffectSpec`](#concepts-ge-spec)을 생성한다. 성공적으로 적용된 `GameplayEffectSpec`은 `FActiveGameplayEffect`라는 새 구조체에 추가되며, ASC는 이를 `ActiveGameplayEffects`라는 전용 컨테이너 구조체로 관리한다.

---

## 내 분석

### GE에 로직을 넣으면 안 되는 이유

> 소스: `GameplayEffect.h:2096`, `GameplayEffect.cpp:937~991`

GE는 절대 `new`로 인스턴스화되지 않는다. CDO 하나를 모든 적용이 공유한다.

```
UGameplayEffect (CDO 하나만 존재)
    ↓ 적용 시
FGameplayEffectSpec 생성 (Spec.Def → CDO 포인터)
    ↓ 성공 시
FActiveGameplayEffect (컨테이너에 추가)
```

따라서 GE에 게임 로직을 추가해도 세 가지 이유로 동작하지 않는다:

- **GAS가 그 함수를 모른다** — GAS가 GE에 호출하는 훅은 `CanApply` / `OnAddedToActiveContainer` / `OnExecuted` / `OnApplied` 로 고정되어 있다. 서브클래싱해서 함수를 추가해도 GAS는 그 함수를 언제 호출할지 알 방법이 없다
- **상태를 가질 수 없다** — CDO를 여러 적용이 동시에 공유하므로 멤버 변수에 값을 쓰면 서로 덮어쓴다
- **복제/예측과 충돌** — GAS의 복제·예측 시스템은 Spec 기반으로 작동한다. CDO에 로직을 끼워넣으면 실행 보장이 깨진다

GAS 프레임워크 훅들의 실제 구현은 전부 `GEComponents` 순회 위임이다. `UGameplayEffect` 자체에는 판단 로직이 없다:

```cpp
// GameplayEffect.cpp:937
bool UGameplayEffect::CanApply(...) const
{
    for (const UGameplayEffectComponent* GEComponent : GEComponents)
        if (!GEComponent->CanGameplayEffectApply(...)) return false;
    return true;
}
// OnAddedToActiveContainer / OnExecuted / OnApplied 모두 동일한 패턴
```

`UGameplayEffect`의 나머지 함수들도 게임 로직이 아니다:

| 종류 | 예시 |
|---|---|
| UObject 라이프사이클 | `PostLoad`, `PostCDOCompiled` — 엔진이 자동 호출 |
| 읽기 전용 Accessor | `GetGrantedTags`, `FindComponent<T>` |
| Deprecated 변환 헬퍼 (private) | `ConvertTagRequirementsComponent` 등 — UE 5.3 마이그레이션용 |

**로직을 넣는 올바른 위치:**

| 상황 | 사용할 것 |
|---|---|
| Attribute 변경량 동적 계산 | **MMC** — `CalculateBaseMagnitude_Implementation` 오버라이드 |
| 복수 Attribute 변경, 조건 분기 | **Execution** — `Execute_Implementation`에서 `OutExecutionOutput`에 직접 밀어넣기 |
| GE 적용/실행 흐름에 끼어들기 | **GEComponent** — `UGameplayEffectComponent` 서브클래스, `GEComponents` 배열에 추가 |

### Periodic Effect가 예측 불가능한 이유

`GameplayPrediction.h`에 이렇게 명시되어 있다:

```
What is not predicted:
  - GameplayEffect removal
  - GameplayEffect periodic effects (dots ticking)
```

GAS Prediction 시스템은 클라이언트가 효과를 먼저 로컬에 적용(낙관적 실행)하고, 서버가 PredictionKey로 검증 후 확인 or 롤백하는 구조다. Instant GE는 "지금 이 순간" 발생하는 단발 이벤트라서 클라이언트와 서버가 같은 사건을 독립적으로 재현할 수 있다.

Periodic GE는 세 가지 이유로 이 구조가 깨진다:

| 문제 | 설명 |
|---|---|
| **클락 불일치** | 각 틱 타이밍은 서버의 게임 클락이 결정한다. 네트워크 레이턴시로 클라이언트/서버 시간이 항상 어긋나므로, 클라이언트가 예측한 틱 시점과 서버의 실제 틱 시점이 다르다 |
| **BaseValue 영구 수정** | 각 틱은 Instant GE처럼 BaseValue를 바꾼다. CurrentValue 수정과 달리 BaseValue 변경은 롤백이 까다롭다 |
| **오차 누적** | 단발 이벤트는 PredictionKey 하나로 처리되지만, 주기적 틱은 N번의 이벤트가 연속 발생한다. 틱마다 예측 오차가 쌓이면 클라이언트/서버 상태가 점점 벌어진다 |

```
Instant GE:   [클라이언트 적용] ←── 서버 확인 1회 → 완료  (예측 가능 ✓)

Periodic GE:  [틱1] [틱2] [틱3] [틱4] ...
              각 틱이 서버 시간 기준으로 발생
              클라이언트가 언제 틱이 올지 알 수 없음  (예측 불가 ✗)
```

따라서 DoT 효과는 **서버에서만 처리**하고 클라이언트는 결과를 복제(Replicate)받는 방식으로 동작한다. Epic도 이를 한계로 인식하고 있으며 `GameplayPrediction.h`에 "미래에 추가 가능성이 있다"고 명시되어 있다.

### Ongoing Tag Requirements — GE 켜고 끄기 메커니즘

> 소스: `TargetTagRequirementsGameplayEffectComponent.cpp`, `AbilitySystemComponent.cpp`

`FActiveGameplayEffect::bIsInhibited` 플래그 하나로 GE의 켜짐/꺼짐을 제어한다. `FActiveGameplayEffect`는 컨테이너에서 제거되지 않고, 이 플래그만 토글된다.

```
bIsInhibited = false  →  GE 활성 (Modifier + Tag 적용 중, GameplayCue Add)
bIsInhibited = true   →  GE 억제 (Modifier + Tag 제거, GameplayCue Remove. 객체는 컨테이너에 잔류)
```

**동작 흐름**: GE 추가 시 `OngoingTagRequirements`에 선언된 태그들에 이벤트 구독 → 태그 변경 시 `RequirementsMet()` 재평가 → `SetActiveGameplayEffectInhibit(handle, !bMet)` 호출. GE 제거 시 구독 전부 해제.

**Ongoing vs Removal 차이**:

| 조건 | 동작 |
|---|---|
| `OngoingTagRequirements` 불충족 | `bIsInhibited = true` — 일시 억제, 조건 회복 시 재활성 |
| `RemovalTagRequirements` 충족 | `RemoveActiveGameplayEffect` — 영구 제거 |
