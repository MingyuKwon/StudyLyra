# GAS 개요

> 참고: [GAS Doc 캐시](cache/gas_doc_cache.md) | [Lyra 소스 분석](../memory/lyra_gas_analysis.md)

---

## GAS란

GAS(Gameplay Ability System)는 언리얼 엔진 공식 플러그인으로, 캐릭터가 사용할 **능력(Ability)**, **효과(Effect)**, **속성(Attribute)** 을 구조적으로 관리하는 시스템이다.

단순한 데미지 처리나 입력 처리를 넘어, 멀티플레이어 예측(Prediction), 네트워크 복제(Replication), 상태 관리, 비동기 작업까지 하나의 프레임워크로 통합한다.

---

## 핵심 구성요소

| 구성요소 | 약어 | 역할 |
|---|---|---|
| [AbilitySystemComponent](asc/README.md) | ASC | 모든 GAS 기능의 허브. Owner Actor에 붙음 |
| [GameplayAbility](ga/README.md) | GA | 하나의 능력 (공격, 점프, 스킬 등) |
| [GameplayEffect](ge/README.md) | GE | 속성(Attribute)을 수정하는 규칙. 지속시간/즉시/무한 |
| [AttributeSet](attribute/README.md) | - | 체력, 데미지 등 수치 데이터 묶음 |
| AbilityTask | AT | GA 내부에서 비동기 작업 처리 |
| [GameplayCue](cue/README.md) | GC | 시각/사운드 이펙트 전담. 게임플레이 로직과 분리 |
| [GameplayTag](tag/README.md) | GT | 계층형 문자열 태그. 상태, 조건, 식별자로 사용 |

---

## 전체 흐름

```
[입력 발생]
    │
    ▼
ULyraAbilitySystemComponent::AbilityInputTagPressed(InputTag)
    │ InputTag를 가진 AbilitySpec을 InputPressedSpecHandles에 추가
    │
    ▼
ULyraAbilitySystemComponent::ProcessAbilityInput()  ← 매 프레임 호출
    │ ActivationPolicy == OnInputTriggered → TryActivateAbility()
    │ ActivationPolicy == WhileInputActive → 입력 유지 중 계속 시도
    │
    ▼
UGameplayAbility::CanActivateAbility()
    │ 태그 조건, ActivationGroup 차단 여부, Cost 확인
    │
    ▼
UGameplayAbility::ActivateAbility()
    │ 실제 능력 로직 실행 (대부분 AbilityTask 시작)
    │
    ▼
[GE 적용] → AttributeSet::PostGameplayEffectExecute() → 속성 변화
    │
    ▼
[GameplayCue 트리거] → 사운드/파티클 재생 (게임플레이 로직과 무관)
```

---

## Lyra에서의 구현 패턴

### Owner/Avatar 분리

```
ALyraPlayerState          → ASC 소유자(Owner) + IAbilitySystemInterface 구현
    │ owns
    ▼
ULyraAbilitySystemComponent   → GAS의 핵심 ASC
    │ avatar =
    ▼
ALyraCharacter            → 실제 게임 세계의 Pawn(Avatar)
```

리스폰 시 PlayerState는 유지되므로 ASC와 모든 Attribute 상태가 보존된다.

### AbilitySet — 부여 단위

`ULyraAbilitySet`은 GA + GE + AttributeSet을 하나로 묶은 DataAsset.
- `GiveToAbilitySystem()` 한 번 호출로 세 가지를 모두 부여
- 반환된 `FLyraAbilitySet_GrantedHandles`로 나중에 일괄 제거 가능
- 장비 장착/해제, ExperienceDefinition 로드 시 사용됨

```cpp
// 장비 장착 시
AbilitySet->GiveToAbilitySystem(LyraASC, &OutGrantedHandles, EquipmentInstance);

// 장비 해제 시
OutGrantedHandles.TakeFromAbilitySystem(LyraASC);
```

### Pawn 초기화 조율

`ULyraPawnExtensionComponent`가 `IGameFrameworkInitStateInterface`를 구현해
여러 컴포넌트의 초기화 순서를 관리한다.

```
InitState_Spawned
    → InitState_DataAvailable  (PawnData 준비됨, Controller 보유)
    → InitState_DataInitialized (모든 Feature가 DataAvailable 도달)
    → InitState_GameplayReady  (AbilitySystem 초기화 완료)
```

`DataInitialized` 단계에서 `InitializeAbilitySystem()` 호출 → `InitAbilityActorInfo()` 실행.

---

## 관련 문서

- [ASC 상세](asc/README.md)
- [GA 상세](ga/README.md)
- [GE 상세](ge/README.md)
- [Attribute & AttributeSet](attribute/README.md)
- [GameplayTag](tag/README.md)
- [GameplayCue](cue/README.md)
- [AbilityTask](task/README.md)
- [ExecCalc](exec/README.md)
- [네트워크 & Prediction](network/README.md)
