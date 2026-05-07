# DefaultSubobject

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectGlobals.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/UObjectGlobals.cpp`

---

## CreateDefaultSubobject란

Actor(또는 UObject) **생성자 안에서만** 사용할 수 있는 특수 팩토리 함수다.  
CDO가 만들어질 때 함께 생성되어 오브젝트의 "기본 구성"을 정의한다.

```cpp
AMyActor::AMyActor()
{
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
    MeshComp->SetupAttachment(RootComponent);
}
```

`TEXT("MeshComp")`는 서브오브젝트의 고유 이름이다.  
에디터 Outliner·Blueprint 컴포넌트 패널에 표시되고, 직렬화(저장) 키로도 사용된다.

---

## 내부 동작 — 항상 새 오브젝트를 만든다

`CreateDefaultSubobject`는 CDO 생성이든 일반 인스턴스 생성이든  
**항상 `StaticConstructObject_Internal`을 호출해서 새 오브젝트를 만든다.**  
CDO의 서브오브젝트를 공유하거나 재사용하는 게 아니다.

```cpp
// UObjectGlobals.cpp:6006
Result = StaticConstructObject_Internal(Params);
```

두 경우의 차이는 `Params.Template` — 프로퍼티 초기값을 어디서 복사해오는가다.

```
CDO 생성 시:
  Template 미지정 → 서브오브젝트 클래스 자체의 CDO가 기준
  AddDefaultSubobject() 호출 → UClass 서브오브젝트 목록에 등록  ← CDO만 해당

일반 인스턴스 생성 시 (SpawnActor 기본):
  Template = CDO의 서브오브젝트  → CDO 서브오브젝트 프로퍼티 복사
  AddDefaultSubobject() 호출 안 함  ← 인스턴스는 등록 불필요

커스텀 Template 지정 시 (Params.Template = ExistingActor):
  Template = ExistingActor의 해당 서브오브젝트 → 그 값 복사
```

```cpp
// UObjectGlobals.cpp:6020 — CDO 생성 시에만 실행
if (Outer->HasAnyFlags(RF_ClassDefaultObject) && Outer->GetClass()->GetSuperClass())
{
    Outer->GetClass()->AddDefaultSubobject(Result, ReturnType);
}
```

각 Actor 인스턴스는 **자기만의 독립된 MeshComp**를 갖는다.  
CDO의 MeshComp는 공유 객체가 아니라 초기값의 원본이다.

```
SpawnActor<AMyActor>() 호출 시:
  생성자 실행
    → CreateDefaultSubobject("MeshComp")
        → StaticConstructObject_Internal()     ← 새 MeshComp 생성
            → CDO의 MeshComp를 Template으로   ← 초기값 복사
        → 새 MeshComp 반환 (공유 아님)
```

---

## CDO 등록과 인스턴스 추적

```
CDO 생성 시: UClass 서브오브젝트 목록에 등록 (AddDefaultSubobject)
  CDO(AMyActor)
    ├── MeshComp  ← UClass가 알고 있음
    └── MyData    ← UClass가 알고 있음

인스턴스 생성 시: UClass 목록에 등록하지 않음
  AMyActor 인스턴스
    ├── MeshComp  ← OwnedComponents(UPROPERTY) 또는 UPROPERTY 변수로 추적
    └── MyData    ← UPROPERTY 변수로만 추적
```

에디터에서 컴포넌트 기본값을 수정하면 CDO 서브오브젝트에 저장된다.

---

## UPROPERTY 없을 때 어떻게 되나

### UActorComponent 계열

`UActorComponent` 서브오브젝트는 인스턴스 생성 시 `AActor::OwnedComponents`(UPROPERTY)에 자동 추가된다.  
UPROPERTY 변수가 없어도 GC에 수거되지는 않는다.  
그러나 포인터 접근·에디터 노출·직렬화가 불가능하므로 의미 없는 컴포넌트가 된다.

### 일반 UObject 계열

`UActorComponent`가 아닌 일반 `UObject`는 `OwnedComponents`에 들어가지 않는다.  
UPROPERTY 없이 만든 인스턴스 서브오브젝트를 붙잡아 줄 참조가 없으므로 **GC에 수거될 수 있다.**

### 올바른 패턴

```cpp
UPROPERTY()
UStaticMeshComponent* MeshComp;   // UActorComponent: OwnedComponents 백업 있지만 UPROPERTY 필수

UPROPERTY()
UMyObject* Data;                   // 일반 UObject: UPROPERTY 없으면 GC 위험

AMyActor::AMyActor()
{
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
    Data     = CreateDefaultSubobject<UMyObject>(TEXT("Data"));
}
```

| 항목 | UPROPERTY 있음 | UPROPERTY 없음 |
|------|---------------|----------------|
| GC 안전 (컴포넌트) | O | O (OwnedComponents) |
| GC 안전 (일반 UObject) | O | **X** |
| GC auto-null | O | X — dangling 위험 |
| 에디터 노출·직렬화 | O | X |
| 포인터 접근 | O | X |

---

## 생성자 밖에서 호출하면 안 되는 이유

`CreateDefaultSubobject`는 **생성자 안인지 검사**한다 (소스 5950번 줄).  
생성자 밖(BeginPlay 등)에서 호출하면 Fatal 로그를 남기고 nullptr를 반환한다.

```cpp
// UObjectGlobals.cpp:5950
UE_CLOG(!FUObjectThreadContext::Get().IsInConstructor, LogUObjectGlobals, Fatal, ...);
```

런타임에 컴포넌트를 동적으로 추가하려면 `NewObject + RegisterComponent`를 사용한다.  
→ [02_creation.md — 런타임 컴포넌트 추가](02_creation.md)

---

## CreateDefaultSubobject vs NewObject 비교

| 항목 | CreateDefaultSubobject | NewObject (런타임) |
|------|------------------------|-------------------|
| 호출 위치 | 생성자 안에서만 | 어디서든 |
| 내부 생성 방식 | StaticConstructObject_Internal | StaticConstructObject_Internal |
| CDO 등록 | O (CDO 생성 시) | X |
| Template | CDO 서브오브젝트 | 지정하지 않으면 클래스 CDO |
| 직렬화 | O | X (기본) |
| Blueprint 노출 | O | X |
| 사용 목적 | 기본 구성 정의 | 런타임 동적 추가 |

---

## 내 노트
