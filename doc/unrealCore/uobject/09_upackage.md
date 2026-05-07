# UPackage — 직렬화와 에셋 시스템

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Package.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PackageFileSummary.cpp`

---

## UPackage란

UObject 시스템의 파일·모듈 단위 컨테이너다.  
종류에 따라 실제 파일이 있는 것과 없는 것으로 나뉜다.

| 종류 | 경로 | 실제 파일 | 내용 | 로드 시점 |
|------|------|-----------|------|-----------|
| 콘텐츠 패키지 | `/Game/`, `/Engine/` | `.uasset` / `.umap` | 에셋·레벨 인스턴스 | 참조 방식에 따라 다름 |
| 스크립트 패키지 | `/Script/` | 없음 | C++ 모듈의 UClass 전체 | 엔진 시작 시 모듈 DLL 로드 |
| Transient 패키지 | `/Engine/Transient` | 없음 | 런타임 임시 오브젝트 | 엔진 시작 시 (항상 존재) |

---

## 왜 필요한가 — 포인터는 저장할 수 없다

런타임 포인터 주소는 다음 실행 때 달라진다.  
**문자열 경로만이 실행 간에 유효하게 오브젝트를 식별**할 수 있다.

```
/Game/Meshes/SM_Rock . SM_Rock
      ↑                  ↑
  UPackage 경로     패키지 안 오브젝트 이름
```

```
저장:
  MeshComp->StaticMesh = SM_Rock (포인터)
  → GetPathName()으로 경로 변환
  → "/Game/Meshes/SM_Rock.SM_Rock" 문자열을 파일에 기록

로드:
  "/Game/Meshes/SM_Rock.SM_Rock" 읽음
  → UPackage("/Game/Meshes/SM_Rock") 로드 (SM_Rock.uasset 열기)
  → 패키지 안에서 이름 "SM_Rock" 오브젝트 검색
  → 포인터 복원
```

---

## 콘텐츠 패키지 — 에셋과 1:1

사용자 입장에서 **에셋 하나 = 패키지 하나 = 파일 하나**다.  
패키지 안 UObject가 여러 개여도 나머지는 주인공을 지탱하는 내부 부품이다.

```
SM_Rock.uasset
  ├── UStaticMesh  "SM_Rock"     ← 주인공
  └── (소켓, LOD 데이터 등)      ← 내부 부품
```

주인공 이름이 패키지 이름과 같아서 `/Game/Meshes/SM_Rock.SM_Rock`처럼  
이름이 반복되어 보이는 것이다. 패키지와 오브젝트가 하나인 게 아니라 이름이 같을 뿐이다.

**Blueprint** — 에디터용과 런타임용이 분리되어 두 오브젝트가 존재한다.

```
BP_Hero.uasset
  ├── UBlueprint               "BP_Hero"    ← 에디터용 원본 (주인공)
  └── UBlueprintGeneratedClass "BP_Hero_C"  ← 런타임 클래스 (필수 부품)
```

**레벨 (.umap)** — 수많은 독립 오브젝트가 하나의 패키지에 담기는 예외 케이스다.

```
MyLevel.umap
  ├── AMyActor  "Actor_1"
  ├── AMyActor  "Actor_2"    ← 독립적인 오브젝트들
  └── ALight    "Light_1"
```

---

## 스크립트 패키지 — C++ 모듈당 1개

C++ 모듈 하나당 Script 패키지 하나. `.uasset` 파일이 없고 모듈 DLL 로드 시 메모리에 생성된다.  
해당 모듈의 **모든 UClass 객체**를 담는다 — 에셋 인스턴스가 아니라 클래스 메타데이터다.

```
/Script/Engine      → UStaticMesh, AActor 등 엔진 UClass 전부
/Script/MyGame      → AMyActor, UMyComponent 등 내 게임 UClass 전부
/Script/CoreUObject → UObject, UPackage 등 코어 UClass 전부
```

```
/Script/Engine.StaticMesh        ← UStaticMesh 클래스 자체 (UClass 객체)
/Game/Meshes/SM_Rock.SM_Rock     ← SM_Rock 인스턴스 (UStaticMesh의 인스턴스)
```

---

## 콘텐츠 패키지 로드 시점 — 참조 방식이 결정한다

### Hard 참조 — 참조하는 패키지 로드 시 함께

```cpp
UPROPERTY()
UStaticMesh* MyMesh;   // Hard 참조
```

이 Actor가 담긴 레벨이 로드될 때 `MyMesh` 패키지도 **같이 로드**된다.

```
MyLevel 로드
  → BP_MyActor 로드
      → SM_Rock 로드
          → T_Rock_Diffuse 로드    ← 체인 전체가 한 번에 딸려 올라옴
```

참조 체인이 깊을수록 초기 로드 시간이 길어진다.

### Soft 참조 — 명시적 요청 시에만

```cpp
UPROPERTY()
TSoftObjectPtr<UStaticMesh> MyMesh;   // Soft 참조
```

레벨이 로드돼도 `MyMesh` 패키지는 로드되지 않는다. 직접 요청해야 한다.

```cpp
// 동기 로드 (완료까지 게임 스레드 블로킹)
UStaticMesh* Mesh = MyMesh.LoadSynchronous();

// 비동기 로드 (완료 시 콜백)
StreamableManager.RequestAsyncLoad(
    MyMesh.ToSoftObjectPath(),
    FStreamableDelegate::CreateUObject(this, &AMyActor::OnMeshLoaded)
);
```

### 레벨 스트리밍 — 조건 충족 시

```
플레이어가 특정 구역 진입
  → ULevelStreaming 조건 감지
  → 해당 맵 패키지 비동기 로드 → 로드 완료 후 레벨 활성화
```

---

## 패키지 로드 파이프라인 — 내부 흐름

### FLinkerLoad

`FLinkerLoad` — 패키지 파일을 디스크에서 읽는 클래스다.  
패키지 로드 요청이 들어오면 FLinkerLoad가 파일을 열고 오브젝트를 복원한다.

패키지 파일의 내부 구조:

```
파일 헤더      (버전, 플래그 등 요약 정보)
Name 테이블    (파일 안에서 쓰이는 FName 문자열 목록)
Import 테이블  (이 패키지가 참조하는 다른 패키지의 오브젝트 목록)
Export 테이블  (이 패키지에 실제로 들어있는 오브젝트 목록)
Export 데이터  (각 오브젝트의 직렬화된 프로퍼티 값 — CDO 대비 델타)
```

Import는 "다른 파일에서 빌려 쓰는 것", Export는 "이 파일이 소유한 것"이다.  
포인터 복원 시 Import 테이블의 경로 문자열로 다른 패키지를 찾아 포인터를 연결한다.

### 오브젝트 복원 흐름

```
패키지 로드 요청
  → FLinkerLoad 파일 열기
  → Export 테이블 순회 — 각 오브젝트마다:
        StaticConstructObject_Internal()   ← 생성 + CDO 복사
        RF_NeedLoad 플래그 부착            ← "아직 읽을 데이터 있음"

  → Export 데이터 순회 — 각 오브젝트마다:
        Serialize()                        ← 델타 데이터 덮어씀
        RF_NeedLoad 제거

  → PostLoad() 호출                        ← 모든 Serialize 완료 후
```

두 순회가 분리된 이유: A가 B를 참조할 때 A를 Serialize하기 전에 B가 먼저 존재해야 하므로,  
전체 오브젝트를 먼저 생성(1차 순회)하고 나서 데이터를 채운다(2차 순회).

### PostLoad

패키지에서 로드된 **모든 Export 오브젝트**에 호출된다. 호출 순서는 의존성 순서다 — A가 B를 참조하면 B의 PostLoad가 먼저 불린다.

| | PostInitProperties | PostLoad |
|---|---|---|
| 호출 시점 | 생성자 직후 (항상) | 패키지 Serialize 완료 후 |
| 대상 | 모든 UObject | 패키지에서 로드된 오브젝트만 |
| 용도 | 생성 직후 파생값 초기화 | 캐시 재구성, 버전 마이그레이션, 포인터 픽스업 |

런타임 `NewObject` / `SpawnActor`로 만든 오브젝트는 PostLoad가 호출되지 않는다 — 디스크에서 온 게 아니기 때문이다.

```
패키지에서 로드된 오브젝트:
  생성자 → PostInitProperties → Serialize(델타 적용) → PostLoad

런타임 NewObject / SpawnActor:
  생성자 → PostInitProperties
  (PostLoad 없음)
```

---

## Transient — 직렬화 제외

Transient는 **"직렬화(저장) 대상에서 제외"** 를 의미한다.  
저장 행위 자체를 막는 게 아니라 직렬화 과정에서 건너뛰는 것이다.

| 위치 | 의미 |
|------|------|
| `UPROPERTY(Transient)` | 이 프로퍼티는 저장 안 함, GC 추적은 유지 |
| `UCLASS(Transient)` | 이 클래스 인스턴스는 저장 안 함 (`UGameInstance`, `UWorld` 등) |
| `GetTransientPackage()` | 저장 안 하는 오브젝트의 Outer 역할 패키지 |
| `RF_Transient` 플래그 | 이 UObject 인스턴스만 저장 안 함 |

```cpp
UPROPERTY()
float MaxSpeed = 600.f;      // 저장됨

UPROPERTY(Transient)
float CurrentSpeed = 0.f;   // 저장 안 됨 — 런타임에 채워지는 캐시값

UPROPERTY(Transient, Replicated)
float CurrentSpeed = 0.f;   // 저장 안 됨 + 네트워크 복제는 됨
                             // Transient는 디스크 직렬화만 제외, 복제와 무관
```

`GetTransientPackage()`는 어느 에셋에도 속하지 않는 임시 오브젝트의 Outer 역할을 한다.

```cpp
UMyRuntimeData* Data = NewObject<UMyRuntimeData>(GetTransientPackage());
// 엔진 시작 시 생성, RF_RootSet 등록, 디스크에 저장 안 됨
```

---

## 내 노트

