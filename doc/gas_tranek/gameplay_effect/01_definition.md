# GE 정의

> **GASDoc**: 4.5.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-definition"></a>
#### GameplayEffect란 무엇이며 세 가지 Duration 타입은 언제 사용해야 하는가?

GE는 어빌리티가 자신 또는 대상의 Attribute와 GameplayTag를 변경하는 수단이다. `UGameplayEffect`는 **데이터 전용 클래스**로, 게임 로직을 추가해서는 안 된다. 적용 시 CDO로부터 `FGameplayEffectSpec`이 생성되며, 실제로 적용되는 것은 이 Spec이다.

| Duration Type | GameplayCue 이벤트 | 사용 시점 |
| ------------- | ----------------- | --------- |
| `Instant`     | Execute           | Attribute의 BaseValue를 즉시 영구 변경. GameplayTag는 한 프레임도 적용되지 않음 |
| `Duration`    | Add & Remove      | Attribute의 CurrentValue를 일시 변경하거나, GE 만료 시 함께 해제되는 GameplayTag를 부여할 때. 지속 시간은 GE에서 지정 |
| `Infinite`    | Add & Remove      | Duration과 동일하나 자동으로 만료되지 않음. 어빌리티나 ASC가 직접 제거해야 함 |

`Duration`과 `Infinite` GE는 `Periodic Effect`를 지원한다. `Period`마다 Modifier와 Execution을 실행하며, BaseValue를 변경하는 측면에서 `Instant` GE처럼 동작한다. DoT에 유용하다.

> **참고**: Periodic Effect는 예측(Prediction)이 불가능하다.

---

### GE는 왜 데이터 전용 클래스여야 하며, 로직이 필요할 때는 어디에 넣어야 하는가?

> 소스: `GameplayEffect.h:2096`, `GameplayEffect.cpp:937~991`

GE는 CDO 하나를 모든 적용이 공유한다. 게임 로직을 추가해도 동작하지 않는 세 가지 이유:

- **GAS가 그 함수를 모른다** — GAS가 GE에 호출하는 훅은 고정(`CanApply` / `OnAddedToActiveContainer` / `OnExecuted` / `OnApplied`)이다. 서브클래싱으로 함수를 추가해도 GAS가 언제 호출할지 알 방법이 없다
- **상태를 가질 수 없다** — CDO를 여러 적용이 동시에 공유하므로 멤버 변수에 값을 쓰면 서로 덮어쓴다
- **복제/예측과 충돌** — GAS의 복제·예측은 Spec 기반으로 동작한다. CDO에 로직을 끼워넣으면 실행 보장이 깨진다

GAS 프레임워크 훅들은 전부 `GEComponents` 순회 위임이다:

```cpp
// GameplayEffect.cpp:937
bool UGameplayEffect::CanApply(...) const
{
    for (const UGameplayEffectComponent* GEComponent : GEComponents)
        if (!GEComponent->CanGameplayEffectApply(...)) return false;
    return true;
}
```

**로직을 넣는 올바른 위치:**

| 상황 | 사용할 것 |
|---|---|
| Attribute 변경량 동적 계산 | **MMC** — `CalculateBaseMagnitude_Implementation` 오버라이드 |
| 복수 Attribute 변경, 조건 분기 | **Execution** — `Execute_Implementation`에서 `OutExecutionOutput`에 직접 밀어넣기 |
| GE 적용/실행 흐름에 끼어들기 | **GEComponent** — `UGameplayEffectComponent` 서브클래스를 `GEComponents` 배열에 추가 |

### Periodic GE(DoT)는 왜 클라이언트 예측이 불가능한가?

`GameplayPrediction.h`에 명시되어 있다: Periodic Effect(dots ticking)는 예측 불가.

| 문제 | 설명 |
|---|---|
| **클락 불일치** | 각 틱 타이밍은 서버의 게임 클락이 결정한다. 네트워크 레이턴시로 클라이언트와 서버의 시간이 항상 어긋난다 |
| **BaseValue 영구 수정** | 각 틱은 Instant GE처럼 BaseValue를 영구 변경한다. 롤백이 까다롭다 |
| **오차 누적** | 단발 이벤트는 PredictionKey 하나로 처리되지만, 주기적 틱은 N번의 이벤트가 연속 발생해 오차가 쌓인다 |

따라서 DoT는 **서버에서만 처리**하고 클라이언트는 결과를 복제받는다.

### Ongoing Tag Requirements는 GE를 어떻게 일시 억제(켜고 끄기)하며 완전 제거와는 어떻게 다른가?

> 소스: `TargetTagRequirementsGameplayEffectComponent.cpp`, `AbilitySystemComponent.cpp`

`FActiveGameplayEffect::bIsInhibited` 플래그 하나로 제어한다. GE는 컨테이너에서 제거되지 않고, 이 플래그만 토글된다.

```
bIsInhibited = false  →  GE 활성 (Modifier + Tag 적용 중, GameplayCue Add)
bIsInhibited = true   →  GE 억제 (Modifier + Tag 제거, GameplayCue Remove. 객체는 컨테이너에 잔류)
```

| 조건 | 동작 |
|---|---|
| `OngoingTagRequirements` 불충족 | `bIsInhibited = true` — 일시 억제, 조건 회복 시 재활성 |
| `RemovalTagRequirements` 충족 | `RemoveActiveGameplayEffect` — 영구 제거 |
