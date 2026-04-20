# GameplayAbility (GA)

> 소스: `LyraGameplayAbility.h/cpp`, `LyraAbilitySet.h/cpp`

GA는 캐릭터가 수행하는 **하나의 능력 단위**다. 공격, 점프, 회피, 상호작용, 사망 처리 등 모든 능력이 GA로 구현된다.

---

## 문서 목록

| 문서 | 내용 |
|---|---|
| [01. 생명주기](01_lifecycle.md) | OnGiveAbility, ActivateAbility, EndAbility, 주요 콜백 |
| [02. ActivationPolicy](02_activation_policy.md) | OnInputTriggered / WhileInputActive / OnSpawn |
| [03. Instancing & Net Policy](03_instancing_net.md) | Instancing Policy, Net Execution Policy |
| [04. Cost & AdditionalCost](04_cost.md) | GE Cost, ULyraAbilityCost, ShouldOnlyApplyCostOnHit |
| [05. 태그 조건 (9가지)](05_tag_conditions.md) | GA 태그 컨테이너 + TagRelationshipMapping 확장 |
| [06. Lyra 구현 예시](06_examples.md) | Death, Jump, FromEquipment, GamePhaseAbility |
| [07. 태그 기반 차단/취소 플로우](07_block_cancel_flow.md) | BlockedAbilityTags 카운터, CancelAbilities, ApplyAbilityBlockAndCancelTags 생애주기 |

---

## 클래스 계층

```
UObject
    └── UGameplayAbility  (엔진 기본)
            └── ULyraGameplayAbility  (Lyra 공통 베이스)
                    ├── ULyraGameplayAbility_Death
                    ├── ULyraGameplayAbility_Jump
                    ├── ULyraGameplayAbility_FromEquipment
                    │       └── ULyraGameplayAbility_RangedWeapon
                    └── ULyraGamePhaseAbility
```

---

## 기본 설정값 (생성자)

```cpp
ULyraGameplayAbility::ULyraGameplayAbility(...)
{
    ReplicationPolicy  = EGameplayAbilityReplicationPolicy::ReplicateNo;  // 복제 안 함
    InstancingPolicy   = EGameplayAbilityInstancingPolicy::InstancedPerActor;  // ASC당 1개
    NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::LocalPredicted;   // 클라이언트 예측
    NetSecurityPolicy  = EGameplayAbilityNetSecurityPolicy::ClientOrServer;

    ActivationPolicy = ELyraAbilityActivationPolicy::OnInputTriggered;
    ActivationGroup  = ELyraAbilityActivationGroup::Independent;
}
```
