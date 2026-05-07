# UPackage — 종류

## 세 가지 패키지

| 종류 | 경로 | 실제 파일 | 내용 |
|------|------|-----------|------|
| 콘텐츠 패키지 | `/Game/`, `/Engine/` | `.uasset` / `.umap` | 에셋·레벨 인스턴스 |
| 스크립트 패키지 | `/Script/` | 없음 | C++ 모듈의 UClass 전체 |
| Transient 패키지 | `/Engine/Transient` | 없음 | 런타임 임시 오브젝트 |

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

## 내 노트
