# GameplayEffect (GE)

> 참고: [GAS Doc 캐시](../cache/gas_doc_cache.md) | 소스: `LyraDamageExecution.cpp`, `LyraAbilitySet.cpp`

GE는 **Attribute를 수정하는 규칙**이다. 지속 시간, 수정 방법, 조건, 스택 등을 정의하는 DataAsset.

GA는 GE를 통해 데미지, 체력 회복, 버프, 디버프, 상태 태그 부여 등 모든 수치 변경을 처리한다.

---

## 문서 목록

| 문서 | 내용 |
|---|---|
| [01. 지속 타입](01_types.md) | Instant / Duration / Infinite, Periodic |
| [02. Modifier & MMC](02_modifiers_mmc.md) | 4가지 Op, Aggregator, MMC |
| [03. 태그 & 스택](03_tags_stacking.md) | 7가지 GE 태그, Stacking, Immunity |
| [04. GESpec & SetByCaller](04_spec_setbycaller.md) | GESpec 생성, SetByCaller, EffectContext |

---

## GE와 Attribute 수정 흐름

```
GE 적용 (ApplyGameplayEffectSpecToSelf)
    │
    ├─ Instant GE → BaseValue 영구 변경
    │   └─ PreAttributeBaseChange() → [값 반영] → PostAttributeChange()
    │
    └─ Duration/Infinite GE → Aggregator에 Modifier 등록
        └─ PreAttributeChange() → [CurrentValue 재계산] → PostAttributeChange()
```

---

## Lyra에서의 GE 사용 패턴

### AbilitySet을 통한 GE 부여

```cpp
// ULyraAbilitySet::GiveToAbilitySystem()에서
const UGameplayEffect* GameplayEffect = EffectToGrant.GameplayEffect->GetDefaultObject<UGameplayEffect>();
const FActiveGameplayEffectHandle Handle = LyraASC->ApplyGameplayEffectToSelf(
    GameplayEffect, EffectToGrant.EffectLevel, LyraASC->MakeEffectContext());
```

### 데미지 GE (ExecCalc 기반)

```
DamageGameplayEffect
    ├── Duration: Instant
    └── Executions: ULyraDamageExecution
            └── BaseDamage (CombatSet) → Damage (HealthSet Meta)
                → PostGameplayEffectExecute → Health 감소
```

### 상태 태그 부여 GE

```
StunGameplayEffect
    ├── Duration: Duration (N초)
    └── Granted Tags: Status.Debuff.Stun
```

Duration이 끝나면 `Status.Debuff.Stun` 태그가 자동 제거된다.
