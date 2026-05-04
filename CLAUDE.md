# Lyra GAS 학습 프로젝트

## 목적

이 프로젝트는 **언리얼 엔진 Lyra 스타터 게임**을 분석하여 **GAS(Gameplay Ability System)를 완벽 학습**하기 위한 프로젝트다.
코드를 직접 수정하는 것보다 분석, 설명, 패턴 파악이 주된 작업이다.

---

## 프로젝트 구조 핵심 요약

```
Source/LyraGame/AbilitySystem/   ← GAS 핵심 구현 폴더
Source/LyraGame/Character/       ← Pawn/Character, PawnExtensionComponent
Source/LyraGame/Player/          ← PlayerState (ASC 소유자)
Source/LyraGame/Equipment/       ← 장비 시스템 (AbilitySet 연동)
Source/LyraGame/Weapons/         ← 무기 GA
Source/LyraGame/Interaction/     ← AbilityTask 예시
Plugins/GameFeatures/            ← ShooterCore 등 게임 기능 플러그인
```

## GAS 아키텍처 핵심

- **ASC 소유자**: `ALyraPlayerState` (IAbilitySystemInterface 구현)
- **ASC 아바타**: `ALyraCharacter`
- **ASC 클래스**: `ULyraAbilitySystemComponent`
- **Ability 부여 단위**: `ULyraAbilitySet` (DataAsset — Ability + Effect + AttributeSet 묶음)
- **Pawn 초기화 조율**: `ULyraPawnExtensionComponent` (IGameFrameworkInitStateInterface)
- **AttributeSet**: `ULyraHealthSet` (Meta Attribute 패턴 — Damage/Healing은 임시값)
- **입력 연결**: `ULyraInputConfig` (InputAction ↔ GameplayTag) → `ULyraAbilitySystemComponent::AbilityInputTagPressed`

---

## 행동 지침

- 코드를 분석할 때는 **클래스 계층, 패턴, 설계 의도**를 중심으로 설명한다.
- 파일을 읽기 전에 먼저 수정을 제안하지 않는다.
- 설명은 **한국어**로 한다.
- GAS 개념 설명 시 언리얼 공식 용어(ASC, GA, GE, AttributeSet, GameplayCue, GameplayTag 등)를 그대로 사용한다.
- 코드 수정 작업이 발생하면 범위를 최소화하고, 요청한 것만 변경한다.
- 작업이 완료되면 항상 git commit까지 한다.
- 새 문서를 작성할 때는 `doc/_template.md`를 참고해 형식을 맞춘다.

---

## 소스 코드 분석 전 캐시 확인 규칙

**모든 소스 파일**(Lyra, 엔진 코드 등)을 읽을 때는 — 문서 작성 중이든, 질문에 답하는 중이든, 이유와 무관하게 — 반드시 아래 순서를 따른다.

1. **캐시 먼저 확인**: `D:\Nexon\Study\GasStudy\memory\lyra_gas_analysis.md` 를 읽는다.
2. **캐시에 있으면**: 소스 파일을 열지 않고 캐시 내용을 바탕으로 답한다.
3. **캐시에 없으면**: 소스 파일을 직접 읽어서 분석한다.
4. **소스 직접 분석 후**: 반드시 새로 알게 된 내용을 `lyra_gas_analysis.md`에 추가한다.
   - 섹션 번호를 이어서 붙인다.
   - 출처 파일 경로(엔진 경로 포함)를 명시한다.
   - 핵심 함수명, 호출 체인, 설계 의도를 포함한다.
   - **캐싱을 빠뜨리는 것은 허용되지 않는다.** 분석했으면 반드시 기록한다.

> **목적**: 같은 소스를 반복 열람하는 토큰 낭비를 막기 위함.

---

---

## 폴더 분류 규칙

하나의 `.md` 파일이 아래 조건 중 하나라도 충족하면 **하위 폴더로 분리**한다.

- **300줄 초과** — 한 파일에 너무 많은 내용이 집중된 경우
- **독립적인 개념이 3개 이상** — 각자 완결된 주제가 여러 개 모인 경우

### 하위 폴더 구성 규칙

1. 폴더 안에 `README.md`를 만들어 인덱스 역할을 한다.
2. 각 주제는 번호 접두사 파일(`01_topic.md`, `02_topic.md`, ...)로 분리한다.
3. 부모 `README.md`의 링크를 `하위폴더/README.md`로 교체하고, 구 파일은 삭제한다.

**예시:**
```
gas/05_attribute_set.md  (610줄, 5개 독립 주제)
  →  gas/attribute/README.md
     gas/attribute/01_attribute_types.md
     gas/attribute/02_base_current_value.md
     gas/attribute/03_accessors_and_clamp.md
     gas/attribute/04_meta_attribute.md
     gas/attribute/05_derived_attribute.md
```

---

## 참고

- 전체 GAS 구조 분석: `README.md` 하단 "GAS 학습 분석" 섹션
- 세션 간 지속 메모리: `C:\Users\kmgmg2391601\.claude\projects\D--LyraStarterGame\memory\`

---

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
