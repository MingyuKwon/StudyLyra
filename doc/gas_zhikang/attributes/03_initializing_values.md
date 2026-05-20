# Attribute 값 초기화 방법

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 5가지 방법 개요

1. AttributeSet 생성자에서 Init
2. PostInitializeComponents / BeginPlay에서 Init
3. BeginPlay에서 GE 적용
4. AttributeSetInitter + CurveTable
5. DefaultStartingData

---

## 방법 1 — AttributeSet 생성자에서 Init

`ATTRIBUTE_ACCESSORS` 매크로를 사용했다면 `InitMyAttribute(Value)` 호출이 가능하다.

```cpp
ULabHealthAttributeSet::ULabHealthAttributeSet()
{
    InitHealth(100.0f);
    InitMaxHealth(100.0f);
}
```

컴파일 타임에 값이 이미 정해져 있고 유연성이 필요 없을 때 사용한다.

---

## 방법 2 — PostInitializeComponents / BeginPlay에서 Init

생성자와 동일하게 Init 함수를 나중에 호출하는 방식이다. 이 시점에는 Actor 블루프린트 클래스의 값이 로드된다.

`SpawnActorDeferred`로 Actor를 스폰하면 `BeginPlay` 전에 런타임 값을 설정할 수 있어 유연성이 더 높다. 프로그래머 수준의 유연성이 필요할 때 사용한다.

---

## 방법 3 — BeginPlay에서 GE 적용

Attribute 초기값을 GE Modifier로 적용하는 방식이다. Modifier 값은 직접 입력, CurveTable 참조, 다른 값 기반 계산 등 다양한 방식으로 설정할 수 있다.

여러 GE를 조합하는 것도 가능하다. 예: MaxHealth = 100을 설정하는 Infinite GE + Health = MaxHealth로 설정하는 Instant GE.

디자이너가 GE 에셋을 수정해 유연하게 조정할 수 있을 때 유리하다.

---

## 방법 4 — AttributeSetInitter + CurveTable ⭐ 가장 유연

전역 UCurveTable 에셋 목록을 설정하는 방식이다. Project Settings에서 `GlobalAttributeSetDefaultsTables`를 검색해 설정할 수 있다.

대형 프로젝트에서는 `AbilitySystemGlobals` 서브클래스에서 `GetGlobalAttributeSetDefaultsTablePaths()`를 오버라이드하거나 `Add/RemoveAttributeDefaultTables()`를 호출해 런타임에 테이블 목록을 변경할 수도 있다.

```cpp
void AAbilitiesLabCharacter::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    LabAbilitySystemComp->InitAbilityActorInfo(this, this);
    IGameplayAbilitiesModule::Get().GetAbilitySystemGlobals()
        ->GetAttributeSetInitter()
        ->InitAttributeSetDefaults(LabAbilitySystemComp, "MyCharacter", /*Level=*/1, /*IsInitialLoad=*/true);
}
```

CurveTable Row 이름 형식: `GroupName.AttributeSetName.AttributeName`

- `GroupName`: 호출 시 전달하는 식별자 (예: `"MyCharacter"`). 정확히 일치해야 함
- `AttributeSetName`: 부분 일치로도 동작 (예: `"Health"` → `"LabHealthAttributeSet"` 매핑됨)
- `AttributeName`: 정확히 일치해야 함

Level 파라미터에 따라 CurveTable의 컬럼이 선택된다. `"Default"` 그룹 이름을 추가해두면 매핑되지 않는 그룹에 대한 폴백으로 사용된다.

Fortnite는 이 방식에 커스텀 서브클래스와 플러그인 기반 추가 CurveTable 에셋을 더해 사용한다.

---

## 방법 5 — DefaultStartingData

[AttributeSet 추가 방법 — 방법 4](02_adding_attribute_sets.md) 참고. 이미 코드에서 추가한 AttributeSet에도 초기값 설정 목적으로 사용할 수 있다.
