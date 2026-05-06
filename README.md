Lyra Sample Game
===

Content Information
----
When downloading Lyra Source code from git, the content folders are not included.

To make use of the Lyra source code, you will need to download the content from the Unreal Marketplace through the Epic Games Launcher.

For more information please visit the [Unreal Engine Lyra documentation](https://docs.unrealengine.com/5.0/en-US/lyra-sample-game-in-unreal-engine/)

Once installed, copy the "Content" folder and any other folders named "Content" from the Marketplace project you downloaded to the project in your solution, and you should be good to go.


Additional Information
----
See the [Unreal Engine README](../../../README.md) at the root of the repository for [Licensing](../../../README.md#licensing) and [Contributing](../../../README.md#contributions) information.


---

GAS 학습 분석
===

언리얼 엔진 Lyra 스타터 게임을 통해 GAS(Gameplay Ability System)를 완벽 학습하기 위한 분석 프로젝트.

## 문서 모음

| 폴더 | 내용 |
|------|------|
| [doc/gas/](doc/gas/) | GAS 개념 학습 노트 (원리, API, 동작 방식) |
| [doc/unrealCore/](doc/unrealCore/) | 언리얼 엔진 코어 시스템 분석 (입력 파이프라인 등) |
| [doc/LyraImpl/](doc/LyraImpl/) | Lyra 소스 코드 구현 분석 (입력, 시스템 흐름 등) |
| [memory/](memory/) | 세션 간 지속 캐시 (소스 분석 결과, 프로젝트 개요) |

---

## GAS 학습 문서

> 상세 인덱스: [doc/gas/README.md](doc/gas/README.md)

| 폴더 | GASDoc | 내용 |
|------|--------|------|
| [AbilitySystemComponent](doc/gas/ability_system_component/README.md) | 4.1 | ASC 역할, Replication Mode, 초기화 |
| [GameplayTag](doc/gas/gameplay_tag/README.md) | 4.2 | 태그 계층, 변화 감지 |
| [Attribute](doc/gas/attribute/README.md) | 4.3 | Attribute 타입, Base/Current, Meta |
| [AttributeSet](doc/gas/attribute_set/README.md) | 4.4 | AttributeSet 설계, 콜백 |
| [GameplayEffect](doc/gas/gameplay_effect/README.md) | 4.5 | GE 타입, Modifier, MMC, ExecCalc |
| [GameplayAbility](doc/gas/gameplay_ability/README.md) | 4.6 | GA 생명주기, 입력, 태그 |
| [AbilityTask](doc/gas/ability_task/README.md) | 4.7 | Task 생명주기, 커스텀 |
| [GameplayCue](doc/gas/gameplay_cue/README.md) | 4.8 | Cue 트리거, Manager |
| [AbilitySystemGlobals](doc/gas/ability_system_globals/README.md) | 4.9 | 전역 설정, InitGlobalData |
| [NetworkPrediction](doc/gas/network_prediction/README.md) | 4.10 | Prediction Key, Window |
| [Targeting](doc/gas/targeting/README.md) | 4.11 | TargetData, TargetActor |
| [공통 패턴](doc/gas/common_patterns/README.md) | 5 | Stun, Sprint, Lifesteal 등 구현 예시 |

---

## 언리얼 코어 분석

> 상세 인덱스: [doc/unrealCore/README.md](doc/unrealCore/README.md)

| 문서/폴더 | 내용 |
|-----------|------|
| [UObject](doc/unrealCore/uobject/README.md) | GC, CDO, DefaultSubobject, IsValid/MarkAsGarbage, Blueprint Asset |
| [Actor](doc/unrealCore/actor/README.md) | Actor·Component 개념, SpawnActor, 생명주기 |
| [Collision](doc/unrealCore/collision/README.md) | Block/Overlap/Ignore, CollisionEnabled 종류, 성능 최적화 |
| [입력 파이프라인](doc/unrealCore/input_pipeline.md) | PlayerTick → ProcessInputStack 전체 흐름, Accumulator 패턴, bDown 홀드 원리 |
| [Enhanced Input](doc/unrealCore/enhanced_input.md) | IMC 관리(UEnhancedInputLocalPlayerSubsystem) vs Action 바인딩(UEnhancedInputComponent) 역할 분리 |
| [Slate](doc/unrealCore/slate/README.md) | Slate UI 프레임워크 기초 — SWidget 계층, TSharedRef 메모리 모델, 레이아웃 시스템, 선언형 문법 |
| [UMG](doc/unrealCore/umg/README.md) | UMG — UWidget 계층, UUserWidget 생명주기, 뷰포트 추가/제거, BindWidget |
| [UI 파이프라인](doc/unrealCore/ui_pipeline.md) | Slate/UMG 렌더 흐름, TakeWidget 브릿지, Prepass/OnPaint 두 단계 Pass |
| [월드 프레임워크](doc/unrealCore/world_framework.md) | UWorld · AWorldSettings · GameMode · GameState 역할 구분, 생성 체인 |
| [플레이어 프레임워크](doc/unrealCore/player_framework.md) | PlayerController · LocalPlayer 생존 범위 차이, 분리 이유, 스플릿스크린 |
| [PredictionKey](doc/unrealCore/prediction_key.md) | FPredictionKey 구조, 예측 윈도우 수명, Reject/CatchUp 두 종료 경로, NetSerialize |
| [복제 시스템](doc/unrealCore/replication/README.md) | NetDriver 파이프라인, Actor 복제, Shadow Buffer, Relevancy, NetSerialize |
| [엔진 플러그인](doc/unrealCore/plugin/README.md) | ModularGameplay, GameFeatures, CommonUser, GameplayMessage 분석 |

---

## GAS 레퍼런스

| 문서 | 내용 |
|------|------|
| [디버깅](doc/gas/reference/debugging.md) | showdebug abilitysystem, GAS 로그, 콘솔 명령 |
| [최적화](doc/gas/reference/optimization.md) | ASC Replication Mode, GC 최적화 패턴 |
| [Quality of Life](doc/gas/reference/quality_of_life.md) | Batch GE, Generic Tag Response, FGameplayEffectContextHandle 확장 |
| [ASC Replicated Containers](doc/gas/reference/asc_replicated_containers.md) | FActiveGameplayEffectsContainer, FGameplayAbilitySpecContainer 복제 구조 |
| [Dave Ratti Q&A](doc/gas/reference/dave_ratti_qa.md) | GAS 개발자 Dave Ratti의 공식 Q&A 정리 |
| [트러블슈팅](doc/gas/reference/troubleshooting.md) | 흔한 GAS 오류 및 해결책 |
