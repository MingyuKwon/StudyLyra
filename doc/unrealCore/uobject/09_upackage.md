# UPackage — 직렬화와 에셋 시스템

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Package.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp`

---

## UPackage란

`.uasset` / `.umap` 파일 하나와 1:1 대응하는 UObject다.  
엔진의 모든 파일 I/O는 UPackage 단위로 일어난다.

```
Content/Meshes/SM_Rock.uasset    ←→  UPackage("/Game/Meshes/SM_Rock")
Content/Maps/MyLevel.umap        ←→  UPackage("/Game/Maps/MyLevel")
```

---

## 왜 필요한가 — 포인터는 저장할 수 없다

런타임 포인터 주소는 저장할 수 없다. 다음 실행 때 주소가 달라진다.  
**문자열 경로만이 실행 간에 유효하게 오브젝트를 식별**할 수 있다.

```
/Game/Meshes/SM_Rock.SM_Rock
      ↑                ↑
  UPackage 경로    패키지 안 오브젝트 이름
```

Outer 체인이 이 경로를 만들고, UPackage가 경로의 최상단이 된다.

### 저장·로드 흐름

```
저장:
  MeshComp->StaticMesh = SM_Rock (포인터)
  → GetPathName()으로 경로 변환
  → "/Game/Meshes/SM_Rock.SM_Rock" 문자열을 파일에 기록

로드:
  "/Game/Meshes/SM_Rock.SM_Rock" 읽음
  → UPackage("/Game/Meshes/SM_Rock") 로드 (SM_Rock.uasset 파일 열기)
  → 패키지 안에서 이름 "SM_Rock" 오브젝트 검색
  → 포인터 복원
```

---

## 패키지 ↔ 에셋 관계

사용자 입장에서 **에셋 하나 = 패키지 하나 = 파일 하나**다.  
패키지 안에 UObject가 여러 개일 수 있지만 나머지는 주인공 에셋을 지탱하는 **내부 부품**이지 독립적인 에셋이 아니다.

### 일반 에셋 — 주인공 1개 + 내부 부품

```
SM_Rock.uasset
  ├── UStaticMesh  "SM_Rock"     ← 주인공 (사용자가 만든 에셋)
  └── (소켓, LOD 데이터 등)      ← 내부 부품
```

주인공 이름이 패키지 이름과 같아서 경로가 `/Game/Meshes/SM_Rock.SM_Rock`처럼  
이름이 반복되어 보이는 것이다. 패키지와 오브젝트가 하나인 게 아니라 이름이 같을 뿐이다.

### Blueprint — 에디터용과 런타임용이 분리된다

```
BP_Hero.uasset
  ├── UBlueprint               "BP_Hero"    ← 에디터용 원본 (주인공)
  └── UBlueprintGeneratedClass "BP_Hero_C"  ← 런타임 클래스 (필수 부품)
```

에디터에서 BP를 편집하는 오브젝트(`UBlueprint`)와 실제 게임에서 인스턴스를 만드는 클래스(`UBlueprintGeneratedClass`)를 분리해서 관리하기 때문이다. 사용자가 만든 에셋은 `BP_Hero` 하나지만 내부 구현상 두 오브젝트가 필요하다.

### 레벨 (.umap) — 예외

레벨은 오브젝트들의 모음 자체가 하나의 패키지에 담기는 특수 케이스다.

```
MyLevel.umap
  ├── AMyActor  "Actor_1"    ← 독립적인 오브젝트들
  ├── AMyActor  "Actor_2"
  └── ALight    "Light_1"
```

이 때문에 레벨 안 특정 Actor를 참조하려면 패키지 경로만으로는 부족하고 세부 path가 필요하다.

```
/Game/Maps/MyLevel          ← 파일은 찾지만 안에 오브젝트가 수백 개
/Game/Maps/MyLevel.Actor_1  ← 정확히 이 Actor
```

---

## UPackage가 담당하는 작업

| 작업 | 설명 |
|------|------|
| 에셋 저장 | UPackage 직렬화 → .uasset 파일 |
| 에셋 로드 | .uasset 파일 → UPackage 역직렬화 |
| 크로스 에셋 참조 | 경로 문자열로 다른 패키지 오브젝트 참조 |
| 레벨 스트리밍 | UPackage 단위로 로드/언로드 |
| 쿠킹 | UPackage 단위로 패키징·최적화 |

---

## Transient 패키지 — 저장 불필요한 런타임 오브젝트

저장할 필요 없는 런타임 오브젝트는 `GetTransientPackage()`를 쓴다.  
디스크에 저장되지 않는 임시 패키지로, 엔진 시작 시 생성되어 루트셋에 등록된다.

```cpp
// 저장 불필요 — Transient 패키지 소속
UMyRuntimeData* Data = NewObject<UMyRuntimeData>(GetTransientPackage());

// 저장 필요 — 실제 패키지 소속
UMyDataAsset* Asset = NewObject<UMyDataAsset>(SomeRealPackage);
```

---

## 내 노트

