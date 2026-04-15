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

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 프로젝트 전체 구조](doc/01_project_structure.md) | 소스 모듈, GameFeatures 플러그인, 폴더 트리 |
| [02. GAS 아키텍처](doc/02_gas_architecture.md) | ASC 소유 구조, 핵심 클래스 목록, AttributeSet 패턴 |
| [03. Pawn 초기화 흐름](doc/03_pawn_initialization.md) | PawnData → ASC 생성 → Avatar 등록 → AbilitySet 부여 |
| [04. 입력 → Ability 연결](doc/04_input_ability.md) | InputConfig, HeroComponent, ASC 입력 처리 흐름 |
| [05. Equipment / Weapon GAS 연동](doc/05_equipment_weapon.md) | 장비 장착/해제 시 Ability 부여/제거 패턴 |
| [06. 게임 페이즈 시스템](doc/06_game_phase.md) | GamePhaseAbility, GamePhaseSubsystem |
| [07. GameFeature 기반 Ability 추가](doc/07_game_feature_ability.md) | Experience 로딩 → GameFeature → 동적 Ability 부여 |
