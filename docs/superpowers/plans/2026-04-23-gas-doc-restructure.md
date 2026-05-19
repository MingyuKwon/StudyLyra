# doc/gas 폴더 구조 재설계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `doc/gas_tranek/` 폴더를 GASDocumentation(tranek)을 뼈대로 삼아 완전히 새 구조로 재편. 각 파일에 GASDoc 요약 + 개인 분석 공간이 있는 템플릿으로 스캐폴딩.

**Architecture:** GASDoc 섹션 번호를 폴더/파일에 매핑. 각 파일은 `## 개념 요약` + `## 내 분석` 두 섹션으로 구성. README.md는 인덱스 전용(링크만), 내용 파일은 번호 접두사 사용.

**Tech Stack:** Markdown, Bash (파일 생성)

---

## Task 1: cache 정리 + 기존 파일 삭제

**Files:**
- Move: `doc/gas_tranek/GASDocument_Readme.md` → `doc/gas_tranek/cache/GASDocument_Readme.md`
- Delete: `doc/gas_tranek/` 내 기존 폴더/파일 (cache 제외)

- [ ] **Step 1: GASDocument_Readme.md를 cache로 이동**

```bash
mv D:/LyraStarterGame/doc/gas_tranek/GASDocument_Readme.md D:/LyraStarterGame/doc/gas_tranek/cache/GASDocument_Readme.md
```

- [ ] **Step 2: cache 보존하면서 나머지 기존 폴더/파일 삭제**

```bash
cd D:/LyraStarterGame/doc/gas
rm -f README.md 00_intro_setup.md
rm -rf ability_system_component ability_task attribute_set execution_calculation gameplay_ability gameplay_cue gameplay_effect gameplay_tag network_prediction
```

- [ ] **Step 3: 삭제 확인**

```bash
ls D:/LyraStarterGame/doc/gas_tranek/
```

기대 결과: `cache/` 폴더만 남아있음

- [ ] **Step 4: cache 안 파일 확인**

```bash
ls D:/LyraStarterGame/doc/gas_tranek/cache/
```

기대 결과: `GASDocument_Readme.md`와 `gas_doc_cache.md` 두 파일

- [ ] **Step 5: Commit**

```bash
cd D:/LyraStarterGame
git add -A doc/gas_tranek/
git commit -m "refactor: doc/gas 기존 파일 삭제 및 GASDocument_Readme 캐시로 이동"
```

---

## Task 2: doc/gas_tranek/README.md + 00_intro_setup.md 생성

**Files:**
- Create: `doc/gas_tranek/README.md`
- Create: `doc/gas_tranek/00_intro_setup.md`

- [ ] **Step 1: doc/gas_tranek/README.md 생성 (전체 인덱스)**

```bash
cat > D:/LyraStarterGame/doc/gas_tranek/README.md << 'EOF'
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
EOF
```

- [ ] **Step 2: 00_intro_setup.md 생성**

```bash
cat > D:/LyraStarterGame/doc/gas_tranek/00_intro_setup.md << 'EOF'
# GAS 소개 & 셋업

> **GASDoc**: 1~3 · [원문 참조](cache/GASDocument_Readme.md)

---

## 개념 요약

### 1. GAS란

### 2. 샘플 프로젝트

### 3. 프로젝트 셋업

---

## 내 분석

EOF
```

- [ ] **Step 3: 파일 확인**

```bash
ls D:/LyraStarterGame/doc/gas_tranek/
```

기대 결과: `README.md`, `00_intro_setup.md`, `cache/`

- [ ] **Step 4: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/README.md doc/gas_tranek/00_intro_setup.md
git commit -m "docs: doc/gas 메인 인덱스 및 intro_setup 스캐폴딩"
```

---

## Task 3: ability_system_component/ 생성 (GASDoc 4.1)

**Files:**
- Create: `doc/gas_tranek/ability_system_component/README.md`
- Create: `doc/gas_tranek/ability_system_component/01_replication_mode.md`
- Create: `doc/gas_tranek/ability_system_component/02_setup_initialization.md`

- [ ] **Step 1: 폴더 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/ability_system_component
```

- [ ] **Step 2: README.md 생성**

```bash
cat > D:/LyraStarterGame/doc/gas_tranek/ability_system_component/README.md << 'EOF'
# Ability System Component (4.1)

> **GASDoc**: 4.1 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 Replication Mode](01_replication_mode.md) | 4.1.1 | Full / Mixed / Minimal |
| [02 Setup & Initialization](02_setup_initialization.md) | 4.1.2 | Owner/Avatar 설정, BeginPlay 초기화 |
EOF
```

- [ ] **Step 3: 01_replication_mode.md 생성**

```bash
cat > D:/LyraStarterGame/doc/gas_tranek/ability_system_component/01_replication_mode.md << 'EOF'
# Replication Mode

> **GASDoc**: 4.1.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
```

- [ ] **Step 4: 02_setup_initialization.md 생성**

```bash
cat > D:/LyraStarterGame/doc/gas_tranek/ability_system_component/02_setup_initialization.md << 'EOF'
# Setup & Initialization

> **GASDoc**: 4.1.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
```

- [ ] **Step 5: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/ability_system_component/
git commit -m "docs: ability_system_component 스캐폴딩 (4.1)"
```

---

## Task 4: gameplay_tag/ 생성 (GASDoc 4.2)

**Files:**
- Create: `doc/gas_tranek/gameplay_tag/README.md`
- Create: `doc/gas_tranek/gameplay_tag/01_basics.md`
- Create: `doc/gas_tranek/gameplay_tag/02_responding_to_changes.md`
- Create: `doc/gas_tranek/gameplay_tag/03_loading_from_plugin.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/gameplay_tag

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_tag/README.md << 'EOF'
# Gameplay Tag (4.2)

> **GASDoc**: 4.2 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 기초](01_basics.md) | 4.2 | 태그 계층, GAS에서 역할 |
| [02 변화 감지](02_responding_to_changes.md) | 4.2.1 | 태그 추가/제거 이벤트 |
| [03 플러그인 로드](03_loading_from_plugin.md) | 4.2.2 | ini 파일에서 태그 등록 |
EOF

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_tag/01_basics.md << 'EOF'
# GameplayTag 기초

> **GASDoc**: 4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_tag/02_responding_to_changes.md << 'EOF'
# 태그 변화 감지

> **GASDoc**: 4.2.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_tag/03_loading_from_plugin.md << 'EOF'
# 플러그인 ini에서 태그 로드

> **GASDoc**: 4.2.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/gameplay_tag/
git commit -m "docs: gameplay_tag 스캐폴딩 (4.2)"
```

---

## Task 5: attribute/ 생성 (GASDoc 4.3)

**Files:**
- Create: `doc/gas_tranek/attribute/README.md`
- Create: `doc/gas_tranek/attribute/01_definition.md`
- Create: `doc/gas_tranek/attribute/02_base_current_value.md`
- Create: `doc/gas_tranek/attribute/03_meta_attribute.md`
- Create: `doc/gas_tranek/attribute/04_responding_to_changes.md`
- Create: `doc/gas_tranek/attribute/05_derived_attribute.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/attribute

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/README.md << 'EOF'
# Attribute (4.3)

> **GASDoc**: 4.3 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의](01_definition.md) | 4.3.1 | FGameplayAttributeData, UPROPERTY |
| [02 Base vs Current](02_base_current_value.md) | 4.3.2 | 두 값의 차이와 용도 |
| [03 Meta Attribute](03_meta_attribute.md) | 4.3.3 | 임시값 패턴 (Damage, Healing) |
| [04 변화 감지](04_responding_to_changes.md) | 4.3.4 | GetGameplayAttributeValueChangeDelegate |
| [05 Derived Attribute](05_derived_attribute.md) | 4.3.5 | 다른 Attribute로부터 계산 |
EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/01_definition.md << 'EOF'
# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/02_base_current_value.md << 'EOF'
# BaseValue vs CurrentValue

> **GASDoc**: 4.3.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/03_meta_attribute.md << 'EOF'
# Meta Attribute

> **GASDoc**: 4.3.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/04_responding_to_changes.md << 'EOF'
# Attribute 변화 감지

> **GASDoc**: 4.3.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute/05_derived_attribute.md << 'EOF'
# Derived Attribute

> **GASDoc**: 4.3.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/attribute/
git commit -m "docs: attribute 스캐폴딩 (4.3)"
```

---

## Task 6: attribute_set/ 생성 (GASDoc 4.4)

**Files:**
- Create: `doc/gas_tranek/attribute_set/README.md`
- Create: `doc/gas_tranek/attribute_set/01_definition_design.md`
- Create: `doc/gas_tranek/attribute_set/02_item_attributes.md`
- Create: `doc/gas_tranek/attribute_set/03_defining_initializing.md`
- Create: `doc/gas_tranek/attribute_set/04_pre_attribute_change.md`
- Create: `doc/gas_tranek/attribute_set/05_post_ge_execute.md`
- Create: `doc/gas_tranek/attribute_set/06_aggregator_created.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/attribute_set

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/README.md << 'EOF'
# AttributeSet (4.4)

> **GASDoc**: 4.4 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의 & 설계](01_definition_design.md) | 4.4.1~2 | AttributeSet 구조, 설계 패턴 |
| [02 아이템 Attribute](02_item_attributes.md) | 4.4.2.3 | 아이템에 Attribute 붙이는 3가지 패턴 |
| [03 선언 & 초기화](03_defining_initializing.md) | 4.4.3~4 | ATTRIBUTE_ACCESSORS, DataTable 초기화 |
| [04 PreAttributeChange](04_pre_attribute_change.md) | 4.4.5 | CurrentValue 변경 전 훅 |
| [05 PostGameplayEffectExecute](05_post_ge_execute.md) | 4.4.6 | GE 실행 후 훅 |
| [06 OnAttributeAggregatorCreated](06_aggregator_created.md) | 4.4.7 | Aggregator 커스터마이징 |
EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/01_definition_design.md << 'EOF'
# AttributeSet 정의 & 설계

> **GASDoc**: 4.4.1~4.4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/02_item_attributes.md << 'EOF'
# 아이템 Attribute 패턴

> **GASDoc**: 4.4.2.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/03_defining_initializing.md << 'EOF'
# Attribute 선언 & 초기화

> **GASDoc**: 4.4.3~4.4.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/04_pre_attribute_change.md << 'EOF'
# PreAttributeChange()

> **GASDoc**: 4.4.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/05_post_ge_execute.md << 'EOF'
# PostGameplayEffectExecute()

> **GASDoc**: 4.4.6 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF

cat > D:/LyraStarterGame/doc/gas_tranek/attribute_set/06_aggregator_created.md << 'EOF'
# OnAttributeAggregatorCreated()

> **GASDoc**: 4.4.7 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/attribute_set/
git commit -m "docs: attribute_set 스캐폴딩 (4.4)"
```

---

## Task 7: gameplay_effect/ 생성 (GASDoc 4.5)

**Files:**
- Create: `doc/gas_tranek/gameplay_effect/README.md`
- Create: `doc/gas_tranek/gameplay_effect/01_definition.md` ~ `10_advanced.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/gameplay_effect

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_effect/README.md << 'EOF'
# Gameplay Effect (4.5)

> **GASDoc**: 4.5 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의](01_definition.md) | 4.5.1 | GE 구조, Duration 타입 |
| [02 적용 & 제거](02_apply_remove.md) | 4.5.2~3 | ApplyGE, RemoveGE API |
| [03 Modifier](03_modifiers.md) | 4.5.4 | Add/Multiply/Divide/Override |
| [04 스태킹 & 태그 & 면역](04_stacking_tags_immunity.md) | 4.5.5, 4.5.7~8 | 스택 정책, GE 태그, Immunity |
| [05 Spec & SetByCaller](05_spec_setbycaller.md) | 4.5.9 | GESpec 구조, SetByCaller 패턴 |
| [06 Context](06_context.md) | 4.5.10 | GEContext, EffectCauser |
| [07 MMC](07_mmc.md) | 4.5.11 | Modifier Magnitude Calculation |
| [08 ExecCalc](08_execution_calculation.md) | 4.5.12 | Execution Calculation, Capture |
| [09 Cost & Cooldown](09_cost_cooldown.md) | 4.5.13~15 | Cost GE, Cooldown GE, 예측 |
| [10 고급 기능](10_advanced.md) | 4.5.16~18 | Duration 변경, 동적 GE, GE Container |
EOF

for i in \
  "01_definition|4.5.1|GE 정의" \
  "02_apply_remove|4.5.2~3|GE 적용 & 제거" \
  "03_modifiers|4.5.4|GE Modifier" \
  "04_stacking_tags_immunity|4.5.5 / 4.5.7~8|스태킹 / 태그 / 면역" \
  "05_spec_setbycaller|4.5.9|GESpec & SetByCaller" \
  "06_context|4.5.10|Gameplay Effect Context" \
  "07_mmc|4.5.11|Modifier Magnitude Calculation" \
  "08_execution_calculation|4.5.12|Execution Calculation" \
  "09_cost_cooldown|4.5.13~15|Cost & Cooldown GE" \
  "10_advanced|4.5.16~18|고급 GE 기능"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_effect/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: 파일 수 확인 (README 포함 11개)**

```bash
ls D:/LyraStarterGame/doc/gas_tranek/gameplay_effect/ | wc -l
```

기대 결과: `11`

- [ ] **Step 3: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/gameplay_effect/
git commit -m "docs: gameplay_effect 스캐폴딩 (4.5)"
```

---

## Task 8: gameplay_ability/ 생성 (GASDoc 4.6)

**Files:**
- Create: `doc/gas_tranek/gameplay_ability/README.md`
- Create: `doc/gas_tranek/gameplay_ability/01_definition.md` ~ `09_advanced.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/gameplay_ability

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_ability/README.md << 'EOF'
# Gameplay Ability (4.6)

> **GASDoc**: 4.6 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의](01_definition.md) | 4.6.1 | GA 구조, Replication/Cancel/Input 정책 |
| [02 입력 바인딩](02_input_binding.md) | 4.6.2 | ASC에 입력 바인딩 |
| [03 부여 & 활성화](03_granting_activating.md) | 4.6.3~4 | GrantAbility, ActivateAbility, Passive |
| [04 취소 & 조회](04_cancel_get_active.md) | 4.6.5~6 | CancelAbility, GetActivatableAbilities |
| [05 Instancing & Net](05_instancing_net.md) | 4.6.7~8 | Instancing Policy, Net Execution Policy |
| [06 Ability Tags](06_tags.md) | 4.6.9 | GA 태그 종류와 역할 |
| [07 Spec & 데이터](07_spec_data.md) | 4.6.10~11 | GASpec, 데이터 전달 방법 |
| [08 Cost & Cooldown](08_cost_cooldown.md) | 4.6.12 | CommitAbility, Cost/Cooldown 처리 |
| [09 고급 기능](09_advanced.md) | 4.6.13~16 | 레벨업, AbilitySet, Batching, Security |
EOF

for i in \
  "01_definition|4.6.1|GA 정의" \
  "02_input_binding|4.6.2|입력 바인딩" \
  "03_granting_activating|4.6.3~4|GA 부여 & 활성화" \
  "04_cancel_get_active|4.6.5~6|GA 취소 & 활성 GA 조회" \
  "05_instancing_net|4.6.7~8|Instancing & Net Execution Policy" \
  "06_tags|4.6.9|Ability Tags" \
  "07_spec_data|4.6.10~11|GA Spec & 데이터 전달" \
  "08_cost_cooldown|4.6.12|Cost & Cooldown" \
  "09_advanced|4.6.13~16|고급 GA 기능"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_ability/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/gameplay_ability/
git commit -m "docs: gameplay_ability 스캐폴딩 (4.6)"
```

---

## Task 9: ability_task/ 생성 (GASDoc 4.7)

**Files:**
- Create: `doc/gas_tranek/ability_task/README.md`
- Create: `doc/gas_tranek/ability_task/01_definition.md` ~ `04_root_motion.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/ability_task

cat > D:/LyraStarterGame/doc/gas_tranek/ability_task/README.md << 'EOF'
# Ability Task (4.7)

> **GASDoc**: 4.7 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의](01_definition.md) | 4.7.1 | Task 구조, 생명주기 |
| [02 커스텀 Task](02_custom_task.md) | 4.7.2 | 직접 만드는 AbilityTask |
| [03 사용법](03_using.md) | 4.7.3 | Task 사용 패턴 |
| [04 Root Motion](04_root_motion.md) | 4.7.4 | RootMotionSource Task |
EOF

for i in \
  "01_definition|4.7.1|AbilityTask 정의" \
  "02_custom_task|4.7.2|커스텀 AbilityTask" \
  "03_using|4.7.3|AbilityTask 사용법" \
  "04_root_motion|4.7.4|Root Motion Source Task"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/ability_task/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/ability_task/
git commit -m "docs: ability_task 스캐폴딩 (4.7)"
```

---

## Task 10: gameplay_cue/ 생성 (GASDoc 4.8)

**Files:**
- Create: `doc/gas_tranek/gameplay_cue/README.md`
- Create: `doc/gas_tranek/gameplay_cue/01_definition_trigger.md` ~ `05_events_reliability.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/gameplay_cue

cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_cue/README.md << 'EOF'
# Gameplay Cue (4.8)

> **GASDoc**: 4.8 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 정의 & 트리거](01_definition_trigger.md) | 4.8.1~2 | Cue 구조, 트리거 방법 |
| [02 Local & Params](02_local_params.md) | 4.8.3~4 | Local Cue, FGameplayCueParameters |
| [03 Manager & 차단](03_manager_prevention.md) | 4.8.5~6 | CueManager, 발동 억제 |
| [04 배칭](04_batching.md) | 4.8.7 | Manual RPC, 여러 Cue 묶기 |
| [05 이벤트 & 신뢰성](05_events_reliability.md) | 4.8.8~9 | Cue 이벤트 훅, 복제 신뢰성 |
EOF

for i in \
  "01_definition_trigger|4.8.1~2|GameplayCue 정의 & 트리거" \
  "02_local_params|4.8.3~4|Local Cue & Parameters" \
  "03_manager_prevention|4.8.5~6|Cue Manager & 차단" \
  "04_batching|4.8.7|GameplayCue 배칭" \
  "05_events_reliability|4.8.8~9|Cue 이벤트 & 신뢰성"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/gameplay_cue/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/gameplay_cue/
git commit -m "docs: gameplay_cue 스캐폴딩 (4.8)"
```

---

## Task 11: ability_system_globals/ 생성 (GASDoc 4.9)

**Files:**
- Create: `doc/gas_tranek/ability_system_globals/README.md`

- [ ] **Step 1: 폴더 및 파일 생성 (내용 포함 — 하위 섹션이 4.9.1 하나뿐)**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/ability_system_globals

cat > D:/LyraStarterGame/doc/gas_tranek/ability_system_globals/README.md << 'EOF'
# Ability System Globals (4.9)

> **GASDoc**: 4.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

### InitGlobalData() (4.9.1)

---

## 내 분석

EOF
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/ability_system_globals/
git commit -m "docs: ability_system_globals 스캐폴딩 (4.9)"
```

---

## Task 12: network_prediction/ 생성 (GASDoc 4.10)

**Files:**
- Create: `doc/gas_tranek/network_prediction/README.md`
- Create: `doc/gas_tranek/network_prediction/01_prediction_key.md` ~ `03_future_npp.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/network_prediction

cat > D:/LyraStarterGame/doc/gas_tranek/network_prediction/README.md << 'EOF'
# Network Prediction (4.10)

> **GASDoc**: 4.10 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 Prediction Key](01_prediction_key.md) | 4.10.1 | Key 생성, 범위, 생명주기 |
| [02 Prediction Window](02_prediction_windows.md) | 4.10.2~3 | 새 예측 윈도우, 액터 예측 스폰 |
| [03 미래 & NPP](03_future_npp.md) | 4.10.4~5 | Prediction 한계, Network Prediction Plugin |
EOF

for i in \
  "01_prediction_key|4.10.1|Prediction Key" \
  "02_prediction_windows|4.10.2~3|Prediction Window 생성 & 액터 스폰" \
  "03_future_npp|4.10.4~5|Prediction 미래 & Network Prediction Plugin"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/network_prediction/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/network_prediction/
git commit -m "docs: network_prediction 스캐폴딩 (4.10)"
```

---

## Task 13: targeting/ 생성 (GASDoc 4.11)

**Files:**
- Create: `doc/gas_tranek/targeting/README.md`
- Create: `doc/gas_tranek/targeting/01_target_data.md` ~ `04_containers.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/targeting

cat > D:/LyraStarterGame/doc/gas_tranek/targeting/README.md << 'EOF'
# Targeting (4.11)

> **GASDoc**: 4.11 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 Target Data](01_target_data.md) | 4.11.1 | FGameplayAbilityTargetData 구조 |
| [02 Target Actors](02_target_actors.md) | 4.11.2 | AGameplayAbilityTargetActor |
| [03 Filter & Reticle](03_filters_reticles.md) | 4.11.3~4 | TargetDataFilter, WorldReticle |
| [04 Container Targeting](04_containers.md) | 4.11.5 | GE Container 타겟팅 |
EOF

for i in \
  "01_target_data|4.11.1|Target Data" \
  "02_target_actors|4.11.2|Target Actors" \
  "03_filters_reticles|4.11.3~4|Target Filter & Reticle" \
  "04_containers|4.11.5|GE Container Targeting"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/targeting/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/targeting/
git commit -m "docs: targeting 스캐폴딩 (4.11)"
```

---

## Task 14: common_patterns/ 생성 (GASDoc 5)

**Files:**
- Create: `doc/gas_tranek/common_patterns/README.md`
- Create: `doc/gas_tranek/common_patterns/01_stun_sprint_ads.md`
- Create: `doc/gas_tranek/common_patterns/02_lifesteal_crit.md`
- Create: `doc/gas_tranek/common_patterns/03_misc.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/common_patterns

cat > D:/LyraStarterGame/doc/gas_tranek/common_patterns/README.md << 'EOF'
# 공통 구현 패턴 (5)

> **GASDoc**: 5 · [원문 참조](../cache/GASDocument_Readme.md)

| 파일 | 섹션 | 내용 |
|------|------|------|
| [01 Stun / Sprint / ADS](01_stun_sprint_ads.md) | 5.1~3 | 기본 상태이상, 달리기, 조준 |
| [02 Lifesteal / 치명타](02_lifesteal_crit.md) | 5.4, 5.6 | 흡혈, 크리티컬 히트 |
| [03 기타 패턴](03_misc.md) | 5.5, 5.7~9 | 랜덤, Non-Stacking GE, 인터랙션 |
EOF

for i in \
  "01_stun_sprint_ads|5.1~3|Stun / Sprint / ADS 구현" \
  "02_lifesteal_crit|5.4 / 5.6|Lifesteal & 치명타 구현" \
  "03_misc|5.5 / 5.7~9|기타 구현 패턴"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/common_patterns/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/common_patterns/
git commit -m "docs: common_patterns 스캐폴딩 (GASDoc 5)"
```

---

## Task 15: reference/ 생성 (GASDoc 6~11)

**Files:**
- Create: `doc/gas_tranek/reference/debugging.md`
- Create: `doc/gas_tranek/reference/optimization.md`
- Create: `doc/gas_tranek/reference/quality_of_life.md`
- Create: `doc/gas_tranek/reference/troubleshooting.md`
- Create: `doc/gas_tranek/reference/dave_ratti_qa.md`

- [ ] **Step 1: 폴더 및 파일 일괄 생성**

```bash
mkdir -p D:/LyraStarterGame/doc/gas_tranek/reference

for i in \
  "debugging|6|GAS 디버깅" \
  "optimization|7|GAS 최적화" \
  "quality_of_life|8|QoL 제안" \
  "troubleshooting|9|트러블슈팅" \
  "dave_ratti_qa|11|Dave Ratti Q&A"
do
  FILE=$(echo $i | cut -d'|' -f1)
  SECTION=$(echo $i | cut -d'|' -f2)
  TITLE=$(echo $i | cut -d'|' -f3)
  cat > D:/LyraStarterGame/doc/gas_tranek/reference/${FILE}.md << EOF
# ${TITLE}

> **GASDoc**: ${SECTION} · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

---

## 내 분석

EOF
done
```

- [ ] **Step 2: 파일 수 확인 (5개)**

```bash
ls D:/LyraStarterGame/doc/gas_tranek/reference/
```

기대 결과: `dave_ratti_qa.md  debugging.md  optimization.md  quality_of_life.md  troubleshooting.md`

- [ ] **Step 3: Commit**

```bash
cd D:/LyraStarterGame
git add doc/gas_tranek/reference/
git commit -m "docs: reference 스캐폴딩 (GASDoc 6~11)"
```

---

## Task 16: 최종 검증

- [ ] **Step 1: 전체 파일 수 확인**

```bash
find D:/LyraStarterGame/doc/gas -name "*.md" | sort
```

기대 결과: 총 75개 파일 (cache 2개 포함)

- [ ] **Step 2: 각 폴더 구조 확인**

```bash
find D:/LyraStarterGame/doc/gas -type d | sort
```

기대 결과:
```
doc/gas
doc/gas_tranek/ability_system_component
doc/gas_tranek/ability_system_globals
doc/gas_tranek/ability_task
doc/gas_tranek/attribute
doc/gas_tranek/attribute_set
doc/gas_tranek/cache
doc/gas_tranek/common_patterns
doc/gas_tranek/gameplay_ability
doc/gas_tranek/gameplay_cue
doc/gas_tranek/gameplay_effect
doc/gas_tranek/gameplay_tag
doc/gas_tranek/network_prediction
doc/gas_tranek/reference
doc/gas_tranek/targeting
```

- [ ] **Step 3: 샘플 파일 내용 확인 (템플릿 형식 검증)**

```bash
cat D:/LyraStarterGame/doc/gas_tranek/gameplay_effect/01_definition.md
```

기대 결과: `# GE 정의` 헤더, GASDoc 섹션 레퍼런스, `## 개념 요약`, `## 내 분석` 섹션 존재

- [ ] **Step 4: doc/gas_tranek/README.md 링크 확인**

```bash
cat D:/LyraStarterGame/doc/gas_tranek/README.md
```

- [ ] **Step 5: 최종 커밋 (필요 시 누락된 파일 추가)**

```bash
cd D:/LyraStarterGame
git status
git add -A doc/gas_tranek/
git commit -m "docs: doc/gas 전체 구조 재편 완료 — GASDoc 기반 스캐폴딩"
```
