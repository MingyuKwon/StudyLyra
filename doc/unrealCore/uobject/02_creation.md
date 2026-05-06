# UObject 생성 방법

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectGlobals.h`  
> `Engine/Source/Runtime/Engine/Private/LevelActor.cpp`

UObject를 상속한 클래스라도 **종류에 따라 생성 방법이 다르다.**  
C++ `new`는 절대 사용하지 않는다.

`new UMyObject()`를 호출하면 UObject 생성자가 내부적으로 `GUObjectArray`에 자신을 등록한다.  
GC는 이 객체의 **존재를 알고 있다.** 하지만 GC는 루트셋에서 출발해 UPROPERTY 참조를 따라가며 "살아있음"을 표시하는 방식으로 동작한다.

```cpp
UMyObject* Ptr = new UMyObject();
// GUObjectArray에 등록됨 — GC가 존재는 앎
// 그러나 어떤 UPROPERTY도 이 객체를 가리키지 않음
// → GC가 "아무도 참조 안 함" 으로 판단
// → 다음 GC 사이클에 수거

Ptr->DoSomething();   // 이미 수거된 객체 — dangling pointer → 크래시
```

GC가 몰라서 수거되는 것이 아니라,  
**GC가 알고 있지만 UPROPERTY 참조가 없어 '쓰레기'로 판단해 수거**하는 것이다.  
UPROPERTY 참조는 GC 수거 시 자동으로 null이 되지만, raw pointer는 null이 되지 않아 dangling pointer가 된다.

---

## UObject — NewObject

순수 `UObject` 자식 클래스를 런타임에 생성하는 함수.

```cpp
// 기본 형태
UMyObject* Obj = NewObject<UMyObject>(
    this,                        // Outer — 이 객체를 소유할 UObject
    UMyObject::StaticClass()     // 생성할 클래스 (생략 시 T::StaticClass() 자동 사용)
);

// 클래스를 런타임에 결정할 때
TSubclassOf<UMyObject> ClassToSpawn = ...;
UMyObject* Obj = NewObject<UMyObject>(this, ClassToSpawn);
```

**Outer란?**  
생성된 객체의 소유자. GC는 Outer → Object 방향으로 소유권 체인을 추적한다.  
Outer가 수거되면 Inner도 함께 수거 대상이 된다.  
컴포넌트라면 Actor를 Outer로, 일반 데이터 오브젝트라면 `this` 또는 `GetTransientPackage()`를 쓴다.

```cpp
// Outer를 잘못 지정하면 생기는 문제
UMyData* Data = NewObject<UMyData>(GetTransientPackage()); // OK — 전역 Transient 패키지
UMyData* Data = NewObject<UMyData>();                      // OK — Outer 생략 시 Transient 패키지
UMyData* Data = NewObject<UMyData>(nullptr);               // Outer 없음 — 위험
```

---

## AActor — SpawnActor

AActor는 반드시 월드를 통해 스폰한다. NewObject로 만들면 월드에 등록되지 않는다.

```cpp
AMyActor* Actor = GetWorld()->SpawnActor<AMyActor>(
    AMyActor::StaticClass(),
    SpawnTransform
);
```

내부 흐름과 Deferred 스폰은 → [actor/02_spawn.md](../actor/02_spawn.md)

---

## UActorComponent / UPrimitiveComponent

컴포넌트를 Actor에 추가하는 방법은 **타이밍에 따라 두 가지**로 나뉜다.

### 생성자에서 — CreateDefaultSubobject

Actor·UObject **생성자 안에서만** 사용할 수 있는 특수 함수.  
CDO 생성 시 컴포넌트를 미리 만들어 Actor의 기본 구성을 정의한다.

```cpp
AMyActor::AMyActor()
{
    // 반드시 생성자 안에서만 호출
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
    MeshComp->SetupAttachment(RootComponent);
}
```

상세 설명 → [04_default_subobject.md](04_default_subobject.md)

### 런타임에서 — NewObject + RegisterComponent

게임 도중 동적으로 컴포넌트를 추가할 때 사용한다.

```cpp
void AMyActor::AddMeshAtRuntime()
{
    UStaticMeshComponent* NewMesh = NewObject<UStaticMeshComponent>(
        this,                               // Outer = 이 Actor
        UStaticMeshComponent::StaticClass()
    );

    NewMesh->SetStaticMesh(SomeMesh);
    NewMesh->SetupAttachment(RootComponent);
    NewMesh->RegisterComponent();           // 월드·렌더링 시스템에 등록
}
```

`RegisterComponent()`를 빠뜨리면 컴포넌트가 월드에 존재하지 않는다.

---

## 생성 방법 요약

| 클래스 종류 | 생성 함수 | 비고 |
|-------------|-----------|------|
| `UObject` 자식 | `NewObject<T>(Outer)` | 생성자·런타임 모두 가능 |
| `AActor` 자식 | `GetWorld()->SpawnActor<T>()` | 월드 필수 |
| 컴포넌트 (생성자) | `CreateDefaultSubobject<T>(Name)` | 생성자 안에서만 |
| 컴포넌트 (런타임) | `NewObject<T>(Actor)` + `RegisterComponent()` | 런타임 동적 추가 |

---

## 내 노트

