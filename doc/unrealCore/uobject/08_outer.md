# Outer

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectBase.h`  
> `Engine/Source/Runtime/CoreUObject/Private/GarbageCollection.cpp`

---

## Outer란

모든 UObject는 생성 시 **Outer**를 지정한다.  
Outer는 이 오브젝트의 "소유자"이자 "소속 컨텍스트"다.

```cpp
UMyObject* Obj = NewObject<UMyObject>(this);   // Outer = this
```

Outer는 세 가지 역할을 가진다.

---

## 역할 1 — 이름·경로 계층

UObject는 전부 경로 이름을 가진다.  
`GetPathName()`이 Outer를 타고 올라가며 이 경로를 조립한다.

```
/Game/MyLevel.MyActor.MyMeshComp

UPackage (/Game/MyLevel)
  └── AMyActor               ← Outer = UPackage
        └── UStaticMeshComp  ← Outer = AMyActor
```

에디터 Outliner, 로그 출력, 애셋 참조가 이 경로를 기준으로 동작한다.

---

## 역할 2 — 패키지 소속 (직렬화)

Outer를 계속 타고 올라가면 반드시 **UPackage** 에 도달한다.  
이 UPackage가 이 오브젝트가 저장될 `.uasset` 파일이다.

```cpp
NewObject<UMyObject>(this);                  // → this의 패키지에 소속, 저장 가능
NewObject<UMyObject>(GetTransientPackage()); // → Transient 패키지, 저장 안 됨
```

Outer를 잘못 지정하면 예상치 못한 패키지에 묶이거나 직렬화가 꼬인다.

---

## 역할 3 — 수명 연계

Outer 관계와 UPROPERTY는 **별개**다. Outer를 지정해도 UPROPERTY가 자동으로 생기지 않는다.

```cpp
// Outer = this 지정, UPROPERTY 없음 → GC가 Inner를 수거
UMyObject* Obj = NewObject<UMyObject>(this);

// Outer = this 지정, UPROPERTY에 저장 → Inner 살아남음
UPROPERTY()
UMyObject* MyData;
MyData = NewObject<UMyObject>(this);
```

GC는 오직 UPROPERTY(Token Stream)만 추적한다. Outer 관계 자체는 GC 경로가 아니다.

### 전형적인 패턴 — Outer가 UPROPERTY도 함께 들고 있을 때

가장 흔한 사용 방식은 Outer와 UPROPERTY 소유자를 같은 객체로 맞추는 것이다.

```
A (Outer이자 UPROPERTY 소유자)
  └── B (Inner)
```

이 패턴에서 수명 연계가 성립한다:

```
A가 GC될 때:
  → A의 UPROPERTY(B) 참조 소멸
  → B를 가리키는 참조가 없음
  → B도 다음 GC에 수거
```

Outer를 `this`로 지정하는 관례의 이유: 이름 계층이 자연스럽고,  
동시에 `this`의 UPROPERTY가 Inner를 잡고 있어 GC 생존도 보장되기 때문이다.

### Outer가 죽어도 Inner가 살아남는 경우 — Orphan 상태

다른 객체가 Inner를 UPROPERTY로 쥐고 있으면, Outer가 GC되어도 Inner는 살아남는다.  
GC는 순수 도달 가능성 기반이므로 C가 B를 참조하는 한 B는 수거되지 않는다.

```
A (Outer)  ──UPROPERTY──▶  B (Inner)
C          ──UPROPERTY──▶  B

A가 GC될 때:
  루트셋 → ... → C → B   ← C의 UPROPERTY로 도달 가능
  → B "살아있음" 표시 → 수거 안 됨

결과:
  B는 메모리에 살아있지만 B->GetOuter()가 이미 수거된 A를 가리킴
  → B->GetPathName() 경로 조립 실패
  → 직렬화, 에디터 기능 오동작 가능
  → "Orphan(고아)" 상태
```

이 상황은 대부분 **설계가 잘못된 것**이다.

```
잘못된 설계:
  A (짧은 수명) → B (Outer)
  C (긴 수명)   → B (UPROPERTY 참조)
  → A가 먼저 죽으면 B가 Orphan

올바른 설계:
  Outer는 B를 참조하는 모든 객체 중 가장 오래 사는 객체로 지정
  → World, GameInstance, GameState 같은 긴 수명 객체
```

---

## Outer 체인의 최상단 — UPackage와 루트셋

Outer를 계속 타고 올라가면 결국 Outer가 없는 UObject가 나온다.  
그게 **UPackage** 다.

```
GC 루트셋 (RF_RootSet)
  ├── UPackage (/Engine/Transient)   ← Outer = nullptr
  ├── UPackage (/Game/MyLevel)       ← Outer = nullptr
  └── UPackage (/Script/MyGame)      ← Outer = nullptr
        └── AMyActor
              └── UMeshComp
```

엔진의 최상위 패키지들은 `RF_RootSet` 플래그를 달고 GC 루트셋에 직접 등록된다.  
Outer 체인의 최상단이 루트셋에 속해 있기 때문에, 그 밑의 오브젝트들이 UPROPERTY 체인으로 연결되어 살아남는 구조다.

---

## 요약

| 역할 | 설명 |
|------|------|
| 이름·경로 | `GetPathName()` — Outer 타고 올라가며 경로 조립 |
| 패키지 소속 | 최상단 UPackage가 저장 파일을 결정 |
| 수명 연계 | Outer·UPROPERTY 소유자가 같을 때: Outer 죽으면 Inner도 죽음 |
| Orphan 위험 | Outer 죽어도 다른 UPROPERTY 참조가 있으면 Inner 생존 → 고아 상태 |
| GC 생존 보장 | Outer 관계가 아니라 **UPROPERTY 참조**가 담당 |

---

## 내 노트

