# GAS 학습 노트

> 기반: [GASDocumentation (tranek)](cache/GASDocument_Readme.md)

---

## 개요

| 파일 | GASDoc | 내용 |
|------|--------|------|
| [00 Intro & Setup](00_intro_setup.md) | 1~3 | GAS 소개, 샘플 프로젝트, 셋업 |

---

## GAS 핵심 개념

| 폴더 | GASDoc | 내용 |
|------|--------|------|
| [AbilitySystemComponent](ability_system_component/README.md) | 4.1 | ASC 역할, Replication Mode, 초기화 |
| [GameplayTag](gameplay_tag/README.md) | 4.2 | 태그 계층, 변화 감지 |
| [Attribute](attribute/README.md) | 4.3 | Attribute 타입, Base/Current, Meta |
| [AttributeSet](attribute_set/README.md) | 4.4 | AttributeSet 설계, 콜백 |
| [GameplayEffect](gameplay_effect/README.md) | 4.5 | GE 타입, Modifier, MMC, ExecCalc |
| [GameplayAbility](gameplay_ability/README.md) | 4.6 | GA 생명주기, 입력, 태그 |
| [AbilityTask](ability_task/README.md) | 4.7 | Task 생명주기, 커스텀 |
| [GameplayCue](gameplay_cue/README.md) | 4.8 | Cue 트리거, Manager |
| [AbilitySystemGlobals](ability_system_globals/README.md) | 4.9 | 전역 설정, InitGlobalData |
| [NetworkPrediction](network_prediction/README.md) | 4.10 | Prediction Key, Window |
| [Targeting](targeting/README.md) | 4.11 | TargetData, TargetActor |

---

## 응용 & 참고

| 파일/폴더 | GASDoc | 내용 |
|-----------|--------|------|
| [공통 패턴](common_patterns/README.md) | 5 | Stun, Sprint, Lifesteal 등 구현 예시 |
| [디버깅](reference/debugging.md) | 6 | showdebug, Gameplay Debugger, 로그 |
| [최적화](reference/optimization.md) | 7 | 배칭, ASC Lazy Loading |
| [QoL 제안](reference/quality_of_life.md) | 8 | GEContainers, Blueprint AsyncTask |
| [트러블슈팅](reference/troubleshooting.md) | 9 | 흔한 에러 해결 |
| [Dave Ratti Q&A](reference/dave_ratti_qa.md) | 11 | Epic 개발자 Q&A |
| [ASC 복제 컨테이너](reference/asc_replicated_containers.md) | — | GAS 동기화 데이터 보관소 전체 정리 |
