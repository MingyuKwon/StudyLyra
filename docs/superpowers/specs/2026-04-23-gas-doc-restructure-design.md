# Design: doc/gas 폴더 구조 재설계

**날짜**: 2026-04-23  
**목적**: `doc/gas/` 폴더를 GASDocumentation(tranek) README를 뼈대로 삼아 완전히 새로 구성. 각 파일에 GASDoc 요약 + 개인 분석을 함께 담는 구조.

---

## 배경

- 기존 `doc/gas/` 파일들은 삭제하고 새로 시작 (리셋)
- `GASDocument_Readme.md` (3705줄, tranek 원문)가 기준
- 원문 파일은 `cache/` 폴더로 이동 보관

---

## 전체 폴더 구조

```
doc/gas/
├── README.md                        ← 전체 인덱스
├── cache/
│   ├── GASDocument_Readme.md        ← 원문 (이동)
│   └── gas_doc_cache.md             ← 기존 요약 (유지)
│
├── 00_intro_setup.md                ← GASDoc 1~3
│
├── ability_system_component/        ← 4.1
├── gameplay_tag/                    ← 4.2
├── attribute/                       ← 4.3 (신규)
├── attribute_set/                   ← 4.4
├── gameplay_effect/                 ← 4.5
├── gameplay_ability/                ← 4.6
├── ability_task/                    ← 4.7
├── gameplay_cue/                    ← 4.8
├── ability_system_globals/          ← 4.9 (신규)
├── network_prediction/              ← 4.10
├── targeting/                       ← 4.11 (신규)
│
├── common_patterns/                 ← GASDoc 5
│
└── reference/                       ← GASDoc 6~11
    ├── debugging.md
    ├── optimization.md
    ├── quality_of_life.md
    ├── troubleshooting.md
    └── dave_ratti_qa.md
```

---

## 폴더별 파일 목록

### ability_system_component/ (GASDoc 4.1)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.1 개요 |
| 01_replication_mode.md | 4.1.1 |
| 02_setup_initialization.md | 4.1.2 |

### gameplay_tag/ (GASDoc 4.2)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 인덱스 (링크 목록) |
| 01_basics.md | 4.2 개요 |
| 02_responding_to_changes.md | 4.2.1 |
| 03_loading_from_plugin.md | 4.2.2 |

### attribute/ (GASDoc 4.3) — 신규
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.3 개요 |
| 01_definition.md | 4.3.1 |
| 02_base_current_value.md | 4.3.2 |
| 03_meta_attribute.md | 4.3.3 |
| 04_responding_to_changes.md | 4.3.4 |
| 05_derived_attribute.md | 4.3.5 |

### attribute_set/ (GASDoc 4.4)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.4 개요 |
| 01_definition_design.md | 4.4.1~4.4.2 |
| 02_item_attributes.md | 4.4.2.3 |
| 03_defining_initializing.md | 4.4.3~4.4.4 |
| 04_pre_attribute_change.md | 4.4.5 |
| 05_post_ge_execute.md | 4.4.6 |
| 06_aggregator_created.md | 4.4.7 |

### gameplay_effect/ (GASDoc 4.5)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.5 개요 |
| 01_definition.md | 4.5.1 |
| 02_apply_remove.md | 4.5.2~3 |
| 03_modifiers.md | 4.5.4 |
| 04_stacking_tags_immunity.md | 4.5.5, 4.5.7, 4.5.8 |
| 05_spec_setbycaller.md | 4.5.9 |
| 06_context.md | 4.5.10 |
| 07_mmc.md | 4.5.11 |
| 08_execution_calculation.md | 4.5.12 |
| 09_cost_cooldown.md | 4.5.13~4.5.15 |
| 10_advanced.md | 4.5.16~4.5.18 |

### gameplay_ability/ (GASDoc 4.6)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.6 개요 |
| 01_definition.md | 4.6.1 |
| 02_input_binding.md | 4.6.2 |
| 03_granting_activating.md | 4.6.3~4.6.4 |
| 04_cancel_get_active.md | 4.6.5~4.6.6 |
| 05_instancing_net.md | 4.6.7~4.6.8 |
| 06_tags.md | 4.6.9 |
| 07_spec_data.md | 4.6.10~4.6.11 |
| 08_cost_cooldown.md | 4.6.12 |
| 09_advanced.md | 4.6.13~4.6.16 |

### ability_task/ (GASDoc 4.7)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.7 개요 |
| 01_definition.md | 4.7.1 |
| 02_custom_task.md | 4.7.2 |
| 03_using.md | 4.7.3 |
| 04_root_motion.md | 4.7.4 |

### gameplay_cue/ (GASDoc 4.8)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.8 개요 |
| 01_definition_trigger.md | 4.8.1~4.8.2 |
| 02_local_params.md | 4.8.3~4.8.4 |
| 03_manager_prevention.md | 4.8.5~4.8.6 |
| 04_batching.md | 4.8.7 |
| 05_events_reliability.md | 4.8.8~4.8.9 |

### ability_system_globals/ (GASDoc 4.9) — 신규
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.9 전체 (4.9.1 포함) |

### network_prediction/ (GASDoc 4.10)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.10 개요 |
| 01_prediction_key.md | 4.10.1 |
| 02_prediction_windows.md | 4.10.2~4.10.3 |
| 03_future_npp.md | 4.10.4~4.10.5 |

### targeting/ (GASDoc 4.11) — 신규
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 4.11 개요 |
| 01_target_data.md | 4.11.1 |
| 02_target_actors.md | 4.11.2 |
| 03_filters_reticles.md | 4.11.3~4.11.4 |
| 04_containers.md | 4.11.5 |

### common_patterns/ (GASDoc 5)
| 파일 | GASDoc 섹션 |
|------|------------|
| README.md | 5 개요 |
| 01_stun_sprint_ads.md | 5.1~5.3 |
| 02_lifesteal_crit.md | 5.4, 5.6 |
| 03_misc.md | 5.5, 5.7~5.9 |

### reference/ (GASDoc 6~11)
| 파일 | GASDoc 섹션 |
|------|------------|
| debugging.md | 6 |
| optimization.md | 7 |
| quality_of_life.md | 8 |
| troubleshooting.md | 9 |
| dave_ratti_qa.md | 11 |

---

## README.md 역할 정의

- **각 폴더의 README.md**: 인덱스 전용 — 폴더 내 파일 링크 목록만 포함, 내용 없음
- **예외**: `ability_system_globals/README.md` — 하위 섹션이 4.9.1 하나뿐이라 README가 내용도 겸함

---

## 파일 내부 형식 (템플릿)

```markdown
# [제목]

> **GASDoc**: 4.5.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

[GASDoc 핵심 내용을 한국어로 압축 요약]

---

## 내 분석

[Lyra 코드 연결, 직접 실험/분석, 개인적 이해, 주의사항]
```

**규칙:**
- `개념 요약` — GASDoc 내용을 한국어로 압축. 원문 번역이 아닌 핵심 추출.
- `내 분석` — 처음엔 비워두고 나중에 채우는 공간.
- GASDoc 섹션 번호는 헤더 아래 레퍼런스 줄에 명시.

---

## 기존 파일 처리

- `doc/gas/` 내 기존 폴더/파일 전체 삭제 (리셋)
- 예외: `cache/gas_doc_cache.md` 유지
- `GASDocument_Readme.md` → `cache/GASDocument_Readme.md` 이동

---

## 구현 순서

1. `cache/` 정리 (GASDocument_Readme.md 이동, gas_doc_cache.md 유지)
2. 기존 파일/폴더 삭제
3. 새 폴더 생성
4. 각 폴더 README.md 생성
5. 각 폴더 내 번호 파일 생성 (빈 템플릿으로)
6. `doc/gas/README.md` (전체 인덱스) 생성
7. `00_intro_setup.md` 생성
