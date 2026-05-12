# Actor 검색 — TActorIterator / GetAllActorsOfClass

> 소스:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/ActorIterator.h`  
> `Engine/Source/Runtime/Engine/Classes/Kismet/GameplayStatics.h`

게임 런타임에 특정 UWorld 안의 Actor 인스턴스를 검색하는 방법.

---

## 데이터 출처 — UWorld → ULevel::Actors

`TActorIterator`는 `GUObjectArray` 전체가 아닌
**`UWorld`가 관리하는 레벨별 Actor 배열**을 순회한다.

```
UWorld
  └── TArray<ULevel*> Levels
        ├── ULevel (Persistent Level)
        │     └── TArray<AActor*> Actors  ← 여기를 순회
        ├── ULevel (Streaming Level A)
        │     └── TArray<AActor*> Actors
        └── ULevel (Streaming Level B)
              └── TArray<AActor*> Actors
```

`ULevel::Actors`는 다음 시점에 갱신된다.

| 시점 | 동작 |
|------|------|
| `SpawnActor()` | `ULevel::AddActor()` → Actors 배열에 추가 |
| `AActor::Destroy()` | 즉시 제거가 아닌 PendingKill 표시 → 다음 틱에 배열에서 제거 |
| 스트리밍 레벨 로드/언로드 | 해당 ULevel 전체가 추가/제거 |

---

## TActorIterator 초기화와 동작

`UWorld*`를 받아 `World->Levels` 배열을 순서대로 돌면서
각 `ULevel::Actors`를 순회한다.

```cpp
// ActorIterator.h (개념적 구현)
template<class T>
class TActorIterator
{
    UWorld* World;
    int32   LevelIndex = 0;   // World->Levels[LevelIndex]
    int32   ActorIndex = -1;  // 현재 레벨의 Actors[ActorIndex]

    void Advance()
    {
        while (true)
        {
            ++ActorIndex;

            // 현재 레벨 소진 → 다음 레벨로
            while (ActorIndex >= World->Levels[LevelIndex]->Actors.Num())
            {
                ++LevelIndex;
                ActorIndex = 0;
                if (LevelIndex >= World->Levels.Num()) return; // 끝
            }

            AActor* Actor = World->Levels[LevelIndex]->Actors[ActorIndex];
            if (!IsValid(Actor)) continue;           // PendingKill 제외
            if (Actor->IsA(T::StaticClass())) break; // 타입 일치
        }
    }
};
```

`TObjectIterator`와 달리 `IsValid()` 체크가 포함되어 있어
PendingKill 상태인 Actor는 자동으로 건너뛴다.

---

## 사용 예시

### TActorIterator

```cpp
// 현재 월드의 모든 AMyActor 순회
for (TActorIterator<AMyActor> It(GetWorld()); It; ++It)
{
    AMyActor* Actor = *It;
    Actor->DoSomething();
}

// 파생 클래스 포함 (ACharacter 및 그 자식 클래스 전부)
for (TActorIterator<ACharacter> It(GetWorld()); It; ++It)
{
    ACharacter* Char = *It;
}
```

### GetAllActorsOfClass

```cpp
TArray<AActor*> Actors;
UGameplayStatics::GetAllActorsOfClass(
    GetWorld(),
    AMyActor::StaticClass(),
    Actors
);

for (AActor* Actor : Actors)
{
    Cast<AMyActor>(Actor)->DoSomething();
}
```

내부 구현은 `TActorIterator`를 그대로 사용한다.

```cpp
// GameplayStatics.cpp (개념적 구현)
void UGameplayStatics::GetAllActorsOfClass(
    const UObject* WorldContextObject,
    TSubclassOf<AActor> ActorClass,
    TArray<AActor*>& OutActors)
{
    OutActors.Reset();
    UWorld* World = GEngine->GetWorldFromContextObject(WorldContextObject);
    for (TActorIterator<AActor> It(World, ActorClass); It; ++It)
    {
        OutActors.Add(*It);
    }
}
```

---

## 성능 주의

두 방법 모두 **전체 레벨의 Actor 배열을 선형 순회**한다.

| 방법 | 문제점 |
|------|--------|
| 매 틱 `TActorIterator` | Actor 수에 비례한 비용이 매 프레임 발생 |
| 매 틱 `GetAllActorsOfClass` | 추가로 TArray 할당·복사 비용까지 발생 |

Actor 수가 많은 게임에서는 직접 참조 캐시(`TArray<TWeakObjectPtr<>>`),
서브시스템, 또는 GameState에 목록을 유지하는 패턴이 권장된다.

---

## TObjectIterator vs TActorIterator

| | `TObjectIterator<T>` | `TActorIterator<T>` |
|--|----------------------|---------------------|
| 데이터 출처 | GUObjectArray (전역) | UWorld → ULevel::Actors |
| 범위 | 전체 메모리 | 특정 UWorld |
| CDO 포함 | O (수동 필터 필요) | X (자동 제외) |
| PendingKill 처리 | 수동 필터 필요 | 자동 제외 |
| 대상 타입 | 모든 UObject | AActor 파생만 |
| 주요 용도 | 에디터 툴·디버깅 | 게임 런타임 |

---

## 내 노트
