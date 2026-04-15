---
name: Lyra Project Overview
description: Lyra 프로젝트 전체 구조, 모듈, GAS 아키텍처 핵심 클래스 목록
type: project
originSessionId: 3c3925dd-9448-4e40-a5b8-a6b2a3604de6
---
# Lyra 프로젝트 구조

## 소스 모듈
- `Source/LyraGame` — 메인 게임 모듈 (GAS 포함)
- `Source/LyraEditor` — 에디터 전용 유틸리티

## GameFeatures 플러그인
- ShooterCore, ShooterExplorer, ShooterMaps, ShooterTests, TopDownArena

## GAS 핵심 아키텍처

### ASC 소유 구조
- **ASC 소유자**: `ALyraPlayerState` (IAbilitySystemInterface 구현)
- **ASC 아바타**: `ALyraCharacter` (Pawn)
- **ASC 클래스**: `ULyraAbilitySystemComponent` (UAbilitySystemComponent 확장)

### 핵심 클래스 목록

#### AbilitySystem/
- `ULyraAbilitySystemComponent` — 베이스 ASC, 입력 처리, ActivationGroup 관리
- `ULyraAbilitySet` — DataAsset, Ability/Effect/AttributeSet을 묶어서 한번에 부여
- `ULyraAbilityTagRelationshipMapping` — 태그 기반 Ability 간 블록/캔슬 관계 정의
- `ULyraAbilitySystemGlobals` — ASC 글로벌 설정
- `ULyraGameplayCueManager` — GameplayCue 관리
- `ULyraGameplayEffectContext` — Effect Context 확장
- `ULyraGlobalAbilitySystem` — 글로벌 Ability/Effect 적용
- `ULyraTaggedActor` — GameplayTag를 가진 Actor

#### AbilitySystem/Abilities/
- `ULyraGameplayAbility` — 베이스 GA 클래스
  - ActivationPolicy: OnInputTriggered / WhileInputActive / OnSpawn
  - ActivationGroup: Independent / Exclusive_Replaceable / Exclusive_Blocking
  - AdditionalCosts: ULyraAbilityCost 배열
- `ULyraGameplayAbility_Death` — 사망 처리
- `ULyraGameplayAbility_Jump` — 점프
- `ULyraGameplayAbility_Reset` — 리셋
- `ULyraAbilityCost` — 비용 베이스 클래스
- `ULyraAbilityCost_InventoryItem` / `ULyraAbilityCost_ItemTagStack` / `ULyraAbilityCost_PlayerTagStack`

#### AbilitySystem/Attributes/
- `ULyraAttributeSet` — 베이스 AttributeSet (ATTRIBUTE_ACCESSORS 매크로)
- `ULyraHealthSet` — Health, MaxHealth, Healing(Meta), Damage(Meta)
- `ULyraCombatSet` — 전투 관련 어트리뷰트

#### AbilitySystem/Executions/
- `ULyraDamageExecution` — 데미지 계산 (GameplayEffectExecutionCalculation)
- `ULyraHealExecution` — 힐 계산

#### AbilitySystem/Phases/
- `ULyraGamePhaseAbility` — 게임 페이즈 전환 GA
- `ULyraGamePhaseSubsystem` — 페이즈 관리 서브시스템

### Pawn 초기화 흐름
1. `ULyraPawnData` (DataAsset) — PawnClass, AbilitySets, TagRelationshipMapping, InputConfig 정의
2. `ULyraPawnExtensionComponent` — Pawn에 붙는 컴포넌트, ASC 초기화 조율 (IGameFrameworkInitStateInterface)
3. `ALyraPlayerState::PostInitializeComponents` — ASC 생성 + HealthSet/CombatSet 직접 생성
4. `ULyraPawnExtensionComponent::InitializeAbilitySystem` — Pawn을 Avatar로 등록
5. `ULyraAbilitySet::GiveToAbilitySystem` — Ability/Effect/AttributeSet 일괄 부여

### 입력-Ability 연결
- `ULyraInputConfig` — InputAction ↔ GameplayTag 매핑 정의
- `ULyraAbilitySystemComponent::AbilityInputTagPressed/Released` — 입력 태그로 Ability 활성화
- `ULyraHeroComponent` — 입력 설정 담당 컴포넌트

### Equipment/Weapon GAS 연동
- `ULyraEquipmentDefinition` — 장비 정의 DataAsset
- `ULyraEquipmentManagerComponent` — 장비 관리
- `ULyraGameplayAbility_FromEquipment` — 장착된 장비 기반 GA
- `ULyraWeaponInstance` / `ULyraRangedWeaponInstance`
- `ULyraGameplayAbility_RangedWeapon` — 원거리 무기 GA
