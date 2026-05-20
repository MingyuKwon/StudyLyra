# Ability Tags

> **GASDoc**: 4.6.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-tags"></a>
#### GA의 여러 GameplayTag 컨테이너(AbilityTags, CancelWith, BlockWith, ActivationRequired 등)는 각각 어떤 역할을 하는가?

`GameplayAbility`에 내장된 `GameplayTagContainer`들이다. 이 태그들은 복제되지 않는다.

| GameplayTag Container | 역할 |
|---|---|
| `Ability Tags` | 이 GA를 설명하는 태그. 다른 컨테이너의 검색 대상이 된다. |
| `Cancel Abilities with Tag` | 이 GA가 활성화될 때, `Ability Tags`에 해당 태그를 가진 다른 GA를 취소한다. |
| `Block Abilities with Tag` | 이 GA가 활성 중인 동안, `Ability Tags`에 해당 태그를 가진 다른 GA의 활성화를 차단한다. |
| `Activation Owned Tags` | 이 GA가 활성 중인 동안 Owner에게 부여되는 태그. 복제되지 않는다. |
| `Activation Required Tags` | Owner가 이 태그를 **모두** 보유할 때만 활성화 가능. |
| `Activation Blocked Tags` | Owner가 이 태그 중 **하나라도** 보유하면 활성화 불가. |
| `Source Required Tags` | Source가 이 태그를 **모두** 보유할 때만 활성화 가능. 이벤트 트리거 경우에만 설정된다. |
| `Source Blocked Tags` | Source가 이 태그 중 **하나라도** 보유하면 활성화 불가. 이벤트 트리거 경우에만 설정된다. |
| `Target Required Tags` | Target이 이 태그를 **모두** 보유할 때만 활성화 가능. 이벤트 트리거 경우에만 설정된다. |
| `Target Blocked Tags` | Target이 이 태그 중 **하나라도** 보유하면 활성화 불가. 이벤트 트리거 경우에만 설정된다. |

---

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`  
**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/GameplayAbility.cpp`

---

### GA를 직접 활성화하는 경로와 이벤트로 트리거하는 경로는 어떻게 다른가?

**경로 1 — 직접 활성화 (`TryActivateAbility`)**

입력 바인딩이나 코드에서 직접 호출하는 방식. 외부 컨텍스트가 없으므로 `TriggerEventData`가 nullptr로 전달된다.

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
    Instigator, Target, InstigatorTags, TargetTags, TargetData
})
  └─ ASC::HandleGameplayEvent
        └─ TriggerAbilityFromGameplayEvent
              └─ InternalTryActivateAbility(..., &TriggerEventData)  ← 이벤트 데이터 전달
```

두 경로 모두 최종적으로 `InternalTryActivateAbility`에 도달하지만, `TriggerEventData`의 존재 여부가 갈린다.

---

### GA 태그 검사에서 Source / Owner / Target이 각각 가리키는 대상은 무엇인가?

```cpp
const FGameplayTagContainer* SourceTags = TriggerEventData ? &TriggerEventData->InstigatorTags : nullptr;
const FGameplayTagContainer* TargetTags = TriggerEventData ? &TriggerEventData->TargetTags : nullptr;
```

| 용어 | 실제 데이터 | 설명 |
|---|---|---|
| **Owner** | `ASC->GetOwnedGameplayTags()` | GA를 소유한 ASC의 현재 태그 집합 (캐릭터 자신의 상태) |
| **Source** | `FGameplayEventData::InstigatorTags` | 이벤트를 보낸 쪽의 태그 |
| **Target** | `FGameplayEventData::TargetTags` | 이벤트의 대상 쪽 태그 |

Owner 태그 검사는 항상 실행되지만, Source/Target 태그 검사는 `TriggerEventData`가 있을 때만 실행된다.

---

### Source/TargetRequired/BlockedTags가 이벤트 트리거에서만 동작하는 이유는 무엇인가?

- **직접 실행**: 발동 주체가 자기 자신 하나뿐이다. 외부에서 온 컨텍스트가 없으므로 Source/Target 자체가 성립하지 않는다.
- **이벤트 트리거**: 반드시 발신자(X)와 대상(Y)이 존재한다. `FGameplayEventData`가 이 컨텍스트를 담아 전달된다.

`Source/TargetRequired/BlockedTags`는 어떤 조건에서 온 이벤트일 때만 반응할지를 필터링하는 수단이다. 직접 실행에서는 그런 외부 컨텍스트 자체가 없기 때문에 검사도 생략된다.

---

### GA 태그 컨테이너를 검사 대상과 실행 경로 기준으로 어떻게 선택해야 하는가?

| 태그 컨테이너 | 검사 대상 | 실행 경로 | 사용 예시 |
|---|---|---|---|
| `ActivationRequired/BlockedTags` | Owner (자신) | 직접·이벤트 모두 | 스턴 상태일 때 능력 차단 |
| `SourceRequired/BlockedTags` | Source (이벤트 발신자) | 이벤트 트리거만 | 소총 GA가 보낸 이벤트일 때만 처리 |
| `TargetRequired/BlockedTags` | Target (이벤트 대상) | 이벤트 트리거만 | 대상이 경직 상태일 때만 처형기 발동 |
