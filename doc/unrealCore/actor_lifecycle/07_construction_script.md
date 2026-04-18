# ExecuteConstruction과 Construction Script

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/Actor.h`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Private/BlueprintGeneratedClass.cpp`

---

## "생성자"가 두 가지 의미로 쓰인다

언리얼에서 "Construction"이라는 단어가 두 개의 전혀 다른 개념에 붙어 있어서 헷갈린다.

| 용어 | 실제 의미 | 호출 횟수 |
|------|----------|----------|
| C++ 생성자 `AMyActor()` | 클래스 인스턴스 메모리 할당 시 초기화 | 딱 한 번 |
| Construction Script | Actor의 현재 설정값 기준으로 구성을 재계산 | 여러 번 가능 |

이 둘은 완전히 다른 것이다.

---

## ExecuteConstruction 구조

```cpp
// Actor.h:3442
bool AActor::ExecuteConstruction(...)
```

```
ExecuteConstruction()
  ├─ OnConstruction(Transform)   ← C++ override 포인트 (Actor.h:3448)
  └─ SCS(SimpleConstructionScript) 실행
       └─ BP에서 추가한 컴포넌트들을 여기서 생성/부착
```

**SCS(SimpleConstructionScript)** 는 Blueprint 에디터에서 "컴포넌트 패널"에 추가한 컴포넌트 구성을 저장하는 데이터다. `ExecuteConstruction`이 이 레시피를 실행해서 컴포넌트를 실제로 생성하고 Actor에 붙인다.

> `Actor.h:238` 주석:  
> *"OnConstruction: Called at the end of ExecuteConstruction, which calls the blueprint construction script.  
> This is called after all blueprint-created components are fully created and registered."*

---

## 왜 여러 번 실행되나

C++ 생성자는 "클래스를 만든다"는 개념이라 한 번만 불린다.  
Construction Script는 **"현재 설정값 기준으로 Actor를 조립한다"** 는 개념이라, 설정이 바뀌면 재조립이 필요하다.

에디터에서 배치된 Actor의 프로퍼티를 변경하면:

```
사용자가 HitPoints = 100 → 200 으로 변경
  └─ RerunConstructionScripts() 호출
       └─ ExecuteConstruction()
            ├─ OnConstruction()
            └─ SCS 재실행 (컴포넌트 재구성)
```

BP Construction Script 안에서 이런 패턴을 쓸 수 있기 때문이다:

```
// BP Construction Script 예시
if HitPoints > 150:
    AddComponent(HeavyArmorMesh)   ← 값에 따라 컴포넌트가 달라짐
else:
    AddComponent(LightArmorMesh)
```

프로퍼티 값에 따라 **컴포넌트 구성 자체가 달라질 수 있어서**, 값이 바뀌면 처음부터 다시 계산해야 한다.

---

## 언제 실행되나

```
[에디터]
  - Actor를 레벨에 배치할 때
  - 프로퍼티 패널에서 값을 변경할 때
  - Actor를 이동/회전할 때
  → 매번 RerunConstructionScripts() → ExecuteConstruction()

[런타임 — 동적 스폰]
  SpawnActor()
    └─ PostSpawnInitialize()
         └─ ExecuteConstruction()  ← 스폰 시 한 번 실행

[런타임 — 배치 Actor]
  쿠킹 빌드:   실행 안 함 (결과가 직렬화에 포함됨)
  PIE:         실행 안 함 (에디터 레벨을 복제하므로 이미 적용됨)
  에디터 빌드: 레벨 로드 시 실행
```

---

## OnConstruction vs C++ 생성자 — 무엇을 어디에 두나

```cpp
AMyActor::AMyActor()
{
    // ✅ 여기에 둘 것:
    // - bCanEverTick, bReplicates 같은 클래스 기본 설정
    // - CreateDefaultSubobject (컴포넌트 생성)
    // - World 없이도 안전한 초기화
}

void AMyActor::OnConstruction(const FTransform& Transform)
{
    // ✅ 여기에 둘 것:
    // - 프로퍼티 값에 따라 달라지는 비주얼/구성
    // - 에디터에서 바로 확인하고 싶은 것

    // ❌ 여기에 두면 안 되는 것:
    // MyArray.Add(...)   ← 에디터에서 이동할 때마다 중복 추가됨
    // ASC->GiveAbility() ← 게임플레이 시스템 접근, 런타임에 여러 번 불릴 수 있음
}

void AMyActor::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    // ✅ 게임 로직 초기화는 여기서
    // - 다른 컴포넌트 참조
    // - 상태 초기화 (배치/스폰 모두 여기서 만남, 게임 월드 보장)
}
```

---

## 전체 흐름에서의 위치

```
C++ 생성자          메모리 초기화. World 없음. 딱 한 번.
     │
RegisterAllComponents
     │
PostActorCreated    스폰 완료 훅 (배치 Actor엔 없음)
     │
ExecuteConstruction ← 현재 설정으로 Actor 조립. 에디터에서 여러 번 가능.
  OnConstruction()
  SCS 실행 (BP 컴포넌트 생성)
     │
PostInitializeComponents  구성 완료 후 게임 초기화. 한 번. 배치/스폰 공통.
     │
BeginPlay           게임 시작. 한 번.
```
