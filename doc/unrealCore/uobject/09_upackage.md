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

런타임에 BP_MyActor가 SM_Rock을 참조하고 있다고 하자.

```cpp
MeshComp->SetStaticMesh(SM_Rock);  // SM_Rock = 메모리 주소 0x7ff3a2c0
```

이 포인터 주소는 저장할 수 없다. 다음 실행 때 주소가 달라진다.  
**문자열 경로만이 실행 간에 유효하게 오브젝트를 식별**할 수 있다.

```
/Game/Meshes/SM_Rock.SM_Rock
      ↑                ↑
  UPackage 경로    오브젝트 이름
```

Outer 체인이 이 경로를 만들고, UPackage가 경로의 최상단 단위가 된다.

---

## 저장·로드 흐름

### 저장

```
BP_MyActor 저장:
  MeshComp->StaticMesh = SM_Rock (포인터)
  → 엔진이 GetPathName()으로 경로 변환
  → "/Game/Meshes/SM_Rock.SM_Rock" 문자열을 파일에 기록
```

### 로드

```
BP_MyActor 로드:
  "/Game/Meshes/SM_Rock.SM_Rock" 읽음
  → UPackage("/Game/Meshes/SM_Rock") 로드 (= SM_Rock.uasset 파일 열기)
  → 패키지 안에서 이름이 "SM_Rock"인 오브젝트 검색
  → 포인터 복원
```

이 체인이 동작하려면 SM_Rock의 Outer가 정확한 UPackage를 가리키고 있어야 한다.

---

## UPackage가 담당하는 작업

| 작업 | 설명 |
|------|------|
| 에셋 저장 | UPackage 직렬화 → .uasset 파일 |
| 에셋 로드 | .uasset 파일 → UPackage 역직렬화 |
| 크로스 에셋 참조 | 경로 문자열로 다른 패키지 오브젝트 참조 |
| 레벨 스트리밍 | UPackage 단위로 로드/언로드 |
| 쿠킹 | UPackage 단위로 패키징·최적화 |
| 핫 리로드 | UPackage 단위로 재로드 |

---

## Transient 패키지 — 저장 불필요한 런타임 오브젝트

저장할 필요 없는 런타임 오브젝트는 `GetTransientPackage()`를 쓴다.  
이 패키지는 디스크에 저장되지 않는 임시 패키지로, 엔진 시작 시 생성되어 루트셋에 등록된다.

```cpp
// 저장 불필요한 런타임 데이터 — Transient 패키지 소속
UMyRuntimeData* Data = NewObject<UMyRuntimeData>(GetTransientPackage());

// 저장 필요한 에셋 — 실제 패키지 소속
UMyDataAsset* Asset = NewObject<UMyDataAsset>(SomeRealPackage);
```

---

## 한 줄 요약

**UPackage = 오브젝트의 주민등록 파일.**  
런타임 포인터는 프로그램이 꺼지면 사라지지만,  
UPackage 기반 경로 문자열은 영구적이라 저장·로드·크로스 참조가 가능하다.

---

## 내 노트

