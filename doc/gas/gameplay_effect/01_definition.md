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

GE가 **인스턴스화되지 않는다**는 설계 때문이다.

GE를 적용할 때 실제로 일어나는 일:

```
UGameplayEffect (ClassDefaultObject만 존재)
    ↓ 적용 시
GameplayEffectSpec 생성 (CDO 기반 스냅샷)
    ↓ 성공 시
FActiveGameplayEffect (컨테이너에 추가)
```

GE 자체는 **CDO 하나만** 존재한다. `new UGameplayEffect()`가 호출되는 게 아니라, CDO에서 데이터를 읽어 `GameplayEffectSpec`을 만드는 방식이다. 따라서 GE에 로직을 추가해도:

- **실행 시점 제어 불가** — 언제 호출할지 GAS가 알 방법이 없음
- **인스턴스 상태를 가질 수 없음** — CDO 하나를 여러 적용이 공유하므로 상태 저장이 위험
- **복제 흐름과 충돌** — GAS의 예측/복제 시스템은 Spec 기반으로 작동하므로, GE에 직접 로직을 끼워넣으면 복제 타이밍 보장이 깨짐

### 로직을 넣는 올바른 위치

로직의 복잡도에 따라 두 곳으로 나뉜다.

| 상황 | 사용할 것 | 역할 |
|---|---|---|
| "얼마나 변경할지" 계산이 필요할 때 | **MMC** (`ModifierMagnitudeCalculation`) | Attribute 하나의 변경량을 동적으로 계산 |
| Source/Target Attribute를 같이 보거나, 여러 Attribute를 한 번에 바꾸거나, 조건 분기가 필요할 때 | **Execution** (`GameplayEffectExecutionCalculation`) | 완전한 계산 로직, 복수 Attribute 변경 가능 |

- **MMC**: `CalculateBaseMagnitude_Implementation` 하나만 오버라이드, 결과값(float) 반환
- **Execution**: `Execute_Implementation`에서 `OutExecutionOutput`에 Attribute 수정을 직접 밀어넣음

GE는 **"무엇을, 얼마나, 어떤 조건에서"를 선언하는 설계도**이고, 실제 계산 로직은 GE가 참조하는 MMC/Execution 안에 캡슐화한다.
