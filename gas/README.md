# GAS (Gameplay Ability System) 학습 노트

언리얼 엔진 GAS의 개념과 동작 원리를 주제별로 정리한 문서 모음.
엔진 이론([GAS Doc 캐시](gas_doc_cache.md))과 Lyra 소스 코드 구현을 매칭해 설명한다.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. GAS 개요](01_overview.md) | GAS란, 핵심 구성요소, Lyra 전체 흐름 |
| [02. AbilitySystemComponent](asc/README.md) | ASC 역할, Owner/Avatar, 초기화, 입력 바인딩, ActivationGroup |
| [03. GameplayAbility](ga/README.md) | GA 생명주기, ActivationPolicy, Instancing, Cost, 태그 조건, 예시 |
| [04. GameplayEffect](ge/README.md) | GE 타입, Modifier/MMC, 태그/스택, GESpec/SetByCaller |
| [05. Attribute & AttributeSet](attribute/README.md) | Attribute 타입, Base/Current, Meta Attribute, Lyra 구현 |
| [06. GameplayTag](06_gameplay_tag.md) | 태그 계층, GAS 역할, TagRelationshipMapping |
| [07. GameplayCue](07_gameplay_cue.md) | Cue 트리거, Static/Actor, LyraGameplayCueManager, 네트워크 |
| [08. AbilityTask](08_ability_task.md) | Task 생명주기, 사용 패턴, GrantNearbyInteraction 예시 |
| [09. Execution Calculation](09_execution_calculation.md) | ExecCalc 구조, Attribute Capture, LyraDamageExecution 전체 |
| [10. 네트워크 & Prediction](10_network_prediction.md) | 복제 구조, Prediction Key, 예측 가능/불가 목록 |

---

## 폴더 구조

```
gas/
├── README.md                      ← 이 파일
├── gas_doc_cache.md               ← GASDocumentation(tranek) 전체 요약 캐시
├── 01_overview.md                 ← GAS 개요 + Lyra 아키텍처
├── 02_ability_system_component.md ← → asc/ 리다이렉트
├── 03_gameplay_ability.md         ← → ga/ 리다이렉트
├── 04_gameplay_effect.md          ← → ge/ 리다이렉트
├── 06_gameplay_tag.md
├── 07_gameplay_cue.md
├── 08_ability_task.md
├── 09_execution_calculation.md
├── 10_network_prediction.md
│
├── asc/                           ← ASC 상세 (5개 주제)
│   ├── README.md
│   ├── 01_owner_avatar.md
│   ├── 02_initialization.md
│   ├── 03_input_binding.md
│   └── 04_activation_group.md
│
├── ga/                            ← GameplayAbility 상세 (6개 주제)
│   ├── README.md
│   ├── 01_lifecycle.md
│   ├── 02_activation_policy.md
│   ├── 03_instancing_net.md
│   ├── 04_cost.md
│   ├── 05_tag_conditions.md
│   └── 06_examples.md
│
├── ge/                            ← GameplayEffect 상세 (4개 주제)
│   ├── README.md
│   ├── 01_types.md
│   ├── 02_modifiers_mmc.md
│   ├── 03_tags_stacking.md
│   └── 04_spec_setbycaller.md
│
└── attribute/                     ← AttributeSet 상세 (8개 주제)
    ├── README.md
    ├── 01_attribute_types.md
    ├── 02_base_current_value.md
    ├── 03_accessors_and_clamp.md
    ├── 04_meta_attribute.md
    ├── 05_derived_attribute.md
    ├── 06_lyra_usage.md
    ├── 07_asc_registration.md
    └── 08_attributeset_guide.md
```

---

## 참고 자료

- [GASDocumentation(tranek)](gas_doc_cache.md) — 엔진 GAS 이론 전체
- [Lyra 소스 분석 캐시](../memory/lyra_gas_analysis.md) — 소스 직접 확인 내용
- [프로젝트 개요](../memory/project_overview.md)
