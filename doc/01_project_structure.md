# 프로젝트 전체 구조

## 소스 모듈

| 모듈 | 설명 |
|------|------|
| `Source/LyraGame` | 메인 게임 모듈 (GAS 전체 구현 포함) |
| `Source/LyraEditor` | 에디터 전용 커맨드렛 및 유틸리티 |

## GameFeatures 플러그인

| 플러그인 | 설명 |
|----------|------|
| `ShooterCore` | 슈터 게임 핵심 로직 |
| `ShooterMaps` | 슈터 맵 정의 |
| `ShooterExplorer` | 탐색 모드 |
| `ShooterTests` | 자동화 테스트 |
| `TopDownArena` | 탑다운 아레나 게임모드 |

## LyraGame 하위 폴더 구조

```
Source/LyraGame/
├── AbilitySystem/          # GAS 핵심 구현
│   ├── Abilities/          # GameplayAbility 클래스들
│   ├── Attributes/         # AttributeSet 클래스들
│   ├── Executions/         # GameplayEffectExecutionCalculation
│   └── Phases/             # 게임 페이즈 시스템
├── Character/              # Pawn / Character / 관련 컴포넌트
├── Equipment/              # 장비 시스템 (GAS 연동)
├── Weapons/                # 무기 시스템 (GAS 연동)
├── Inventory/              # 인벤토리 시스템
├── Interaction/            # 인터랙션 시스템 (AbilityTask 포함)
├── Input/                  # 입력 설정 (InputTag ↔ Ability 연결)
├── GameModes/              # Experience 기반 게임모드
├── GameFeatures/           # GameFeatureAction 구현
├── Player/                 # PlayerState, PlayerController
├── Teams/                  # 팀 시스템
├── Camera/                 # 카메라 모드 시스템
└── System/                 # AssetManager, GameInstance 등
```
