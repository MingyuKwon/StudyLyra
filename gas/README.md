# GAS (Gameplay Ability System) 학습 노트

언리얼 엔진 GAS의 개념과 동작 원리를 주제별로 정리한 문서 모음.
Lyra 구현 분석은 [doc/](../doc/README.md) 폴더 참고.

---

## 문서 목록

| 문서 | 내용 | 상태 |
|------|------|------|
| [01. GAS 개요](01_overview.md) | GAS란 무엇인가, 핵심 구성요소, 전체 흐름 | |
| [02. AbilitySystemComponent](02_ability_system_component.md) | ASC의 역할, Owner/Avatar 구조, 초기화 | |
| [03. GameplayAbility](03_gameplay_ability.md) | GA 생명주기, 활성화 조건, Instancing Policy | |
| [04. GameplayEffect](04_gameplay_effect.md) | GE 종류(Instant/Duration/Infinite), Modifier, Stack | |
| [05. Attribute & AttributeSet](attribute/README.md) | Attribute 타입, BaseValue/CurrentValue, Meta Attribute, 파생 Attribute | |
| [06. GameplayTag](06_gameplay_tag.md) | 태그 계층 구조, 태그 기반 조건, 태그 이벤트 | |
| [07. GameplayCue](07_gameplay_cue.md) | Cue 트리거 방식, Cue Manager, 네트워크 처리 | |
| [08. AbilityTask](08_ability_task.md) | Task 생명주기, 비동기 작업 패턴, 커스텀 Task | |
| [09. Execution Calculation](09_execution_calculation.md) | ExecCalc 구조, Capture Attribute, 데미지 계산 | |
| [10. 네트워크 & Prediction](10_network_prediction.md) | 복제 구조, Prediction Key, 클라이언트 예측 | |
