# 게임 페이즈 시스템

## 개념

Lyra는 게임 진행 단계(페이즈)를 **GameplayAbility로 표현**한다.
페이즈가 활성화된다는 것 = 해당 GA가 실행 중이라는 것이며, GAS의 태그 시스템과 자연스럽게 통합된다.

## 핵심 클래스

| 클래스 | 역할 |
|--------|------|
| `ULyraGamePhaseAbility` | 페이즈를 표현하는 GA 베이스 클래스. GameplayTag로 페이즈 식별 |
| `ULyraGamePhaseSubsystem` | 페이즈 전환 관리. 현재 페이즈 GA 활성/비활성 처리 |

## 동작 흐름

```
ULyraGamePhaseSubsystem::StartPhase(PhaseAbilityClass)
  └─ GameState의 ASC에 PhaseAbility 활성화 요청
        └─ ULyraGamePhaseAbility::ActivateAbility()
              └─ 페이즈 태그 부여 (ASC에 GameplayTag 추가)
                    └─ 이전 페이즈 GA는 태그 충돌로 자동 캔슬
```

## 페이즈 태그 예시

```
GamePhase.WarmUp     ← 워밍업 페이즈 GA 실행 중
GamePhase.Playing    ← 게임 진행 중
GamePhase.PostGame   ← 게임 종료 후
```

페이즈 전환 시 `ActivationGroup = Exclusive_Blocking` 또는 태그 관계를 통해 이전 페이즈가 자동 종료된다.

## GameFeature와의 연동

각 게임모드(ShooterCore, TopDownArena 등)는 자신만의 페이즈 Ability를 정의하고, Experience 로딩 완료 후 첫 페이즈를 시작한다.
