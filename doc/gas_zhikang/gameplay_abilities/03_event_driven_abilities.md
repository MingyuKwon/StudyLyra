# 이벤트 기반 어빌리티와 페이로드 전달

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 외부 이벤트에 반응하는 어빌리티 구현

"화염 피해를 받으면 이동 속도 증가"같은 발동 효과나, 사망·리스폰 시 커스텀 로직처럼 외부 상태에 반응하는 어빌리티가 필요한 경우가 있다.

반응 트리거로 사용할 수 있는 이벤트 유형:

- 소유자에게 GE가 추가되거나 제거될 때
- 소유자가 대상에게 GE를 적용할 때
- GE 스택 카운트가 변경될 때
- GameplayTag가 추가되거나 제거될 때
- 게임 코드가 소유자에게 프로젝트 전용 Gameplay Event를 트리거할 때

### 구현 방식 선택

**간단한 경우**: AbilityTrigger 설정으로 처리한다. (`AbilityTriggers` 프로퍼티 — [01 어빌리티 활성화](01_activating_abilities.md) "Via Ability Trigger" 참고)

**복잡한 경우**: 어빌리티를 즉시 활성화한 뒤 Wait 함수로 원하는 이벤트를 대기하는 패턴을 사용한다.
예를 들어 `WaitGameplayEvent` AbilityTask를 활성화 직후 호출해 특정 이벤트를 기다리게 한다.
패시브 퍼크·발동 효과처럼 항상 대기 상태여야 하는 어빌리티는 최대한 빨리 활성화한 뒤 Wait 함수를 호출하는 구조로 설계한다.

---

## 이벤트 기반 어빌리티에 추가 파라미터 전달

### Ability Trigger + SendGameplayEvent 방식

어빌리티 트리거를 Gameplay Event로 설정한 경우, `SendGameplayEventToActor`로 태그와 페이로드를 함께 전달한다.
Local Predicted 어빌리티는 클라이언트에서 호출하면 페이로드가 서버로 자동 복제된다.

어빌리티 블루프린트에서 페이로드를 받으려면 `ActivateAbility` 대신 **`ActivateAbilityFromEvent`를 오버라이드**해야 한다.

### WaitGameplayEvent 방식

어빌리티 내에서 `WaitGameplayEvent` AbilityTask로 대기하는 경우,
이벤트가 발생할 때 함께 전달되는 Payload 파라미터를 통해 추가 데이터를 받는다.
커스텀 GameplayEffectContext 클래스를 페이로드에 포함할 수 있다.

---

## 이벤트 트리거 방법 3가지

| 방법 | 설명 |
|---|---|
| `SendGameplayEvent` | 어빌리티 블루프린트에서 소유 Actor에 이벤트 발생 |
| `SendGameplayEventToActor` | `UAbilitySystemBlueprintLibrary`의 정적 함수 — 모든 Actor에 이벤트 발생 |
| `HandleGameplayEvent` | C++에서 모든 ASC에 직접 호출 |

---

## GameplayEventData 페이로드 주요 프로퍼티

이벤트를 트리거할 때 `GameplayEventData` 구조체로 임의의 데이터를 전달할 수 있다.

### OptionalObject1 / OptionalObject2

임의의 오브젝트 포인터 (Actor나 커스텀 오브젝트 클래스 등).
포인터 자체에 의미가 없으므로, 이벤트를 발생시키는 측과 어빌리티에서 수신하는 측이 의미를 서로 약속해야 한다.

### GameplayEffectContextHandle

프로젝트 전용 구조체에 넉백 속도 등 임의의 데이터를 담아 전달할 수 있다.
커스텀 GameplayEffectContext 서브클래스를 사용하는 방법은 [GE 추가 파라미터 전달](../../02_gameplay_effects.md) 참고.

### GameplayAbilityTargetDataHandle

GameplayEffectContext와 유사한 다형성 방식.
프로젝트 전용 타겟팅 데이터를 담기 위한 용도.

---

## 페이로드 전달 — Event 외의 방법

Event가 유일한 방법은 아니지만, **예측 파이프라인을 타면서 활성화마다 다른 데이터를 안전하게 넘길 수 있는 유일한 내장 방법**이 Event다.

### 왜 Event가 기본 정답인가

클라이언트가 `LocalPredicted` 어빌리티를 활성화하면 GAS가 서버로 RPC를 보낸다.
페이로드 유무에 따라 RPC가 분기되며, `FGameplayEventData` 슬롯이 딱 하나다.

```
ServerTryActivateAbility(Handle, InputPressed, PredictionKey)
ServerTryActivateAbilityWithEventData(Handle, InputPressed, PredictionKey, EventData)
```

이 슬롯 밖으로 나가면 예측 파이프라인에서 이탈한다.

### 대안 방법과 제약

| 방법 | 네트워크 예측 | 활성화마다 다른 데이터 |
|---|---|---|
| GameplayEvent | 완전 지원 | 가능 |
| 복제된 상태 읽기 | 가능 (이미 복제됨) | 타이밍 주의 |
| `SourceObject` (Spec) | 지원 안 함 | 불가 — 부여 시점에 고정 |
| 멤버 변수 (`InstancedPerActor`) | 직접 처리 필요 | 경쟁 조건 주의 |

**복제된 상태 읽기**: 어빌리티가 액터의 복제 프로퍼티나 Attribute를 활성화 시점에 직접 읽는 방식. 데이터를 "넘기는" 게 아니라 어빌리티가 꺼내 쓴다. 활성화 순간의 스냅샷이 아닌 현재 상태를 읽으므로 타이밍 이슈에 주의해야 한다.

**`SourceObject`**: `GiveAbility` 시 `FGameplayAbilitySpec`에 `UObject*`를 넣어두고 `GetCurrentSourceObject()`로 꺼내 쓴다. 부여 시점에 고정되므로 활성화마다 다른 데이터를 넘기는 용도에는 맞지 않는다.

**멤버 변수**: `InstancedPerActor` 어빌리티에서 `Spec.GetPrimaryInstance()`로 인스턴스를 꺼낸 뒤 멤버를 설정하고 활성화하는 방식. `ServerOnly` 어빌리티가 아니면 그 멤버를 별도 복제해야 하고, 설정과 활성화 사이에 경쟁 조건이 생긴다.
