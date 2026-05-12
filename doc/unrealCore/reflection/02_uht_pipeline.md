# UHT 파이프라인 — generated.h와 gen.cpp 상세

> 소스:  
> `Engine/Source/Programs/UnrealHeaderTool/` (UHT 구현)  
> `Engine/Intermediate/Build/Win64/.../Inc/MyGame/` (생성 파일 출력 위치)

UHT(Unreal Header Tool)는 빌드 전에 실행되어
소스 헤더에서 `*.generated.h`와 `*.gen.cpp` 두 파일을 만든다.

---

## UHT가 파싱하는 항목

```
헤더 매크로                UHT가 생성하는 대상 타입 객체
────────────────────────────────────────────────
UCLASS(...)           →   UClass
USTRUCT(...)          →   UScriptStruct
UFUNCTION(...)        →   UFunction
UPROPERTY(...)        →   FProperty (서브클래스는 타입에 따라 결정)
UENUM(...)            →   UEnum
UMETA(...)            →   FProperty/UFunction의 메타데이터 태그
```

UHT는 C++ 파서가 아니다.  
전처리·템플릿 인스턴스화 없이 **정적 텍스트 파싱**으로 이 마커들을 찾는다.  
따라서 UCLASS/UPROPERTY 괄호 안에 복잡한 C++ 표현식이 들어가면 UHT가 이해하지 못한다.

---

## generated.h — 클래스 본문에 삽입되는 선언 코드

`AMyActor.generated.h`의 주요 내용:

```cpp
// ① CURRENT_FILE_ID 정의
//    GENERATED_BODY() 매크로 이름을 조립할 때 사용
#undef  CURRENT_FILE_ID
#define CURRENT_FILE_ID FID_MyGame_Source_MyGame_AMyActor_h

// ② GENERATED_BODY()가 최종적으로 확장될 매크로 정의
//    줄 번호(25)는 헤더에서 GENERATED_BODY()가 위치한 실제 줄
#define FID_MyGame_Source_MyGame_AMyActor_h_25_GENERATED_BODY \
    FID_MyGame_Source_MyGame_AMyActor_h_25_SPARSE_DATA \
    FID_MyGame_Source_MyGame_AMyActor_h_25_RPC_WRAPPERS_NO_PURE_DECLS \
    FID_MyGame_Source_MyGame_AMyActor_h_25_INCLASS_NO_PURE_DECLS \
    FID_MyGame_Source_MyGame_AMyActor_h_25_ENHANCED_CONSTRUCTORS

// ③ _ENHANCED_CONSTRUCTORS 안에 실제 코드가 들어 있다
#define FID_MyGame_Source_MyGame_AMyActor_h_25_ENHANCED_CONSTRUCTORS \
private: \
    /** 복사 불가 */ \
    AMyActor(const AMyActor&) = delete; \
    AMyActor& operator=(const AMyActor&) = delete; \
public: \
    DECLARE_VTABLE_PTR_HELPER_CTOR(NO_API, AMyActor); \
    DEFINE_VTABLE_PTR_HELPER_CTOR_CALLER(AMyActor); \
    DEFINE_DEFAULT_OBJECT_INITIALIZER_CONSTRUCTOR_CALL(AMyActor) \
    NO_API virtual ~AMyActor();

// ④ StaticClass() 선언 — 구현은 gen.cpp
#define DECLARE_CLASS(TClass, TSuperClass, ...) \
public: \
    static UClass* StaticClass(); \
    static UClass* GetPrivateStaticClass(); \
    ...
```

> `GENERATED_BODY()` → 매크로 이름 조립 → 이 정의 호출 흐름은
> [uobject/01_overview.md](../uobject/01_overview.md)에 상세히 다룬다.

---

## gen.cpp — 런타임 타입 객체 팩토리

`AMyActor.gen.cpp`의 구조를 단계별로 본다.

### 1단계: 프로퍼티 서술 구조체

UHT가 각 `UPROPERTY`마다 정적 파라미터 구조체를 생성한다.

```cpp
// Health (float) 프로퍼티 기술자
static const UECodeGen_Private::FFloatPropertyParams NewProp_Health = {
    "Health",                            // 프로퍼티 이름
    nullptr,                             // RepNotify 함수 이름 (없으면 nullptr)
    (EPropertyFlags)0x0010000000000001,  // CPF_Edit | CPF_BlueprintVisible
    UECodeGen_Private::EPropertyGenFlags::Float,
    RF_Public | RF_Transient | RF_MarkAsNative,
    nullptr, nullptr, 1,
    STRUCT_OFFSET(AMyActor, Health),     // 구조체 내 바이트 오프셋
    METADATA_PARAMS(NewProp_Health_MetaData, UE_ARRAY_COUNT(NewProp_Health_MetaData))
};

// 클래스의 모든 UPROPERTY 포인터 배열
static const FPropertyParamsBase* const PropPointers[] = {
    (const FPropertyParamsBase*)&NewProp_Health,
    // ... 다른 UPROPERTY들
};
```

### 2단계: 함수 서술 구조체

```cpp
// Fire() 함수 기술자
static const UECodeGen_Private::FFunctionParams FuncParams_Fire = {
    (UObject*(*)())Z_Construct_UClass_AMyActor,  // 소유 클래스 팩토리
    nullptr,                                      // 슈퍼 함수
    "Fire",                                       // 함수 이름
    nullptr,                                      // 파라미터 FProperty 배열
    0,                                            // 파라미터 개수
    FUNC_Public | FUNC_BlueprintCallable | FUNC_Net | FUNC_NetServer | FUNC_NetReliable,
    RF_Public | RF_Transient | RF_MarkAsNative,
    METADATA_PARAMS(...)
};
```

### 3단계: 클래스 파라미터 구조체

프로퍼티·함수·의존성·플래그를 한 데 모은다.

```cpp
static const UECodeGen_Private::FClassParams ClassParams_AMyActor = {
    &AMyActor::StaticClass,       // StaticClass() 함수 포인터
    nullptr,                       // Config 파일 이름 (없으면 nullptr)
    &StaticCppClassTypeInfo,       // C++ 타입 크기·정렬 정보
    DependentSingletons,           // 의존하는 UClass 팩토리 포인터 목록
    FuncInfo,                      // UFUNCTION 기술자 목록
    PropPointers,                  // UPROPERTY 기술자 목록
    nullptr,                       // 구현한 인터페이스 목록
    UE_ARRAY_COUNT(DependentSingletons),
    UE_ARRAY_COUNT(FuncInfo),
    UE_ARRAY_COUNT(PropPointers),
    0, 0,
    0x009000A4u,                   // ClassFlags (Blueprintable 등 비트 조합)
    0,
    METADATA_PARAMS(...)
};
```

### 4단계: Z_Construct_UClass_ 팩토리 함수

엔진이 이 함수를 처음 호출할 때 `UClass`가 생성·완성된다.

```cpp
UClass* Z_Construct_UClass_AMyActor()
{
    if (!Z_Registration_Info_UClass_AMyActor.InnerSingleton)
    {
        UECodeGen_Private::ConstructUClass(
            Z_Registration_Info_UClass_AMyActor.InnerSingleton,
            ClassParams_AMyActor   // 위의 FClassParams 전달
        );
    }
    return Z_Registration_Info_UClass_AMyActor.InnerSingleton;
}

// StaticClass() 구현도 gen.cpp에
UClass* AMyActor::StaticClass()
{
    return Z_Construct_UClass_AMyActor();
}
```

`ConstructUClass()`가 내부에서:
- `FProperty` 객체들을 생성해 `UClass::ChildProperties`에 연결
- `UFunction` 객체들을 생성해 `UClass::FuncMap`에 삽입
- `SuperStruct`를 부모 `UClass`에 연결
- ClassFlags·PropertyFlags를 적용

### 5단계: 자동 등록 (static initializer)

```cpp
// 이 객체의 생성자가 프로그램 시작 시 자동 실행됨
static FRegisterCompiledInInfo Z_CompiledInDeferFile_...(
    TEXT("/Script/MyGame"),                    // 패키지 경로
    Z_CompiledInDeferFile_ClassInfo,           // { 팩토리 함수, 크기, 이름, ... }
    UE_ARRAY_COUNT(Z_CompiledInDeferFile_ClassInfo),
    nullptr, 0,   // 구조체 등록 없음
    nullptr, 0    // 열거형 등록 없음
);
```

---

## 등록 체인 전체 흐름

```
프로그램 시작
  → gen.cpp의 static 변수 초기화 (링커 순서대로)
  → FRegisterCompiledInInfo 생성자 실행
  → 팩토리 함수 포인터를 전역 목록(GUObjectProcessors)에 등록
         │
         ▼ (CoreUObject 모듈 로드 시점)
  ProcessNewlyLoadedUObjects() 호출
  → 등록된 팩토리 함수들 순서대로 실행
  → Z_Construct_UClass_XXX() 호출
  → UECodeGen_Private::ConstructUClass()
      ├── FProperty 객체 생성 (FFloatProperty, FObjectProperty ...)
      ├── UFunction 객체 생성
      ├── SuperStruct 체인 연결
      └── ClassFlags / PropertyFlags 적용
  → GUObjectArray에 UClass 등록 (RF_MarkAsNative 설정)
  → CDO 생성 → __DefaultConstructor 호출 → AMyActor 기본 생성자 실행
  → UClass.ClassDefaultObject 포인터 저장
```

> `UClass`가 완전히 초기화되기 전에는 `StaticClass()`를 안전하게 호출할 수 없다.
> 전역 생성자에서 `StaticClass()`를 호출하면 초기화 순서 문제가 생길 수 있다.

---

## RPC UFUNCTION의 추가 생성 코드

`UFUNCTION(Server, Reliable)` 선언이 있으면
gen.cpp에 네트워크 래퍼가 추가로 생성된다.

```cpp
// gen.cpp (개념적 구현)

// 실제 호출되는 Fire() — 클라이언트 측에서 RPC 패킷 전송
void AMyActor::Fire()
{
    // 서버 RPC 전송 로직
    ProcessEvent(FindFunctionChecked(TEXT("Fire")), nullptr);
}
// 서버 측에서 실행될 실제 구현은 Fire_Implementation()
// → .cpp에서 개발자가 직접 작성
```

함수 플래그(FUNC_Net | FUNC_NetServer | FUNC_NetReliable)가
`UFunction` 객체에 기록되어 있어 `NetDriver`가 호출 시
로컬 실행 vs 패킷 전송 여부를 판단한다.

---

## 내 노트

### UFUNCTION 종류별 호출 경로 — gen.cpp 개입 여부

UFUNCTION이 붙는다고 항상 gen.cpp 래퍼를 경유하는 것이 아니다.  
**gen.cpp가 함수 본체를 대신 생성하는 경우에만** ProcessEvent를 경유한다.

#### 일반 BlueprintCallable

```cpp
UFUNCTION(BlueprintCallable)
void Fire();
```

C++에서 `actor->Fire()`를 직접 호출하면 gen.cpp 개입 없이 바로 C++ 함수가 실행된다.  
gen.cpp가 하는 일은 `UFunction` 메타데이터 객체 생성뿐이고, 호출 경로엔 끼지 않는다.

Blueprint 노드에서 호출할 때만 `exec_Fire()` thunk 함수를 경유해 C++로 들어온다.

#### BlueprintNativeEvent / BlueprintImplementableEvent

이 두 지정자는 **gen.cpp가 함수 본체 자체를 생성**한다. 개발자가 직접 `Fire()` 바디를 작성하지 않는다.

```cpp
// gen.cpp가 생성하는 Fire() 본체 (개념적 구현)
void AMyActor::Fire()
{
    ProcessEvent(FindFunctionChecked(TEXT("Fire")), nullptr);
    // Blueprint 오버라이드 있으면 → Blueprint VM 실행
    // 없으면 → Fire_Implementation() 호출 (NativeEvent의 경우)
}
```

C++에서 `actor->Fire()`를 호출해도 이 gen.cpp 생성 함수를 통해 ProcessEvent로 간다.  
`BlueprintImplementableEvent`는 `_Implementation`이 없으며, BP 오버라이드도 없으면 아무것도 실행되지 않는다.

#### RPC (Server / Client / NetMulticast)

BlueprintNativeEvent와 동일한 구조다.  
gen.cpp가 `ServerFire()` 본체를 생성하고, ProcessEvent → NetDriver 경로로 연결한다.  
개발자는 `ServerFire_Implementation()`만 작성한다.

#### 정리

| UFUNCTION 종류 | C++에서 직접 호출 시 경로 |
|----------------|--------------------------|
| `BlueprintCallable` (일반) | 직접 C++ 함수 실행 — gen.cpp 개입 없음 |
| `BlueprintNativeEvent` | gen.cpp 생성 본체 → ProcessEvent → BP 오버라이드 or `_Implementation` |
| `BlueprintImplementableEvent` | gen.cpp 생성 본체 → ProcessEvent → BP VM (오버라이드 없으면 아무것도 안 함) |
| `Server` / `Client` / `NetMulticast` | gen.cpp 생성 본체 → ProcessEvent → NetDriver |
