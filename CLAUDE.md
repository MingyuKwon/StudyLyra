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

**Tradeoff:** 빠른 작업보다 신중함을 우선한다. 단순한 작업은 판단에 따라 유연하게 적용한다.

### 1. 코딩 전 사고 (Think Before Coding)

- 방향이 애매하거나 선택지가 여러 개이면 바로 진행하지 말고 선택지를 보여준다.
- 파일을 읽기 전에 먼저 수정을 제안하지 않는다.
- 코드를 분석할 때는 **클래스 계층, 패턴, 설계 의도**를 중심으로 설명한다.
- 여러 해석이 가능하면 조용히 하나를 고르지 말고 제시한다.
- 불확실하면 멈추고 질문한다.

### 2. 단순함 우선 (Simplicity First)

- 요청한 것 외의 기능을 추가하지 않는다.
- 단일 사용 코드에 추상화를 도입하지 않는다.
- 200줄로 쓸 수 있는 걸 50줄로 쓸 수 있다면 다시 쓴다.

### 3. 최소한의 변경 (Surgical Changes)

- 코드 수정 작업이 발생하면 범위를 최소화하고, 요청한 것만 변경한다.
- 인접 코드·포맷을 "개선"하지 않는다.
- 기존 스타일을 따른다.
- 관련 없는 dead code는 삭제하지 말고 언급만 한다.

### 4. 목표 중심 실행 (Goal-Driven Execution)

- 작업이 완료되면 항상 git commit까지 한다.
- 다단계 작업에는 계획을 먼저 제시한다.
- 성공 기준을 명확히 정의한 뒤 실행한다.

### 프로젝트 규칙

- 설명은 **한국어**로 한다.
- GAS 개념 설명 시 언리얼 공식 용어(ASC, GA, GE, AttributeSet, GameplayCue, GameplayTag 등)를 그대로 사용한다.
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

