# AttributeSet 추가 방법

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 4가지 방법 개요

1. **C++ 생성자에서 Default Subobject로** (권장)
2. **PostInitializeComponents / BeginPlay에서**
3. **런타임에 동적으로**
4. **블루프린트 DefaultStartingData로**

---

## 방법 1 — Default Subobject (DSO) ✅ 권장

Actor 클래스가 어떤 AttributeSet을 필요로 하는지 컴파일 타임에 알고 있다면, 생성자에서 `CreateDefaultSubobject()`로 만드는 것이 가장 좋다.

```cpp
AAbilitiesLabCharacter::AAbilitiesLabCharacter()
{
    LabAbilitySystemComp = CreateDefaultSubobject<ULabAbilitySystemComponent>(TEXT("AbilitySystemComponent"));
    HealthSet = CreateDefaultSubobject<ULabHealthAttributeSet>(TEXT("HealthSet"));
    CombatSet = CreateDefaultSubobject<ULabCombatAttributeSet>(TEXT("CombatSet"));
}
```

**장점**: 클라이언트가 서버 오브젝트 복제를 기다리지 않고 즉시 AttributeSet에 접근 가능. 델리게이트 바인딩에 유리.

**주의사항**:
- `UPROPERTY()` 참조를 반드시 보관해야 한다. 그렇지 않으면 GC에 의해 수거될 수 있다. (PIE를 위해 월드를 복제할 때 GC 패스가 발생하는 레벨 배치 Actor에서 특히 중요)
- 생성자 실행 시점에는 블루프린트 기본값이 아직 로드되지 않아 조건부 추가가 불가능하다.
- 생성자의 DSO는 아카이타입 오브젝트다. 델리게이트 바인딩은 `PostInitializeComponents()` 또는 `BeginPlay()`에서 해야 한다.
- DSO AttributeSet은 `AbilitySystemComponent::InitializeComponent()`에서 자동으로 감지된다.

---

## 방법 2 — PostInitializeComponents / BeginPlay에서 AddSet

```cpp
void AAbilitiesLabCharacter::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    LabAbilitySystemComp->AddSet<ULabHealthAttributeSet>();
    LabAbilitySystemComp->AddSet<ULabCombatAttributeSet>();
}
```

**장점**: 이 시점에는 블루프린트 기본값이 로드되어 있으므로, 블루프린트 설정값에 따라 조건부로 AttributeSet을 추가할 수 있다.

**주의사항 (멀티플레이어)**:
- 클라이언트에서도 AttributeSet을 스폰할 수 있지만, 최종적으로는 서버에서 생성된 오브젝트가 복제되어 `SpawnedAttributes`에 저장된다. 클라이언트 측 스폰은 임시다.
- 델리게이트 바인딩 시 `OnRep_SpawnedAttributes()`를 오버라이드해서 클라이언트 생성 오브젝트 구독을 해제하고 서버 복제본에 재구독해야 한다.
- 그럼에도 클라이언트 측 스폰은 유용하다. 서버가 그 사이에 적용하는 GE를 처리하는 데 쓰인다.

---

## 방법 3 — 런타임 동적 추가

`AddSet<T>()`는 런타임 중 언제든 호출할 수 있다. 장단점은 방법 2와 동일하다.

런타임에 AttributeSet을 제거하는 경우, `OnRep_SpawnedAttributes`에서 제거된 set을 감지해 델리게이트 바인딩을 정리해야 한다.

> **주의**: GE와 AttributeSet의 복제 순서가 클라이언트에서 뒤바뀔 수 있다. AttributeSet은 필요해지기 훨씬 전에 서버 측에서 추가해 두는 것이 좋다. 마찬가지로, AttributeSet을 제거하기 전에 그것에 의존하는 GE를 먼저 제거해야 한다. 일반적으로 AttributeSet을 제거할 일은 거의 없다.

---

## 방법 4 — DefaultStartingData (블루프린트 설정)

ASC의 디테일 패널에서 `DefaultStartingData` 프로퍼티에 AttributeSet 클래스와 DataTable 쌍을 설정한다.

- DataTable은 `AttributeMetaData`를 Row Struct로 사용해야 한다.
- 각 Attribute마다 `MyAttributeSet.AttributeName` 형식의 Row를 추가하고 `BaseValue`를 설정한다.
- DataTable을 제공하지 않으면 AttributeSet이 생성되지 않는다.

**장점**: 디자이너가 Actor 블루프린트나 레벨 인스턴스에서 어떤 AttributeSet을 가질지 직접 설정 가능.

**주의사항**:
- 방법 2/3과 동일하게 클라이언트는 서버 복제본을 기다리는 동안 임시 로컬 AttributeSet을 가진다. `OnRep_SpawnedAttributes`에서 서버 복제본을 감지해 델리게이트를 재바인딩해야 한다.
- 이미 코드에서 추가한 AttributeSet에도 초기값 설정 목적으로 이 방법을 사용할 수 있다.
