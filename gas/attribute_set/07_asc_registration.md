# AttributeSet과 ASC 등록 메커니즘

AttributeSet이 ASC에 인식되려면 `SpawnedAttributes` 배열에 들어가야 한다.
방법은 두 가지다.

---

## 방법 1. 자동 수집 (CreateDefaultSubobject)

ASC Owner의 서브오브젝트로 만들어두면 ASC가 `InitializeComponent()` 시점에 자동으로 찾아서 등록한다.

```cpp
// 예: PlayerState 생성자
HealthSet = CreateDefaultSubobject<ULyraHealthSet>(TEXT("HealthSet"));
```

**엔진 내부 코드**: `AbilitySystemComponent_Abilities.cpp` — `UAbilitySystemComponent::InitializeComponent()`

```cpp
// "Look for DSO AttributeSets" 주석
TArray<UObject*> ChildObjects;
GetObjectsWithOuter(Owner, ChildObjects, /*bIncludeNestedObjects=*/false, RF_NoFlags, EInternalObjectFlags::Garbage);

for (UObject* Obj : ChildObjects)
{
    UAttributeSet* Set = Cast<UAttributeSet>(Obj);
    if (Set)
    {
        SpawnedAttributes.AddUnique(Set);
    }
}
```

**동작 순서:**
1. `CreateDefaultSubobject` → AttributeSet이 Owner의 서브오브젝트(Outer = Owner)로 생성
2. ASC ctor에서 `bWantsInitializeComponent = true` 설정 → 엔진이 `InitializeComponent()` 호출 보장
3. `GetObjectsWithOuter(Owner)` → Owner의 **직접** 자식 오브젝트 전체 스캔 (재귀 없음)
4. `UAttributeSet` 파생 클래스이면 `SpawnedAttributes`에 추가

> **조건은 하나**: AttributeSet의 Outer가 ASC의 Owner와 같을 것.
> `CreateDefaultSubobject`는 자동으로 Owner를 Outer로 설정하므로, 선언만 해두면 자동 등록된다.

---

## 방법 2. 수동 등록 (AddAttributeSetSubobject)

런타임에 동적으로 생성해서 직접 등록한다. `InitializeComponent` 스캔을 거치지 않는다.

```cpp
// Owner를 Outer로 인스턴스 생성
UAttributeSet* NewSet = NewObject<UAttributeSet>(ASC->GetOwner(), AttributeSetClass);

// SpawnedAttributes에 직접 추가
ASC->AddAttributeSetSubobject(NewSet);
```

제거할 때는:
```cpp
ASC->RemoveSpawnedAttribute(NewSet);
```

---

## 두 방법 비교

| | 자동 수집 | 수동 등록 |
|---|---|---|
| 등록 시점 | `InitializeComponent()` (컴포넌트 초기화 시) | 명시적 호출 시점 |
| 제거 가능 여부 | 불가 (Actor 수명과 동일) | `RemoveSpawnedAttribute`로 제거 가능 |
| 용도 | 항상 존재하는 기본 AttributeSet | 장비 장착, GameFeature 등 동적 부여/제거 |
