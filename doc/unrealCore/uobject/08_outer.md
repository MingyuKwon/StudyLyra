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

## 역할 3 — 수명 연계 (단방향)

Outer가 GC되면 Inner도 함께 수거된다.  
Outer가 Inner를 UPROPERTY로 들고 있으므로, Outer가 사라지면 그 참조도 사라지고 Inner도 "아무도 참조 안 함" 상태가 되기 때문이다.

```
Outer 수거
  → Outer의 UPROPERTY(Inner) 참조 소멸
  → Inner도 참조 없음 → 다음 GC에 수거
```

**반대는 자동이 아니다.**  
Outer가 살아있다고 Inner가 자동으로 살아남지 않는다.  
GC는 Outer → Inner를 자동 추적하지 않는다 — Inner를 살리려면 별도 UPROPERTY 참조가 있어야 한다.

```cpp
// Outer = this 지정, 하지만 UPROPERTY에 저장 안 함 → 수거됨
UMyObject* Obj = NewObject<UMyObject>(this);

// Outer = this 지정, UPROPERTY에 저장 → 살아남음
UPROPERTY()
UMyObject* MyData;
MyData = NewObject<UMyObject>(this);
```

`NewObject(this)` 관례의 이유: Outer를 `this`로 설정하면 이름 계층이 자연스럽고,  
동시에 `this`의 UPROPERTY가 Inner를 들고 있으므로 GC 생존도 보장된다.  
두 역할이 같은 객체를 가리키는 것이다.

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
| 수명 연계 | Outer 죽으면 Inner도 죽음 (단방향 — 반대는 자동이 아님) |
| GC 생존 보장 | Outer가 아니라 **UPROPERTY 참조**가 담당 |

---

## 내 노트

