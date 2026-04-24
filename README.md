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

| 문서 | 내용 |
|------|------|
| [입력 파이프라인](doc/unrealCore/input_pipeline.md) | PlayerTick → ProcessInputStack 전체 흐름, Accumulator 패턴, bDown 홀드 원리 |
| [UI 파이프라인](doc/unrealCore/ui_pipeline.md) | Slate/UMG 렌더 흐름, TakeWidget 브릿지, Prepass/OnPaint 두 단계 Pass |
