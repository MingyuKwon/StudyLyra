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

## CDO 등록과 인스턴스 복사

`CreateDefaultSubobject`로 만든 서브오브젝트는 타입 무관하게 **CDO의 서브오브젝트 목록에 등록**된다.  
Actor 인스턴스가 스폰될 때 CDO의 서브오브젝트 목록을 보고 각 인스턴스에 복사본을 만든다.

```
CDO(AMyActor)
  ├── MeshComp (CDO 서브오브젝트)    ← CDO에 등록됨
  └── MyData   (CDO 서브오브젝트)    ← UObject도 동일하게 등록됨

스폰된 AMyActor 인스턴스
  ├── MeshComp (CDO에서 복사)
  └── MyData   (CDO에서 복사)
```

에디터에서 컴포넌트 기본값을 수정하면 CDO 서브오브젝트에 저장된다.

---

## UPROPERTY 없을 때 어떻게 되나

### UActorComponent 계열

`UActorComponent` 서브오브젝트는 인스턴스 생성 시 `AActor::OwnedComponents`(UPROPERTY)에 자동 추가된다.  
UPROPERTY 변수로 저장하지 않아도 GC에 수거되지는 않는다.  
그러나 포인터 접근·에디터 노출·직렬화가 불가능하므로 의미 없는 컴포넌트가 된다.

```cpp
AMyActor::AMyActor()
{
    // OwnedComponents가 잡아주므로 GC는 안전
    // 하지만 포인터 없으므로 접근 불가, 에디터에서도 안 보임
    CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
}
```

### 일반 UObject 계열

`UActorComponent`가 아닌 일반 `UObject`는 `OwnedComponents`에 들어가지 않는다.  
UPROPERTY 없이 만든 인스턴스 복사본을 붙잡아 줄 참조가 없으므로 **GC에 수거될 수 있다.**

```cpp
AMyActor::AMyActor()
{
    // CDO 등록은 됨, 하지만 인스턴스 복사본을 잡아줄 UPROPERTY 없음
    CreateDefaultSubobject<UMyObject>(TEXT("Data"));  // 위험
}
```

### UPROPERTY가 있어야 하는 이유

```cpp
UPROPERTY()                          // 반드시 필요
UStaticMeshComponent* MeshComp;

UPROPERTY()
UMyObject* Data;

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
| GC auto-null | O | X (dangling 위험) |
| 에디터 노출·직렬화 | O | X |
| 포인터 접근 | O | X (변수 없음) |

### Raw pointer (UPROPERTY 없는 포인터)

```cpp
UStaticMeshComponent* MeshComp;  // UPROPERTY 없음
```

GC가 컴포넌트를 수거할 때 UPROPERTY 포인터는 자동으로 null이 되지만  
raw pointer는 null이 안 된다 → dangling pointer → 크래시.

---

## 생성자 밖에서 호출하면 안 되는 이유

`CreateDefaultSubobject`는 내부적으로 **CDO 생성 중인지 검사**한다.  
생성자 밖(BeginPlay 등)에서 호출하면 `ensureMsg`가 발동하고 nullptr를 반환한다.

```cpp
void AMyActor::BeginPlay()
{
    Super::BeginPlay();
    // 잘못된 사용 — ensureMsg 발동 후 nullptr 반환
    UStaticMeshComponent* Bad = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Bad"));
}
```

런타임에 컴포넌트를 동적으로 추가하려면 `NewObject + RegisterComponent`를 사용한다.  
→ [02_creation.md — 런타임 컴포넌트 추가](02_creation.md)

---

## CreateDefaultSubobject vs NewObject 비교

| 항목 | CreateDefaultSubobject | NewObject (런타임) |
|------|------------------------|-------------------|
| 호출 위치 | 생성자 안에서만 | 어디서든 |
| CDO 등록 | O | X |
| 직렬화 | O | X (기본) |
| Blueprint 노출 | O | X |
| 사용 목적 | 기본 구성 정의 | 런타임 동적 추가 |

---

## 내 노트
