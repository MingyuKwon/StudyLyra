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

`UCLASS()`는 **헤더 파일을 분석해 generated 코드를 생성하라는 지시**다.  
UHT(Unreal Header Tool)가 빌드 전에 헤더를 파싱해 `MyObject.generated.h`를 만든다.

generated 코드가 실제로 하는 일:

| 항목 | 역할 |
|------|------|
| `UClass` 등록 | 엔진 오브젝트 시스템에 이 클래스의 메타데이터 등록 |
| CDO 생성 트리거 | 프로그램 시작 시 CDO를 자동으로 만들도록 함 |
| `StaticClass()` 구현 | `UMyObject::StaticClass()` 함수 자동 생성 |
| UPROPERTY/UFUNCTION 등록 | Reflection 테이블에 프로퍼티·함수 정보 추가 |

`GENERATED_BODY()`는 generated 헤더에서 생성된 코드 블록을 삽입하는 자리다.

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

