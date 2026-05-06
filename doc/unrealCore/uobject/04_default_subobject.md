# DefaultSubobject

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectGlobals.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObjectGlobals.cpp`

---

## CreateDefaultSubobject란

Actor(또는 UObject) **생성자 안에서만** 사용할 수 있는 특수 팩토리 함수다.  
CDO가 만들어질 때 함께 생성되어 Actor의 "기본 구성"을 정의한다.

```cpp
AMyActor::AMyActor()
{
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
    MeshComp->SetupAttachment(RootComponent);

    SpringArm = CreateDefaultSubobject<USpringArmComponent>(TEXT("SpringArm"));
    SpringArm->SetupAttachment(RootComponent);
}
```

`TEXT("MeshComp")`는 컴포넌트의 고유 이름이다.  
이 이름이 에디터 Outliner와 Blueprint 컴포넌트 패널에 표시되고, 직렬화(저장) 키로도 사용된다.

---

## 생성자 밖에서 호출하면 안 되는 이유

`CreateDefaultSubobject`는 내부적으로 **현재 CDO 생성 중인지 검사**한다.  
생성자 밖(BeginPlay 등)에서 호출하면 `ensureMsg`가 발동하고 nullptr를 반환한다.

```cpp
void AMyActor::BeginPlay()
{
    Super::BeginPlay();

    // 이건 잘못된 사용 — ensureMsg 발동 후 nullptr 반환
    UStaticMeshComponent* Bad = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Bad"));
}
```

런타임에 컴포넌트를 동적으로 추가하려면 `NewObject + RegisterComponent`를 사용한다.  
→ [02_creation.md — 런타임 컴포넌트 추가](02_creation.md)

---

## CDO와의 관계

`CreateDefaultSubobject`로 만든 컴포넌트는 CDO의 기본 컴포넌트로 등록된다.  
Actor 인스턴스를 스폰하면 이 CDO 구성을 복사해 각 인스턴스의 컴포넌트를 만든다.

```
CDO(AMyActor)
  ├── MeshComp (CDO 컴포넌트)
  └── SpringArm (CDO 컴포넌트)

스폰된 AMyActor 인스턴스
  ├── MeshComp (CDO에서 복사)
  └── SpringArm (CDO에서 복사)
```

에디터에서 컴포넌트 기본값을 수정하면 CDO 컴포넌트에 저장된다.

---

## Subobject vs 일반 NewObject 비교

| 항목 | CreateDefaultSubobject | NewObject (런타임) |
|------|------------------------|-------------------|
| 호출 위치 | 생성자 안에서만 | 어디서든 |
| 직렬화 | O (에디터 저장·로드) | X (기본) |
| Blueprint 노출 | O (컴포넌트 패널) | X |
| CDO와 연동 | O | X |
| 사용 목적 | Actor의 기본 구성 | 런타임 동적 추가 |

---

## 내 노트

