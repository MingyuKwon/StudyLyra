# Outer

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectBase.h`  
> `Engine/Source/Runtime/CoreUObject/Private/GarbageCollection.cpp`

---

## Outer의 핵심 — 오브젝트의 영구적 정체성(Path)을 만드는 도구

모든 UObject는 생성 시 **Outer**를 지정한다.

```cpp
UMyObject* Obj = NewObject<UMyObject>(this);   // Outer = this
```

Outer의 핵심 목적은 **오브젝트의 path를 구성**하는 것이다.

```
런타임 정체성 → 메모리 주소   (프로그램 꺼지면 사라짐)
영구적 정체성 → path 문자열  (저장·로드·크로스 참조에 사용)
```

`GetPathName()`이 Outer를 타고 올라가며 이 path를 조립한다.

```
/Game/MyLevel.MyActor.MeshComp

UPackage (/Game/MyLevel)       ← Outer = nullptr  (최상단)
  └── AMyActor                 ← Outer = UPackage
        └── UStaticMeshComp   ← Outer = AMyActor
```

path가 있으면:
- 에디터 Outliner·로그에서 식별 가능
- 다른 에셋에서 이 오브젝트를 문자열로 참조 가능
- 파일에 저장하고 다음 실행 때 복원 가능

같은 UPackage 안에 같은 클래스 오브젝트가 여럿 있어도 Outer가 달라 path가 구별된다.

```
/Game/MyLevel.Actor_1.MeshComp
/Game/MyLevel.Actor_2.MeshComp   ← Outer(Actor)가 달라서 다른 오브젝트로 식별
```

---

## 패키지 소속

path 최상단은 반드시 **UPackage**다.  
UPackage는 `.uasset` 파일 하나와 1:1 대응한다 — 이 오브젝트가 어느 파일에 저장될지를 결정한다.

```cpp
NewObject<UMyObject>(this);                   // → this의 패키지에 소속, 저장 가능
NewObject<UMyObject>(GetTransientPackage());  // → Transient 패키지, 저장 안 됨
```

Outer를 잘못 지정하면 예상치 못한 패키지에 묶이거나 직렬화가 꼬인다.  
UPackage 상세 → [09_upackage.md](09_upackage.md)

---

## GC와의 관계 — Outer는 GC 경로가 아니다

Outer 관계와 UPROPERTY는 **별개**다.  
GC는 오직 UPROPERTY(Token Stream)만 추적한다. Outer를 지정해도 UPROPERTY가 자동으로 생기지 않는다.

```cpp
// Outer = this, UPROPERTY 없음 → GC가 수거
UMyObject* Obj = NewObject<UMyObject>(this);

// Outer = this, UPROPERTY에 저장 → 살아남음
UPROPERTY()
UMyObject* MyData;
MyData = NewObject<UMyObject>(this);
```

`NewObject(this)` 관례의 이유: Outer를 `this`로 설정하면 path가 자연스럽고,  
동시에 `this`의 UPROPERTY가 Inner를 잡아 GC 생존도 보장된다.  
두 역할이 우연히 같은 객체를 가리킬 뿐이다.

---

## 수명 연계 — UPROPERTY 관계의 부수 효과

Outer 자체가 수명을 보장하지는 않는다.  
그러나 Outer와 UPROPERTY 소유자가 같은 전형적인 패턴에서는 Outer가 죽으면 Inner도 죽는다.

```
A (Outer이자 UPROPERTY 소유자)
  └── B (Inner)

A가 GC될 때:
  → A의 UPROPERTY(B) 참조 소멸
  → B를 가리키는 참조 없음 → B도 수거
```

이건 Outer 때문이 아니라 **UPROPERTY 참조가 사라졌기 때문**이다.

### Orphan 상태 — Outer는 죽었는데 Inner가 살아남는 경우

다른 객체가 Inner를 UPROPERTY로 쥐고 있으면 Outer가 GC되어도 Inner는 살아남는다.

```
A (Outer)  ──UPROPERTY──▶  B (Inner)
C          ──UPROPERTY──▶  B

A가 GC될 때:
  C의 UPROPERTY로 B에 도달 가능 → B "살아있음" → 수거 안 됨

결과:
  B->GetOuter() = 이미 수거된 A   ← path 조립 실패
  B->GetPathName() 오동작
  직렬화·에디터 기능 깨짐
  → "Orphan(고아)" 상태
```

이 상황은 대부분 **설계가 잘못된 것**이다.

```
잘못된 설계:
  A (짧은 수명) = B의 Outer
  C (긴 수명)   = B의 UPROPERTY 참조자
  → A가 먼저 죽으면 B가 Orphan

올바른 설계:
  Outer는 B를 참조하는 모든 객체 중 가장 오래 사는 객체로 지정
  (World, GameInstance, GameState 등)
```

---

## Outer 체인의 최상단 — UPackage와 루트셋

Outer를 계속 타고 올라가면 Outer가 없는 오브젝트에 도달한다 — **UPackage**다.  
엔진의 최상위 패키지들은 `RF_RootSet` 플래그로 GC 루트셋에 직접 등록된다.

```
GC 루트셋 (RF_RootSet)
  ├── UPackage (/Engine/Transient)   ← Outer = nullptr
  ├── UPackage (/Game/MyLevel)       ← Outer = nullptr
  └── UPackage (/Script/MyGame)      ← Outer = nullptr
        └── AMyActor
              └── UMeshComp
```

---

## 요약

| 항목 | 설명 |
|------|------|
| **Outer의 핵심** | path를 구성하는 도구 — 오브젝트의 영구적 정체성 |
| path가 하는 일 | 식별·저장·로드·크로스 참조 |
| 패키지 소속 | path 최상단 UPackage = 저장 파일 결정 |
| GC 생존 | Outer가 아니라 **UPROPERTY** 가 담당 |
| 수명 연계 | UPROPERTY 관계의 부수 효과 (Outer 자체가 보장 안 함) |
| Orphan | Outer 사망 후 Inner가 다른 참조로 생존 → path 깨짐 |

---

## 내 노트

