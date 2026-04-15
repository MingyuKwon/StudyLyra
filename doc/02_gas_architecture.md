# GAS 아키텍처

## ASC 소유 구조

Lyra는 ASC를 PlayerState에 두는 표준 멀티플레이어 패턴을 사용한다.

```
ALyraPlayerState  ──소유──▶  ULyraAbilitySystemComponent
        │                              │
        │                              ▼ (Avatar Actor)
        └──────────▶  ALyraCharacter (Pawn)
```

- **ASC 소유자 (Owner)**: `ALyraPlayerState` — `IAbilitySystemInterface` 구현, ASC의 수명 관리
- **ASC 아바타 (Avatar)**: `ALyraCharacter` — 실제 게임 월드의 표현체
- **ASC 클래스**: `ULyraAbilitySystemComponent`

## 핵심 GAS 클래스 목록

### AbilitySystemComponent

| 클래스 | 역할 |
|--------|------|
| `ULyraAbilitySystemComponent` | 베이스 ASC. 입력 태그 처리, ActivationGroup 관리, TagRelationshipMapping 적용 |
| `ULyraAbilitySet` | DataAsset. Ability + Effect + AttributeSet을 묶어서 한 번에 부여/제거 |
| `ULyraAbilityTagRelationshipMapping` | 태그 기반 Ability 간 블록/캔슬 관계 테이블 |
| `ULyraGameplayCueManager` | GameplayCue 로딩 최적화 |
| `ULyraGameplayEffectContext` | EffectContext 확장 (AbilitySource, HitResult 등) |
| `ULyraGlobalAbilitySystem` | 모든 ASC에 글로벌 Ability/Effect 일괄 적용 |

### GameplayAbility

| 클래스 | 역할 |
|--------|------|
| `ULyraGameplayAbility` | 베이스 GA. ActivationPolicy / ActivationGroup / AdditionalCosts 개념 추가 |
| `ULyraGameplayAbility_Death` | 사망 처리 어빌리티 |
| `ULyraGameplayAbility_Jump` | 점프 어빌리티 |
| `ULyraGameplayAbility_Reset` | 캐릭터 리셋 |
| `ULyraGameplayAbility_FromEquipment` | 장착된 장비 기반 어빌리티 베이스 |
| `ULyraGameplayAbility_RangedWeapon` | 원거리 무기 발사 어빌리티 |
| `ULyraGameplayAbility_Interact` | 인터랙션 어빌리티 |
| `ULyraGamePhaseAbility` | 게임 페이즈 전환 어빌리티 |

**ActivationPolicy (활성화 정책)**

| 값 | 설명 |
|----|------|
| `OnInputTriggered` | 입력 발생 시 한 번 활성화 시도 |
| `WhileInputActive` | 입력 유지 중 지속적으로 활성화 시도 |
| `OnSpawn` | 아바타 설정 시 자동 활성화 |

**ActivationGroup (활성화 그룹)**

| 값 | 설명 |
|----|------|
| `Independent` | 다른 어빌리티와 독립적으로 실행 |
| `Exclusive_Replaceable` | 다른 Exclusive 어빌리티로 대체 가능 |
| `Exclusive_Blocking` | 다른 Exclusive 어빌리티 활성화 차단 |

### AttributeSet

| 클래스 | 어트리뷰트 |
|--------|-----------|
| `ULyraHealthSet` | Health, MaxHealth + Meta(Healing, Damage) |
| `ULyraCombatSet` | 전투 관련 어트리뷰트 |

> **Meta Attribute 패턴**: `Damage`와 `Healing`은 직접 복제되지 않는 임시값으로, `PostGameplayEffectExecute`에서 `Health`에 반영된 후 0으로 초기화된다.

### Execution Calculation

| 클래스 | 역할 |
|--------|------|
| `ULyraDamageExecution` | 데미지 최종 계산 (방어력, 저항 등 적용) |
| `ULyraHealExecution` | 회복량 최종 계산 |

### AbilityTask

| 클래스 | 역할 |
|--------|------|
| `AbilityTask_GrantNearbyInteraction` | 주변 인터랙션 대상에게 GA 부여 |
| `AbilityTask_WaitForInteractableTargets` | 인터랙션 가능 대상 감지 대기 |
