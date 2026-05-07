# UObject 시스템

언리얼 엔진의 모든 클래스 기반인 `UObject` 분석.  
GC, Reflection, Serialization, CDO, Blueprint 연동까지 포함한다.

| 파일 | 내용 |
|------|------|
| [01_overview.md](01_overview.md) | UObject란, 클래스 계층, UCLASS 매크로가 하는 일 |
| [02_creation.md](02_creation.md) | UObject / AActor / UActorComponent 각각의 생성 방법 |
| [03_cdo.md](03_cdo.md) | CDO(Class Default Object) 개념과 역할 |
| [04_default_subobject.md](04_default_subobject.md) | CreateDefaultSubobject — 생성 타이밍과 제약 |
| [05_garbage_collection.md](05_garbage_collection.md) | GC 동작 원리, UPROPERTY 참조 추적, AddToRoot |
| [06_isvalid.md](06_isvalid.md) | MarkPendingKill / IsValid / IsValidLowLevel 차이 |
| [07_blueprint_asset.md](07_blueprint_asset.md) | C++ 클래스 → Blueprint Asset 생성 과정 |
| [08_outer.md](08_outer.md) | Outer — 이름·패키지 소속·수명 연계, UPackage 루트셋 구조 |
| [upackage/](upackage/README.md) | UPackage — 종류, 로드 시점, 파이프라인, Transient |
