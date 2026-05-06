# UPackage — 직렬화와 에셋 시스템

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Package.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp`

---

## UPackage란

UObject 시스템의 파일 단위 컨테이너다.  
종류에 따라 실제 파일이 있는 것과 없는 것으로 나뉜다.

### 패키지 종류

| 종류 | 경로 접두사 | 실제 파일 | 내용 |
|------|-------------|-----------|------|
| 콘텐츠 패키지 | `/Game/`, `/Engine/` | `.uasset` / `.umap` | 에셋·레벨 인스턴스 |
| 스크립트 패키지 | `/Script/` | 없음 (바이너리에서 로드) | C++ 모듈의 UClass 객체들 |
| Transient 패키지 | `/Engine/Transient` | 없음 (메모리에만 존재) | 런타임 임시 오브젝트 |

### 콘텐츠 패키지 — 에셋과 1:1

```
Content/Meshes/SM_Rock.uasset    ←→  UPackage("/Game/Meshes/SM_Rock")
Content/Maps/MyLevel.umap        ←→  UPackage("/Game/Maps/MyLevel")
```

### 스크립트 패키지 — C++ 모듈당 1개

C++ 모듈 하나당 Script 패키지 하나가 생긴다.  
그 모듈에 있는 **모든 UClass 객체**를 담는 컨테이너다.

```
/Script/Engine      → UStaticMesh, AActor, UTexture2D 등 엔진 UClass 전부
/Script/MyGame      → AMyActor, UMyComponent 등 내 게임 C++ UClass 전부
/Script/CoreUObject → UObject, UPackage 등 코어 UClass 전부
```

`.uasset` 파일이 없다. 엔진이 모듈(DLL / 실행 파일)을 로드할 때 메모리에 생성된다.

콘텐츠 패키지와 Script 패키지의 내용물 차이:

```
/Script/Engine.StaticMesh          ← UStaticMesh 클래스 자체 (UClass 객체)
/Game/Meshes/SM_Rock.SM_Rock       ← SM_Rock 인스턴스 (UStaticMesh의 인스턴스)
```

"에셋 1:1" 법칙은 `/Game/` 콘텐츠 패키지에만 해당한다.  
`/Script/` 패키지는 모듈 하나당 하나이며 해당 모듈의 UClass 전부를 담는다.

---

## 왜 필요한가 — 포인터는 저장할 수 없다

런타임 포인터 주소는 저장할 수 없다. 다음 실행 때 주소가 달라진다.  
**문자열 경로만이 실행 간에 유효하게 오브젝트를 식별**할 수 있다.

```
/Game/Meshes/SM_Rock.SM_Rock
      ↑                ↑
  UPackage 경로    패키지 안 오브젝트 이름
```

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

주인공 이름이 패키지 이름과 같아서 `/Game/Meshes/SM_Rock.SM_Rock`처럼  
이름이 반복되어 보인다. 패키지와 오브젝트가 하나인 게 아니라 이름이 같을 뿐이다.

### Blueprint — 에디터용과 런타임용이 분리된다

```
BP_Hero.uasset
  ├── UBlueprint               "BP_Hero"    ← 에디터용 원본 (주인공)
  └── UBlueprintGeneratedClass "BP_Hero_C"  ← 런타임 클래스 (필수 부품)
```

에디터에서 편집하는 오브젝트와 실제 인스턴스를 찍어내는 클래스를 분리해서 관리하기 때문이다.

### 레벨 (.umap) — 예외

레벨은 수많은 독립 오브젝트가 하나의 패키지에 담기는 특수 케이스다.

```
MyLevel.umap
  ├── AMyActor  "Actor_1"    ← 독립적인 오브젝트들
  ├── AMyActor  "Actor_2"
  └── ALight    "Light_1"
```

레벨 안 특정 Actor를 참조하려면 패키지 경로만으로는 부족하고 세부 path가 필요하다.

```
/Game/Maps/MyLevel          ← 파일은 찾지만 오브젝트가 수백 개
/Game/Maps/MyLevel.Actor_1  ← 정확히 이 Actor
```

---

## Transient — 저장하지 않음

Transient는 **"직렬화(저장) 제외"** 를 의미한다.  
언리얼 곳곳에서 같은 의미로 등장한다.

### UPROPERTY(Transient)

```cpp
UPROPERTY()
float MaxSpeed = 600.f;     // 저장됨 — 에디터에서 바꾼 값이 .uasset에 기록

UPROPERTY(Transient)
float CurrentSpeed = 0.f;  // 저장 안 됨 — 런타임에 계산되는 값
```

`CurrentSpeed`는 매 실행마다 0에서 시작해 게임 로직이 채운다.  
저장할 필요가 없고 저장하면 오히려 이상한 값이 로드될 수 있다.

### UCLASS(Transient)

```cpp
UCLASS(Transient)
class UGameInstance : public UObject { ... }
```

이 클래스의 인스턴스는 절대 파일에 저장되지 않는다.  
`UGameInstance`, `UWorld` 같이 매 실행마다 새로 만들어지는 것들이 해당한다.

### GetTransientPackage() — 파일 없는 패키지

`GetTransientPackage()`는 디스크에 대응하는 파일이 없는 전역 패키지다.  
런타임에만 존재하고 엔진이 꺼지면 사라진다.

NewObject를 만들 때 Outer는 반드시 있어야 한다.  
"아무 에셋에도 속하지 않는 임시 오브젝트"가 필요할 때 Transient 패키지가 Outer 역할을 대신한다.

```cpp
// 저장 불필요 — Transient 패키지 소속
UMyRuntimeData* Data = NewObject<UMyRuntimeData>(GetTransientPackage());

// 저장 필요 — 실제 패키지 소속
UMyDataAsset* Asset = NewObject<UMyDataAsset>(SomeRealPackage);
```

```
실제 패키지:   UPackage("/Game/Meshes/SM_Rock")  →  SM_Rock.uasset 파일 존재
Transient 패키지: UPackage("/Engine/Transient")  →  대응 파일 없음
                                                     엔진 시작 시 메모리에만 생성
                                                     RF_RootSet으로 루트셋 등록
```

### Transient 정리

| 위치 | 의미 |
|------|------|
| `UPROPERTY(Transient)` | 이 프로퍼티는 저장 안 함 |
| `UCLASS(Transient)` | 이 클래스 인스턴스는 저장 안 함 |
| `GetTransientPackage()` | 저장 안 하는 오브젝트들의 Outer 역할 패키지 |
| `RF_Transient` 플래그 | 이 UObject 인스턴스는 저장 안 함 |

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

## 내 노트

