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

---

## 참고

- 전체 GAS 구조 분석: `README.md` 하단 "GAS 학습 분석" 섹션
- 세션 간 지속 메모리: `C:\Users\kmgmg2391601\.claude\projects\D--LyraStarterGame\memory\`
