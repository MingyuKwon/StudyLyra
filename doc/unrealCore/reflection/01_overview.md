# 리플렉션 시스템 — 전체 그림

> 소스:  
> `Engine/Source/Programs/UnrealHeaderTool/` (UHT)  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Field.h`

언리얼 리플렉션은 C++ 컴파일러가 최적화로 버리는 타입 정보를
별도로 보존해 런타임에 클래스 구조를 조회·조작할 수 있게 하는 메커니즘이다.

---

## 왜 필요한가

C++ 표준 RTTI는 범위가 좁다.

| 표준 C++ RTTI | 언리얼 리플렉션 |
|--------------|--------------|
| `typeid(T).name()` — 타입 이름만 | 클래스 이름, 부모, 프로퍼티·함수 목록 전부 |
| `dynamic_cast<T*>` — 업/다운캐스트 가능 여부만 | 프로퍼티 이름·오프셋·타입·메타데이터 접근 |
| 멤버 변수 목록 조회 불가 | `TFieldIterator<FProperty>`로 모든 UPROPERTY 순회 |
| 함수 이름 조회 불가 | `FindFunctionByName()`으로 UFunction 검색·호출 |
| Blueprint 클래스(런타임 생성) 인식 불가 | `UClass` 기반이면 동적 생성 클래스도 동일하게 처리 |

GC, 직렬화, Blueprint VM, RPC 자동 생성, 에디터 Details 패널은
모두 이 리플렉션 데이터 위에서 동작한다.

---

## 두 단계 파이프라인

```
══════════════════════════════════════════════
 빌드타임
══════════════════════════════════════════════

 소스 헤더 (*.h)
   ├── UCLASS(...)  클래스 마킹
   ├── UPROPERTY(...) 멤버 변수 마킹
   └── UFUNCTION(...) 함수 마킹
           │
           ▼
     UHT (Unreal Header Tool) 실행
     — C++ 파서 아님, 정적 텍스트 파싱
           │
     ┌─────┴──────┐
     ▼             ▼
 *.generated.h   *.gen.cpp
 클래스 본문에    런타임 타입 객체를
 삽입될 선언코드  만드는 팩토리 코드
           │
           ▼
     C++ 컴파일러 (generated 파일 포함)
           │
           ▼
       바이너리

══════════════════════════════════════════════
 런타임
══════════════════════════════════════════════

 프로그램 시작
   → gen.cpp의 static 변수 초기화
   → FRegisterCompiledInInfo 생성자 실행
   → 팩토리 함수 포인터를 전역 목록에 등록
           │
           ▼ ProcessNewlyLoadedUObjects()
   → Z_Construct_UClass_XXX() 실행
   → UClass / UScriptStruct / UFunction 생성
   → FProperty 객체들 생성 (각 UPROPERTY마다)
   → GUObjectArray 등록 완료
   → CDO 생성 (__DefaultConstructor 호출)
```

---

## 빌드타임: 매크로의 역할

```cpp
UCLASS()
class MYGAME_API AMyActor : public AActor
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float Health;

    UFUNCTION(BlueprintCallable, Server, Reliable)
    void Fire();
};
```

`UCLASS()`, `UPROPERTY()`, `UFUNCTION()`은 C++ 컴파일러에게는
거의 빈 매크로다.  
UHT에게 "이 클래스/프로퍼티/함수를 분석해 코드를 생성하라"고 알려주는 **마커**다.

UHT가 이 마커를 읽어 두 파일을 생성한다:

| 파일 | 역할 |
|------|------|
| `AMyActor.generated.h` | `GENERATED_BODY()`가 클래스 본문에 삽입하는 코드 — `StaticClass()` 선언 등 |
| `AMyActor.gen.cpp` | 런타임에 `UClass` 객체를 구성하는 팩토리 + 자동 등록 코드 |

> `generated.h`와 `GENERATED_BODY()` 동작 원리(토큰 붙이기, 줄 번호)는
> [uobject/01_overview.md](../uobject/01_overview.md)에 상세히 다룬다.

---

## 런타임: 타입 시스템 객체

프로그램이 뜨면 `gen.cpp` 팩토리 코드가 실행되어
**클래스마다 하나의 `UClass` 인스턴스**가 메모리에 생긴다.

```
UClass (AMyActor의 메타데이터)
  ├── Name:        "AMyActor"
  ├── SuperStruct: UClass(AActor)           ← 부모 클래스
  ├── ChildProperties: FProperty 링크드 리스트  ← 모든 UPROPERTY
  │     └── FFloatProperty "Health"
  │           offset = 0x1A0
  │           flags  = CPF_Edit | CPF_BlueprintVisible
  ├── FuncMap: TMap<FName, UFunction*>      ← 모든 UFUNCTION
  │     └── UFunction "Fire"
  │           flags = FUNC_BlueprintCallable | FUNC_Net | FUNC_NetServer
  ├── CDO:         AMyActor*                ← 기본 인스턴스
  └── ClassFlags:  CLASS_Blueprintable ...
```

런타임 접근 API:

```cpp
// 정적 접근 (컴파일타임에 타입을 앎)
UClass* Class = AMyActor::StaticClass();

// 동적 접근 (실제 파생 타입 반환)
UClass* Class = SomeActor->GetClass();

// 프로퍼티 순회
for (TFieldIterator<FProperty> It(AMyActor::StaticClass()); It; ++It)
{
    FProperty* Prop = *It;
    UE_LOG(LogTemp, Log, TEXT("%s (%s)"), *Prop->GetName(), *Prop->GetCPPType());
}

// 함수 이름으로 호출
UFunction* Func = SomeActor->FindFunctionChecked(TEXT("Fire"));
SomeActor->ProcessEvent(Func, nullptr);
```

---

## 핵심 타입 객체 계층

```
UObject 계열 (타입 정보 자체를 표현)
  UObject
  └── UField
      └── UStruct
          ├── UClass        ← UCLASS 한 개당 하나
          ├── UScriptStruct ← USTRUCT 한 개당 하나
          └── UFunction     ← UFUNCTION 한 개당 하나

FField 계열 (UE5 — UObject에서 분리, 성능 최적화)
  FField
  └── FProperty
      ├── FBoolProperty
      ├── FIntProperty / FFloatProperty / FDoubleProperty
      ├── FObjectProperty     ← UObject* raw 포인터
      ├── FSoftObjectProperty ← TSoftObjectPtr<>
      ├── FWeakObjectProperty ← TWeakObjectPtr<>
      ├── FStructProperty     ← USTRUCT 인스턴스
      ├── FArrayProperty      ← TArray<>
      ├── FMapProperty        ← TMap<>
      └── FEnumProperty       ← UENUM
```

> UE4에서는 `UProperty`가 UObject를 상속했다.  
> UE5에서 `FProperty`로 이름이 바뀌고 UObject 계층에서 분리되었다.  
> 이유: 프로퍼티 객체는 수가 매우 많아 UObject로 두면 GUObjectArray가 급증해
> GC 부담이 커진다. FField는 UClass와 수명을 함께하며 직접 해제된다.

---

## 리플렉션 위에 올라타는 기능들

| 기능 | 리플렉션 사용 방식 |
|------|----------------|
| **가비지 컬렉션** | `FObjectProperty`가 오프셋을 알고 있어 GC가 UObject 그래프를 순회 |
| **직렬화** | `FProperty::SerializeItem()`으로 타입별 자동 직렬화·역직렬화 |
| **Blueprint VM** | `UClass` 인스턴스화, `ProcessEvent()`로 `UFunction` 호출 |
| **네트워크 RPC** | `UFUNCTION(Server/Client)` → gen.cpp가 네트워크 래퍼 자동 생성 |
| **에디터 Details 패널** | `TFieldIterator`로 `EditAnywhere` 프로퍼티 열거 → 위젯 생성 |
| **CDO 기본값 복사** | 신규 인스턴스 생성 시 CDO에서 `FProperty` 단위로 기본값 복사 |
| **`Cast<T>()` / `IsA<T>()`** | `SuperStruct` 체인을 따라 올라가며 타입 확인 |

---

## 내 노트
