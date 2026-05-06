# UObject 개념

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Object.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/ObjectMacros.h`

---

## UObject란

언리얼 엔진에서 **거의 모든 클래스의 최상위 조상**이다.  
UObject를 상속하면 엔진이 다음 기능을 자동으로 제공한다.

| 기능 | 설명 |
|------|------|
| **가비지 컬렉션 (GC)** | UPROPERTY로 선언된 참조를 추적해 자동 메모리 관리 |
| **Reflection** | 런타임에 클래스 정보(프로퍼티, 함수) 조회 가능 |
| **직렬화 (Serialization)** | 저장/로드, 패키지 시스템, 에디터 undo/redo |
| **CDO** | 클래스당 기본 인스턴스를 유지해 Blueprint 기본값의 토대가 됨 |
| **에디터 통합** | Details 패널 노출, Blueprint 상속 가능 |

C++ 표준 `new`로 만든 객체는 이 중 아무것도 없다.

---

## 클래스 계층

```
UObject
├── UActorComponent
│   ├── USceneComponent
│   │   └── UPrimitiveComponent      ← 렌더·콜리전 담당
│   │       ├── UMeshComponent
│   │       │   └── UStaticMeshComponent
│   │       └── UCapsuleComponent
│   └── UMovementComponent
├── AActor                           ← 월드에 존재하는 오브젝트
│   ├── APawn
│   │   └── ACharacter
│   └── AGameModeBase
├── UDataAsset
├── UGameInstance
└── ...
```

`AActor`와 `UActorComponent`는 모두 `UObject`를 상속한다.  
`AActor`가 컴포넌트를 소유(Outer)하고, 컴포넌트가 실제 기능을 제공하는 구조다.

---

## UCLASS() 매크로가 하는 일

```cpp
UCLASS()
class MYGAME_API UMyObject : public UObject
{
    GENERATED_BODY()
};
```

### 빌드 파이프라인

보통 C++는 `소스 → 컴파일러 → 오브젝트 파일` 순서다.  
언리얼은 **그 앞에 UHT(Unreal Header Tool)가 먼저 끼어든다.**

```
*.h 파일
  → UHT 파싱          ← UCLASS, UPROPERTY, UFUNCTION 등 마커 읽음
  → *.generated.h 생성
  → C++ 컴파일러 실행  ← generated.h 포함한 채로 컴파일
  → 오브젝트 파일
```

`UCLASS()`는 C++ 컴파일러 입장에서는 **거의 아무것도 아니다.**  
`#define UCLASS(...)` 로 정의된 빈 매크로에 가깝다.  
진짜 역할은 UHT에게 "이 클래스를 분석해서 generated 코드 만들어줘"라고 알려주는 **마커**다.

### generated.h 안에 생기는 것

UHT가 `AMyActor.h`를 보고 `AMyActor.generated.h`를 만든다.

```cpp
// AMyActor.generated.h — UHT가 자동 생성, 직접 수정하면 안 됨

// StaticClass() 구현
static UClass* StaticClass();

// CDO 생성용 기본 생성자 래퍼
static void __DefaultConstructor(const FObjectInitializer& X)
{
    new ((EInternal*)X.GetObj()) AMyActor(X);
}

// 직렬화 override
virtual void Serialize(FArchive& Ar) override;

// Reflection 테이블 등록
DECLARE_CLASS(AMyActor, AActor, ...)
```

`GENERATED_BODY()`는 이 generated.h의 코드 블록을 **클래스 본문 안에 붙여넣는 자리**다.  
`GENERATED_BODY()`를 빼면 `StaticClass()`가 없으니 컴파일 자체가 안 된다.

### UClass 오브젝트 — 클래스를 표현하는 UObject

`StaticClass()`가 반환하는 `UClass*`는 **클래스 자체를 표현하는 UObject**다.  
클래스의 메타데이터 컨테이너라고 보면 된다.

```
UClass (AMyActor에 대한 UClass 인스턴스)
  ├── Name: "AMyActor"
  ├── SuperClass: UClass(AActor)
  ├── Properties: [ Speed(float), Health(float), ... ]   ← UPROPERTY 목록
  ├── Functions: [ Fire(), TakeDamage(), ... ]           ← UFUNCTION 목록
  ├── CDO: AMyActor* (기본 인스턴스 포인터)
  └── ClassFlags: Blueprintable, ...
```

이 UClass가 있기 때문에 런타임 Reflection이 가능하다.

```cpp
// 런타임에 클래스 이름으로 오브젝트 생성
UClass* Class = FindObject<UClass>(ANY_PACKAGE, TEXT("AMyActor"));
AActor* Actor = GetWorld()->SpawnActor<AActor>(Class, Transform);

// 런타임에 프로퍼티 목록 순회
for (TFieldIterator<FProperty> It(AMyActor::StaticClass()); It; ++It)
{
    UE_LOG(LogTemp, Log, TEXT("Property: %s"), *It->GetName());
}
```

### 프로그램 시작 시 등록 흐름

generated.h는 static initializer도 생성한다. 프로그램이 시작되면 자동으로 실행된다.

```
프로그램 시작
  → static initializer 실행
  → Z_Construct_UClass_AMyActor() 호출   (UHT가 생성한 함수)
  → UClass 객체 생성 → GUObjectArray에 등록
  → __DefaultConstructor로 CDO 생성 (AMyActor 생성자 호출)
  → UClass.CDO 포인터 저장
```

### 핵심 요약

| 항목 | 역할 |
|------|------|
| `UCLASS()` | UHT 마커. C++ 컴파일러엔 빈 매크로 |
| `generated.h` | UHT가 만드는 파일. StaticClass/CDO생성자/직렬화 코드 포함 |
| `GENERATED_BODY()` | generated.h의 코드를 클래스 본문에 삽입하는 자리 |
| `UClass` | 클래스 메타데이터를 담는 UObject. Reflection/CDO/직렬화의 토대 |
| `StaticClass()` | 이 클래스의 UClass*를 반환하는 함수 (generated 코드가 구현) |

---

## 자주 쓰는 UCLASS 지정자

```cpp
UCLASS(Blueprintable)           // Blueprint에서 이 클래스를 상속 가능
UCLASS(BlueprintType)           // Blueprint 변수 타입으로 사용 가능
UCLASS(Abstract)                // 직접 인스턴스화 불가 (SpawnActor 불가)
UCLASS(NotBlueprintable)        // Blueprint 상속 금지
UCLASS(Transient)               // 저장되지 않음 (GameInstance 등에 사용)
UCLASS(MinimalAPI)              // DLL export 최소화
```

---

## 내 노트

