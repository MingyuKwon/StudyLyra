# Ability Tags

> **GASDoc**: 4.6.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-tags"></a>
#### 4.6.9 Ability Tags

`GameplayAbility`에는 내장 로직을 가진 `GameplayTagContainer`가 여러 개 포함되어 있다. 이 `GameplayTag`들은 복제되지 않는다.

| `GameplayTag Container`     | 설명                                                                                                                                                                                                                              |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Ability Tags`              | `GameplayAbility`가 소유하는 `GameplayTag`. 해당 GameplayAbility를 설명하는 용도의 태그다.                                                                                                                                        |
| `Cancel Abilities with Tag` | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화될 때 취소된다.                                                                                                                              |
| `Block Abilities with Tag`  | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화 중인 동안 활성화가 차단된다.                                                                                                                |
| `Activation Owned Tags`     | 이 `GameplayAbility`가 활성화 중인 동안, 해당 GameplayAbility의 Owner에게 부여되는 `GameplayTag`. 이 태그들은 복제되지 않는다는 점에 유의할 것.                                                                                    |
| `Activation Required Tags`  | Owner가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다.                                                                                                                                             |
| `Activation Blocked Tags`   | Owner가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다.                                                                                                                                           |
| `Source Required Tags`      | `Source`가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Source Blocked Tags`       | `Source`가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |
| `Target Required Tags`      | `Target`이 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Target Blocked Tags`       | `Target`이 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |

---

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`  
**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/GameplayAbility.cpp`

---

### 두 가지 GA 실행 경로

GA를 활성화하는 경로는 크게 두 가지다. Source/Target이 이벤트에서만 존재하는 이유는 이 두 경로의 차이에서 비롯된다.

**경로 1 — 직접 활성화 (`TryActivateAbility`)**

입력 바인딩이나 코드에서 직접 호출하는 방식. 발동 주체는 자기 자신이고 외부 컨텍스트가 없다.

```
(입력 or 코드)
  └─ ASC::TryActivateAbilityByClass / ByTag / ByHandle
        └─ InternalTryActivateAbility(Handle, ActorInfo, ActivationMode,
                                       nullptr,   ← TriggerPayload 없음
                                       nullptr)   ← TriggerEventData 없음
```

**경로 2 — 이벤트 트리거 (`SendGameplayEventToActor`)**

GA의 `Triggers` 배열에 특정 GameplayTag와 `TriggerSource = GameplayEvent`를 등록해두면, 해당 태그의 이벤트가 왔을 때 자동 발동된다.

```
SendGameplayEventToActor(TargetActor, EventTag, FGameplayEventData{
    Instigator,      ← 이벤트를 보낸 액터
    Target,          ← 이벤트 대상 액터
    InstigatorTags,  ← → Source
    TargetTags,      ← → Target
    TargetData,      ← HitResult 등 추가 데이터
})
  └─ ASC::HandleGameplayEvent
        └─ TriggerAbilityFromGameplayEvent
              └─ InternalTryActivateAbility(Handle, ActorInfo, ActivationMode,
                                             nullptr,
                                             &TriggerEventData)  ← 이벤트 데이터 전달
```

두 경로 모두 최종적으로 `InternalTryActivateAbility`에 도달하지만, `TriggerEventData`의 존재 여부가 갈린다.

---

### Source / Owner / Target이 가리키는 대상

`InternalTryActivateAbility` 내부의 이 한 줄이 전부를 설명한다.

```cpp
const FGameplayTagContainer* SourceTags = TriggerEventData ? &TriggerEventData->InstigatorTags : nullptr;
const FGameplayTagContainer* TargetTags = TriggerEventData ? &TriggerEventData->TargetTags : nullptr;
```

| 용어 | 실제 데이터 | 설명 |
|---|---|---|
| **Owner** | `ASC->GetOwnedGameplayTags()` | GA를 소유한 ASC의 현재 태그 집합 (캐릭터 자신의 상태) |
| **Source** | `FGameplayEventData::InstigatorTags` | 이벤트를 보낸 쪽의 태그 |
| **Target** | `FGameplayEventData::TargetTags` | 이벤트의 대상 쪽 태그 |

`DoesAbilitySatisfyTagRequirements` 내부에서 각각 다른 컨테이너를 검사한다:

```cpp
// Owner 태그 검사 — 항상 실행
CheckForBlocked(AbilitySystemComponent.GetOwnedGameplayTags(), ActivationBlockedTags);
CheckForRequired(AbilitySystemComponent.GetOwnedGameplayTags(), ActivationRequiredTags);

// Source 태그 검사 — TriggerEventData가 있을 때만
if (SourceTags != nullptr)
{
    CheckForBlocked(*SourceTags, SourceBlockedTags);
    CheckForRequired(*SourceTags, SourceRequiredTags);
}

// Target 태그 검사 — TriggerEventData가 있을 때만
if (TargetTags != nullptr)
{
    CheckForBlocked(*TargetTags, TargetBlockedTags);
    CheckForRequired(*TargetTags, TargetRequiredTags);
}
```

---

### Source/Target이 이벤트 트리거에서만 존재하는 이유

설계 의도에서 비롯된다.

- **직접 실행**: "이 캐릭터가 이 능력을 쓰겠다" — 관련 주체가 자기 자신 하나뿐. 외부에서 온 컨텍스트가 없으므로 Source/Target 자체가 성립하지 않는다.
- **이벤트 트리거**: "X가 Y에게 무언가를 했을 때" — 반드시 발신자(X)와 대상(Y)이 존재한다. `FGameplayEventData`가 이 컨텍스트를 담아 전달된다.

`Source/TargetRequired/BlockedTags`는 이 이벤트 컨텍스트를 활용해 **어떤 조건에서 온 이벤트일 때만 반응할지**를 필터링하는 수단이다. 직접 실행에서는 그런 외부 컨텍스트 자체가 없기 때문에 검사도 생략된다.

---

### 용도 정리

| 태그 컨테이너 | 검사 대상 | 실행 경로 | 사용 예시 |
|---|---|---|---|
| `ActivationRequired/BlockedTags` | Owner (자신) | 직접·이벤트 모두 | 스턴 상태일 때 능력 차단 |
| `SourceRequired/BlockedTags` | Source (이벤트 발신자) | 이벤트 트리거만 | 소총 GA가 보낸 이벤트일 때만 처리 |
| `TargetRequired/BlockedTags` | Target (이벤트 대상) | 이벤트 트리거만 | 대상이 경직 상태일 때만 처형기 발동 |
