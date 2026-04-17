# ModularGameplay 플러그인

> 플러그인 경로: `Engine/Plugins/Runtime/ModularGameplay/`

런타임에 Actor에 컴포넌트를 동적으로 주입하고, 여러 컴포넌트의 초기화 순서를 GameplayTag 기반 상태 머신으로 조율하는 UE5 공식 플러그인.

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_component_classes.md](01_component_classes.md) | UGameFrameworkComponent 계층 전체 — UPawnComponent, UControllerComponent, UPlayerStateComponent, UGameStateComponent |
| [02_component_manager.md](02_component_manager.md) | UGameFrameworkComponentManager — 컴포넌트 동적 주입 시스템 |
| [03_init_state.md](03_init_state.md) | InitState 시스템 — IGameFrameworkInitStateInterface + Manager InitState 파트 |
| [04_lyra_usage.md](04_lyra_usage.md) | Lyra 구현체 목록 및 초기화 흐름 |

---

## 핵심 클래스 한눈에 보기

```
UActorComponent
  └─ UGameFrameworkComponent                 ← 게임 프레임워크 Actor용 컴포넌트 베이스
        ├─ UPawnComponent                    → APawn용
        ├─ UControllerComponent              → AController용
        ├─ UPlayerStateComponent             → APlayerState용
        └─ UGameStateComponent               → AGameStateBase용

UGameInstanceSubsystem
  └─ UGameFrameworkComponentManager          ← 컴포넌트 주입 + InitState 조율 (GameInstance당 1개)

UInterface
  └─ IGameFrameworkInitStateInterface        ← Feature 초기화 상태 머신 인터페이스
```
