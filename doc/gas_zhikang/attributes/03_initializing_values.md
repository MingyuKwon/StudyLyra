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

### 개념

`FAttributeSetInitter`는 CurveTable 스프레드시트에서 읽은 초기값으로 ASC의 AttributeSet들을 일괄 초기화하는 시스템이다. 핵심은 **GroupName + Level** 두 축으로 값을 조회한다는 것이다.

CurveTable은 아래 형태의 표다.

```
Row 이름 (GroupName.AttributeSetName.Attribute)    |  Level1  Level2  Level3  ...
-----------------------------------------------------------------------
Default.Health.MaxHealth                           |  100     200     300
Default.Health.HealthRegenRate                     |  1       1       1
Hero1.Health.MaxHealth                             |  150     250     350
Hero1.Move.MaxMoveSpeed                            |  500     520     540
```

- **열(Column)**: 레벨. `InitAttributeSetDefaults` 호출 시 Level 인수로 어느 열을 읽을지 결정
- **행(Row)**: `GroupName.AttributeSetName.Attribute` 형식

Row 이름 매핑 규칙:
- `GroupName` — 호출 시 전달하는 식별자 (예: `"Hero1"`). 정확히 일치해야 함
- `AttributeSetName` — **부분 일치** 허용 (`"Health"` → `"LabHealthAttributeSet"` 매핑됨)
- `AttributeName` — 정확히 일치해야 함

### 동작 흐름

```
게임 시작
  └── AbilitySystemGlobals가 CurveTable들을 PreloadAttributeSetData()로 로드
        └── TMap<GroupName, LevelData[]> 형태의 내부 캐시로 변환

Actor 스폰 / 레벨업
  └── InitAttributeSetDefaults(ASC, "Hero1", Level=3)
        └── "Hero1" 그룹의 Level 3 컬럼 데이터 조회
              └── ASC가 보유한 AttributeSet들을 순회
                    └── 매칭되는 Row 값으로 InitFoo() 호출
```

"Default"는 예약된 폴백 GroupName이다. 호출한 GroupName이 테이블에 없으면 "Default" 그룹으로 대신 초기화한다.

### 설정 방법

Project Settings에서 `GlobalAttributeSetDefaultsTables`를 검색해 CurveTable 에셋 목록을 추가한다.

대형 프로젝트에서는 `AbilitySystemGlobals` 서브클래스에서 `GetGlobalAttributeSetDefaultsTablePaths()`를 오버라이드하거나, `Add/RemoveAttributeDefaultTables()`로 런타임에 테이블 목록을 동적으로 변경할 수 있다. Fortnite는 이 방식을 플러그인 기반 추가 테이블과 함께 사용한다.

### 호출 예시

```cpp
void AAbilitiesLabCharacter::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    LabAbilitySystemComp->InitAbilityActorInfo(this, this);
    IGameplayAbilitiesModule::Get().GetAbilitySystemGlobals()
        ->GetAttributeSetInitter()
        ->InitAttributeSetDefaults(LabAbilitySystemComp, "MyCharacter", /*Level=*/1, /*bInitialInit=*/true);
}
```

레벨업 시 Level만 바꿔서 재호출하면 Attribute 값이 새 레벨에 맞게 업데이트된다. `bInitialInit=false`로 호출하면 이미 적용된 GE Modifier를 보존한 채 Base 값만 갱신한다.

---

## 방법 5 — DefaultStartingData

[AttributeSet 추가 방법 — 방법 4](02_adding_attribute_sets.md) 참고. 이미 코드에서 추가한 AttributeSet에도 초기값 설정 목적으로 사용할 수 있다.
