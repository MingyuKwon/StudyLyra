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

| 문서 | 내용 |
|------|------|
| [GAS 개요](doc/gas/README.md) | GAS란, 핵심 구성요소, Lyra 전체 흐름 |
| [AbilitySystemComponent](doc/gas/ability_system_component/README.md) | ASC 역할, Owner/Avatar, 초기화, 입력 바인딩, ActivationGroup |
| [GameplayAbility](doc/gas/gameplay_ability/README.md) | GA 생명주기, ActivationPolicy, Instancing, Cost, 태그 조건 |
| [GameplayEffect](doc/gas/gameplay_effect/README.md) | GE 타입, Modifier/MMC, 태그/스택, GESpec/SetByCaller |
| [AttributeSet](doc/gas/attribute_set/README.md) | Attribute 타입, Base/Current, Meta Attribute, Lyra 구현 |
| [GameplayTag](doc/gas/gameplay_tag/README.md) | 태그 계층, GAS 역할, TagRelationshipMapping |
| [GameplayCue](doc/gas/gameplay_cue/README.md) | Cue 트리거, Static/Actor, LyraGameplayCueManager |
| [AbilityTask](doc/gas/ability_task/README.md) | Task 생명주기, 사용 패턴, GrantNearbyInteraction |
| [Execution Calculation](doc/gas/execution_calculation/README.md) | ExecCalc 구조, Attribute Capture, LyraDamageExecution |
| [네트워크 & Prediction](doc/gas/network_prediction/README.md) | 복제 구조, Prediction Key, 예측 가능/불가 목록 |

---

## 언리얼 코어 분석

| 문서 | 내용 |
|------|------|
| [입력 파이프라인](doc/unrealCore/input_pipeline.md) | PlayerTick → ProcessInputStack 전체 흐름, Accumulator 패턴, bDown 홀드 원리 |
