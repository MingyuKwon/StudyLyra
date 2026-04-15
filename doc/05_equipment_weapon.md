# Equipment / Weapon GAS 연동

## 구조 개요

```
ULyraEquipmentDefinition (DataAsset)
  ├─ EquipmentInstance 클래스 지정
  └─ AbilitySetsToGrant[]  ← 장착 시 부여할 ULyraAbilitySet 배열

ULyraEquipmentManagerComponent (Pawn에 붙는 컴포넌트)
  ├─ EquipItem()   → AbilitySet.GiveToAbilitySystem() 호출
  └─ UnequipItem() → GrantedHandles.TakeFromAbilitySystem() 호출

ULyraEquipmentInstance
  └─ 장착된 장비의 런타임 인스턴스 (스폰된 액터 등 관리)
```

## 무기 클래스 계층

```
ULyraEquipmentInstance
  └─ ULyraWeaponInstance
        └─ ULyraRangedWeaponInstance   ← 원거리 무기 전용 (탄퍼짐, 사거리 등)
```

## 무기 Ability 계층

```
ULyraGameplayAbility
  └─ ULyraGameplayAbility_FromEquipment   ← 장비 기반 GA 베이스
        └─ ULyraGameplayAbility_RangedWeapon  ← 원거리 무기 발사 GA
```

### ULyraGameplayAbility_FromEquipment
- `GetAssociatedEquipment()` — 이 GA를 부여한 장비 인스턴스 반환
- `GetAssociatedItem()` — 연결된 인벤토리 아이템 인스턴스 반환
- 장비 기반 모든 GA의 공통 베이스 클래스

## 인벤토리 연동

```
ULyraInventoryItemDefinition (DataAsset)
  └─ Fragments[]
        └─ InventoryFragment_EquippableItem
              └─ EquipmentDefinition 참조

ULyraQuickBarComponent
  └─ 퀵슬롯 관리, 활성 슬롯 변경 시 Equipment 장착/해제 트리거
```

## Ability 부여 / 제거 패턴 요약

장비 시스템은 Pawn 초기화와 동일한 `ULyraAbilitySet` + `FLyraAbilitySet_GrantedHandles` 패턴을 재사용한다.

| 시점 | 호출 |
|------|------|
| 장착 | `ULyraAbilitySet::GiveToAbilitySystem()` → Handles 저장 |
| 해제 | `FLyraAbilitySet_GrantedHandles::TakeFromAbilitySystem()` |
