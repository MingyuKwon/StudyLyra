# Pawn 초기화 흐름

## 개요

Lyra의 Pawn 초기화는 `ULyraPawnExtensionComponent`가 `IGameFrameworkInitStateInterface`를 구현하여 여러 컴포넌트의 초기화 순서를 조율한다.

## 단계별 흐름

```
1. ULyraPawnData (DataAsset)
      ├─ PawnClass
      ├─ AbilitySets[]         ← ULyraAbilitySet 배열
      ├─ TagRelationshipMapping
      └─ InputConfig

2. ALyraPlayerState::PostInitializeComponents()
      ├─ ULyraAbilitySystemComponent 생성
      ├─ ULyraHealthSet 직접 생성
      └─ ULyraCombatSet 직접 생성

3. ULyraPawnExtensionComponent::InitializeAbilitySystem()
      ├─ ASC에 Pawn을 Avatar로 등록
      └─ InitAbilityActorInfo() 호출

4. ULyraAbilitySet::GiveToAbilitySystem()
      ├─ Ability 일괄 부여
      ├─ GameplayEffect 일괄 부여
      ├─ AttributeSet 일괄 부여
      └─ FLyraAbilitySet_GrantedHandles 반환 (나중에 제거 시 사용)
```

## 핵심 클래스 역할

### ULyraPawnData
- Pawn의 모든 설정을 담는 DataAsset
- `AbilitySets` 배열로 어떤 Ability/Effect/AttributeSet을 줄지 정의
- `TagRelationshipMapping`으로 Ability 간 충돌 관계 지정
- `InputConfig`로 입력 바인딩 지정

### ULyraPawnExtensionComponent
- Pawn에 붙는 컴포넌트로 다른 컴포넌트들의 초기화 순서 조율
- `IGameFrameworkInitStateInterface` 구현 → 상태 머신 방식으로 초기화 진행
- ASC 포인터 캐싱 및 `OnAbilitySystemInitialized` 델리게이트 제공

### FLyraAbilitySet_GrantedHandles
- `GiveToAbilitySystem()` 호출 시 반환되는 핸들 묶음
- `TakeFromAbilitySystem()` 호출로 부여된 Ability/Effect/AttributeSet 일괄 제거 가능
- 장비 장착/해제 시 이 패턴을 그대로 활용
