# GAS 학습 노트 — Zhi Kang Shao 기반

> 출처: Zhi Kang Shao — "Gameplay Ability System: Best Practices for Setup"
> 원문: https://dev.epicgames.com/community/learning/tutorials/DPpd/unreal-engine-gameplay-ability-system-best-practices-for-setup
> 게시일: 2025.04.17 (Epic Developer Community)

> tranek 기반 정리: [GAS 학습 노트 — tranek](../gas_tranek/README.md)

> **작성 규칙**: 원문이 영어로 주어져도 내용은 **한국어**로 번역하여 작성한다.

---

## 이 문서에 대해

GAS(Gameplay Ability System)는 게임플레이 관련 값과 동작을 체계적으로 구성하기 위한 프레임워크다. 편리한 에디팅, 데이터 기반 상호작용, 상태 및 동작 복제, 기본 제공 디버깅 도구를 지원한다. GAS는 Gameplay Abilities 플러그인을 활성화하여 프로젝트에 추가한다. 데미지/체력, 동적 무기 발사 속도 및 재장전 속도, 이동 변수 변경, Pawn 능력 활성화/비활성화, Pawn-환경 상호작용 등 다양한 기능 구현에 활용할 수 있다. Epic의 자체 게임인 Fortnite Battle Royale, LEGO Fortnite에서도 사용하는 검증된 시스템이다.

이 문서는 프로젝트에 GAS를 셋업할 때 발생하는 여러 질문들을 다룬다. 최선의 방법은 프로젝트마다 다르므로 고려해야 할 사항들을 제시하는 형식으로 구성된다. Lyra Starter Game을 자주 참조하므로 Lyra 프로젝트 파일을 받아두면 좋다. 여기서 다루는 Best Practice는 싱글플레이어와 네트워크 멀티플레이어 게임 모두에 적용된다.

---

## 목차

| 파일 | 내용 |
|------|------|
| [01 Ability System Component](01_ability_system_component.md) | ASC를 붙일 수 있는 Actor, 복수 ASC 금지 이유 |
