# Actor와 Component 개념

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/Actor.h`  
> `Engine/Source/Runtime/Engine/Classes/Components/ActorComponent.h`  
> `Engine/Source/Runtime/Engine/Classes/Components/SceneComponent.h`

---

## Actor란

Actor는 **월드에 존재할 수 있는 UObject**다.  
레벨에 배치하거나 런타임에 스폰할 수 있는 모든 오브젝트의 기반 클래스다.

Actor 자체는 Transform을 직접 갖지 않는다.  
위치·회전·스케일은 `RootComponent`(SceneComponent)가 담당한다.

```cpp
class AActor : public UObject
{
    // 트랜스폼의 기준이 되는 루트 컴포넌트
    UPROPERTY()
    TObjectPtr<USceneComponent> RootComponent;

    // 이 Actor에 붙은 모든 컴포넌트
    UPROPERTY()
    TArray<TObjectPtr<UActorComponent>> OwnedComponents;
};
```

Actor가 할 수 있는 것:
- 월드에 배치 / 스폰 / 소멸
- Tick (매 프레임 실행)
- 네트워크 복제
- 입력 처리
- Component 소유

---

## Component란

Component는 **Actor에 붙어 특정 기능을 담당하는 UObject**다.  
Actor에 기능을 조합해 붙이는 방식으로 복잡한 오브젝트를 만든다.

```
ACharacter
  ├── UCapsuleComponent        (충돌 루트)
  ├── USkeletalMeshComponent  (메시 렌더링)
  ├── UCharacterMovementComponent (이동)
  └── UCameraComponent        (카메라 시점)
```

각 Component가 독립적인 역할을 하고, Actor는 이것들을 조율한다.

---

## ActorComponent vs SceneComponent

| 구분 | ActorComponent | SceneComponent |
|------|---------------|----------------|
| Transform | 없음 | 있음 (위치·회전·스케일) |
| 첨부 트리 | 참여 불가 | 부모-자식 첨부 가능 |
| 용도 | 순수 로직 컴포넌트 | 공간 정보가 필요한 컴포넌트 |
| 예시 | UCharacterMovementComponent, UHealthComponent | UMeshComponent, UCameraComponent |

```
UObject
  └── UActorComponent           ← Transform 없음
        └── USceneComponent     ← Transform 있음, 첨부 트리 참여
              ├── UMeshComponent
              ├── UCameraComponent
              ├── ULightComponent
              └── ...
```

---

## 첨부 트리 (Attachment Tree)

SceneComponent는 부모-자식 관계로 계층을 구성할 수 있다.  
자식은 부모의 Transform을 기준으로 상대적 위치를 가진다.

```cpp
// C++ 생성자에서 첨부
CameraComponent = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
CameraComponent->SetupAttachment(GetRootComponent());

// 런타임에 첨부
MeshComponent->AttachToComponent(
    ParentComponent,
    FAttachmentTransformRules::KeepRelativeTransform,
    SocketName   // 소켓에 붙이려면 소켓 이름 지정
);
```

부모가 움직이면 자식이 따라 움직인다.  
자식의 WorldTransform = 부모의 WorldTransform × 자식의 RelativeTransform.

```
RootComponent (위치: 0,0,0)
  └── MeshComponent (상대: 0,0,0)
        └── CameraComponent (상대: 0,0,100)   ← 월드 위치: 0,0,100
```

---

## RootComponent

Actor의 Transform 기준점이 되는 최상위 SceneComponent.

```cpp
// C++ 생성자에서 RootComponent 설정
USphereComponent* SphereComp = CreateDefaultSubobject<USphereComponent>(TEXT("Root"));
RootComponent = SphereComp;

// Actor의 위치 = RootComponent의 위치
FVector ActorLocation = GetActorLocation();  // = RootComponent->GetComponentLocation()
```

RootComponent가 없으면 Actor를 월드 공간에 배치할 수 없다.  
`AActor::SetActorLocation()`은 내부에서 `RootComponent->SetWorldLocation()`을 호출한다.

---

## 소유 관계

### Actor → Component

Actor가 Component를 소유한다.  
Component는 `GetOwner()`로 자신을 소유한 Actor를 참조한다.

```cpp
// Component에서 자신의 Actor에 접근
AActor* MyActor = GetOwner();
ACharacter* Character = Cast<ACharacter>(GetOwner());
```

### Actor → Actor (Instigator / Owner)

Actor도 다른 Actor를 Owner로 가질 수 있다.

```cpp
// 스폰 시 Owner 지정
FActorSpawnParameters Params;
Params.Owner = this;
AProjectile* Bullet = GetWorld()->SpawnActor<AProjectile>(ProjectileClass, Location, Rotation, Params);

// Projectile에서 Owner 확인
AActor* Shooter = GetOwner();
```

Owner는 네트워크 복제에서 의미를 가진다.  
`bOnlyRelevantToOwner = true`면 Owner 클라이언트에게만 복제된다.

---

## 컴포넌트 생성 방법

### 생성자에서 (기본 컴포넌트)

```cpp
AMyActor::AMyActor()
{
    // C++ 생성자에서 생성 — CDO에 포함, WBP에서 보임
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
    MeshComp->SetupAttachment(RootComponent);
}
```

### 런타임에 동적 생성

```cpp
// BeginPlay 등 런타임에서 생성
UParticleSystemComponent* FX = NewObject<UParticleSystemComponent>(this);
FX->SetupAttachment(RootComponent);
FX->RegisterComponent();   // World에 등록 (OnRegister 호출)
FX->Activate();
```

동적 생성 컴포넌트는 `RegisterComponent()`를 명시적으로 호출해야 World에 등록된다.

---

## 내 노트

