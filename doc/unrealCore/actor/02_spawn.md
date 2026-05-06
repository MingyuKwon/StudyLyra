# SpawnActor 메커니즘

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/World.h`  
> `Engine/Source/Runtime/Engine/Private/LevelActor.cpp`  
> `Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h`

---

## Spawn이란

Spawn은 **런타임에 Actor를 월드에 동적으로 생성하는 것**이다.  
에디터에서 레벨에 미리 배치하는 것과 달리, 게임 중 코드로 Actor를 만들어낸다.

```cpp
// 기본 스폰
AProjectile* Bullet = GetWorld()->SpawnActor<AProjectile>(
    ProjectileClass,      // 생성할 클래스
    SpawnLocation,        // 월드 위치
    SpawnRotation         // 회전
);
```

---

## SpawnActor 호출 체인

```
UWorld::SpawnActor<T>(Class, Location, Rotation, Params)
    │
    └─ UWorld::SpawnActor(Class, &Transform, Params)
          │
          ├─ 1. UObject 할당 (NewObject)
          ├─ 2. PostInitProperties()
          ├─ 3. ExchangeNetRoles()           ← 서버/클라이언트 Role 설정
          ├─ 4. ExecuteConstruction()        ← Construction Script
          ├─ 5. PostActorConstruction()
          │       ├─ PreInitializeComponents()
          │       ├─ InitializeComponents()
          │       └─ PostInitializeComponents()
          ├─ 6. 충돌 검사 (SpawnCollisionHandling)
          ├─ 7. World에 Actor 등록
          └─ 8. BeginPlay() ← World가 이미 플레이 중이면 즉시 호출
```

> **참고**  
> 레벨에 배치된 Actor는 6번 충돌 검사를 건너뛴다.  
> 배치 vs 스폰의 전체 차이 → [lifecycle/06_placed_vs_spawned.md](lifecycle/06_placed_vs_spawned.md)

---

## FActorSpawnParameters

SpawnActor에 옵션을 넘기는 구조체.

```cpp
FActorSpawnParameters Params;
Params.Owner      = this;                // 소유 Actor 지정
Params.Instigator = GetInstigator();     // 피해/이벤트 발생 주체
Params.Name       = FName("MyBullet");   // Actor 이름 (디버그용)
Params.SpawnCollisionHandlingOverride =
    ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

AProjectile* Bullet = GetWorld()->SpawnActor<AProjectile>(
    ProjectileClass, Location, Rotation, Params
);
```

---

## ESpawnActorCollisionHandlingMethod

스폰 위치에 충돌이 있을 때 어떻게 처리할지 결정한다.

```cpp
namespace ESpawnActorCollisionHandlingMethod
{
    enum Type
    {
        Undefined,                     // 클래스 기본값 사용
        AlwaysSpawn,                   // 충돌 무시하고 항상 스폰
        AdjustIfPossibleButAlwaysSpawn,// 가능하면 위치 조정, 안 되면 그냥 스폰
        AdjustIfPossibleButDontSpawnIfStillColliding, // 조정 실패 시 스폰 안 함
        DontSpawnIfColliding,          // 충돌 있으면 스폰 안 함 (null 반환)
    };
}
```

| 옵션 | 충돌 시 동작 | 반환값 |
|------|-------------|--------|
| `AlwaysSpawn` | 무시하고 스폰 | 항상 유효 |
| `AdjustIfPossibleButAlwaysSpawn` | 위치 보정 시도 → 실패해도 스폰 | 항상 유효 |
| `AdjustIfPossibleButDontSpawnIfStillColliding` | 위치 보정 시도 → 실패 시 null | null 가능 |
| `DontSpawnIfColliding` | 충돌 시 바로 null | null 가능 |

```cpp
// DontSpawnIfColliding 사용 시 null 체크 필수
AEnemy* Enemy = GetWorld()->SpawnActor<AEnemy>(EnemyClass, Location, Rotation, Params);
if (Enemy)
{
    Enemy->Initialize();
}
```

---

## Deferred Spawn — 스폰 전에 프로퍼티 설정

일반 SpawnActor는 생성과 동시에 초기화까지 완료된다.  
생성 후 BeginPlay 전에 프로퍼티를 설정하고 싶으면 Deferred Spawn을 쓴다.

```cpp
// 1단계: Actor 생성만 하고 초기화는 보류
AMyActor* Actor = GetWorld()->SpawnActorDeferred<AMyActor>(
    AMyActor::StaticClass(),
    SpawnTransform,
    Owner,
    Instigator,
    ESpawnActorCollisionHandlingMethod::AlwaysSpawn
);

// 2단계: BeginPlay 전에 프로퍼티 설정
Actor->SetDamage(100.f);
Actor->SetTeam(ETeam::Red);

// 3단계: 초기화 완료 (PostInitializeComponents → BeginPlay 호출됨)
UGameplayStatics::FinishSpawningActor(Actor, SpawnTransform);
```

`SpawnActorDeferred()`는 내부적으로 `PostInitializeComponents()`까지만 실행하고 멈춘다.  
`FinishSpawningActor()`를 호출해야 `BeginPlay()`가 실행된다.

---

## SpawnActor 반환값 체크

SpawnActor는 실패 시 `nullptr`을 반환한다.

```cpp
AMyActor* Spawned = GetWorld()->SpawnActor<AMyActor>(MyClass, Transform);

// 항상 nullptr 체크
if (!Spawned)
{
    UE_LOG(LogTemp, Warning, TEXT("SpawnActor failed"));
    return;
}
```

실패 원인:
- `DontSpawnIfColliding` 조건에서 충돌 감지
- 유효하지 않은 클래스 (추상 클래스, null 등)
- 유효하지 않은 World

---

## 내 노트

