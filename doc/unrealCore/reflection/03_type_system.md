# 런타임 타입 시스템 — UClass, UStruct, FProperty

> 소스:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Field.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UnrealType.h`

gen.cpp의 팩토리 코드가 실행된 뒤 메모리에 생기는 타입 객체 계층.

---

## UObject 계열 — 타입 메타데이터 컨테이너

```
UObject
└── UField                      ← 타입 노드의 공통 기반
    └── UStruct                 ← 프로퍼티/함수 목록을 보유하는 구조
        ├── UClass              ← UCLASS 한 개당 하나
        ├── UScriptStruct       ← USTRUCT 한 개당 하나
        └── UFunction           ← UFUNCTION 한 개당 하나
```

이들은 **UObject이므로** GC가 관리하고, 패키지에 속하고, GUObjectArray에 등록된다.

---

## FField 계열 — 성능 최적화로 UObject에서 분리 (UE5)

```
FField
└── FProperty                   ← UPROPERTY 한 개당 하나
    ├── FNumericProperty
    │   ├── FInt8Property / FInt16Property / FIntProperty / FInt64Property
    │   ├── FByteProperty       ← uint8, UENUM
    │   ├── FUInt16Property / FUInt32Property / FUInt64Property
    │   ├── FFloatProperty
    │   └── FDoubleProperty
    ├── FBoolProperty           ← bool, 비트 필드 지원
    ├── FStrProperty            ← FString
    ├── FNameProperty           ← FName
    ├── FTextProperty           ← FText
    ├── FObjectProperty         ← UObject* raw 포인터
    ├── FLazyObjectProperty     ← TLazyObjectPtr<>
    ├── FWeakObjectProperty     ← TWeakObjectPtr<>
    ├── FSoftObjectProperty     ← TSoftObjectPtr<>
    ├── FSoftClassProperty      ← TSoftClassPtr<>
    ├── FClassProperty          ← TSubclassOf<>
    ├── FStructProperty         ← USTRUCT 인스턴스
    ├── FArrayProperty          ← TArray<>
    ├── FMapProperty            ← TMap<>
    ├── FSetProperty            ← TSet<>
    ├── FEnumProperty           ← UENUM (int8 기반)
    ├── FDelegateProperty       ← DECLARE_DYNAMIC_DELEGATE
    └── FMulticastDelegateProperty ← DECLARE_DYNAMIC_MULTICAST_DELEGATE
```

> **UE4 → UE5 변경**: UE4에서는 `UProperty`가 UObject를 상속했다.
> UE5에서 `FProperty`로 이름이 바뀌고 UObject 계층에서 분리되었다.
>
> 이유: 프로퍼티 객체는 수가 매우 많다.
> 모든 클래스의 모든 멤버마다 UObject를 만들면 GUObjectArray가 수십만 항목으로 급증해
> GC 순회 비용이 폭증한다.
> FField는 UClass와 수명을 함께하며 `delete`로 직접 해제된다.

---

## UStruct 내부 구조

UClass, UScriptStruct, UFunction이 공통으로 갖는 핵심 필드.

```cpp
// Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h (간략화)
class UStruct : public UField
{
public:
    // 부모 타입 (UClass라면 부모 UClass, UScriptStruct라면 부모 USTRUCT)
    UStruct* SuperStruct;

    // UPROPERTY 링크드 리스트의 헤드
    // FProperty::Next 포인터로 체인 연결
    FField* ChildProperties;

    // 인스턴스 크기(바이트)와 정렬 요건
    int32 PropertiesSize;
    int32 MinAlignment;

    // (UClass 전용) 함수 맵
    // UFunction은 UObject이므로 별도 TMap으로 관리
    TMap<FName, UFunction*> FuncMap;   // UClass에만 있음
};
```

---

## UClass 추가 필드

```cpp
class UClass : public UStruct
{
public:
    // CDO 포인터 — NewObject<T>() 호출 시 기본값 복사 원본
    UObject* ClassDefaultObject;

    // 클래스 플래그
    EClassFlags ClassFlags;
    // 예: CLASS_Blueprintable, CLASS_Abstract, CLASS_Transient

    // 구현한 인터페이스 목록
    TArray<FImplementedInterface> Interfaces;

    // 생성자 함수 포인터 (gen.cpp의 __DefaultConstructor)
    typedef void (*ClassConstructorType)(const FObjectInitializer&);
    ClassConstructorType ClassConstructor;
};
```

---

## FProperty 핵심 필드

```cpp
class FProperty : public FField
{
public:
    int32          ArrayDim;          // 고정 배열 차원 (보통 1)
    int32          ElementSize;       // 원소 한 개의 크기(바이트)
    EPropertyFlags PropertyFlags;     // CPF_Edit, CPF_BlueprintVisible, CPF_Net ...
    int32          Offset_Internal;   // 소유 구조체 내 오프셋(바이트)

    // 소유 UStruct 안에서 이 프로퍼티의 주소를 계산
    template<typename T>
    T* ContainerPtrToValuePtr(void* ContainerPtr, int32 ArrayIndex = 0) const
    {
        return (T*)((uint8*)ContainerPtr + Offset_Internal + ArrayIndex * ElementSize);
    }

    // 아래는 서브클래스가 오버라이드하는 가상 함수들
    virtual void SerializeItem(...) const;    // 직렬화/역직렬화
    virtual void AddReferencedObjects(...);   // GC 참조 탐색 (FObjectProperty만 실질 구현)
    virtual void InitializeValue(void* Dest) const;    // 기본값 초기화
    virtual void CopyCompleteValue(void* Dest, const void* Src) const;
    virtual bool Identical(const void* A, const void* B, ...) const;  // 같은지 비교
};
```

---

## UFunction 구조

```cpp
class UFunction : public UStruct
{
public:
    // 함수 플래그
    EFunctionFlags FunctionFlags;
    // FUNC_BlueprintCallable, FUNC_Net, FUNC_NetServer,
    // FUNC_NetClient, FUNC_NetMulticast, FUNC_NetReliable ...

    // C++ 함수 포인터 (Native 함수)
    FNativeFuncPtr Func;

    // 파라미터 정보는 UStruct::ChildProperties에 FProperty로 저장됨
    // 반환값도 CPF_ReturnParm 플래그가 있는 FProperty로 표현
};
```

---

## 타입 정보 접근 API

```cpp
// ① 컴파일타임 — 타입을 알 때
UClass* Class = AMyActor::StaticClass();

// ② 런타임 — 인스턴스로부터 (실제 파생 타입 반환)
UClass* Class = SomeActor->GetClass();

// ③ 이름으로 검색
UClass* Class = FindObject<UClass>(nullptr, TEXT("/Script/MyGame.AMyActor"));

// ④ 프로퍼티 순회 (부모 클래스 포함)
for (TFieldIterator<FProperty> It(AMyActor::StaticClass()); It; ++It)
{
    FProperty* Prop = *It;
    UE_LOG(LogTemp, Log, TEXT("%s : %s"), *Prop->GetName(), *Prop->GetCPPType());
}

// ⑤ 부모 제외, 특정 타입만
for (TFieldIterator<FObjectProperty> It(
    AMyActor::StaticClass(), EFieldIteratorFlags::ExcludeSuper); It; ++It)
{
    // UObject* 멤버만 나옴
}

// ⑥ 함수 검색·호출
UFunction* Func = SomeActor->FindFunctionChecked(TEXT("Fire"));
SomeActor->ProcessEvent(Func, nullptr);

// ⑦ 특정 UClass 기반 모든 살아있는 인스턴스 순회 (에디터/개발용)
for (TObjectIterator<AMyActor> It; It; ++It)
{
    AMyActor* Actor = *It;
}

// ⑧ 프로퍼티 값 동적 읽기·쓰기
FProperty* Prop = AMyActor::StaticClass()->FindPropertyByName(TEXT("Health"));
if (FFloatProperty* FloatProp = CastField<FFloatProperty>(Prop))
{
    float Val = FloatProp->GetPropertyValue_InContainer(SomeActor);
    FloatProp->SetPropertyValue_InContainer(SomeActor, 200.f);
}
```

---

## IsA / Cast 와 리플렉션의 관계

언리얼의 `Cast<T>()`, `IsA<T>()` 모두 리플렉션 기반이다.

```cpp
// Cast — StaticClass()로 얻은 UClass의 SuperStruct 체인을 올라가며 확인
APawn* Pawn = Cast<APawn>(SomeActor);

// IsA
bool bIsPawn = SomeActor->IsA<APawn>();
bool bIsPawn = SomeActor->IsA(APawn::StaticClass());  // 동일
```

표준 `dynamic_cast`와 달리:
- RTTI 비활성화 빌드에서도 동작
- 런타임에 생성된 Blueprint UClass도 동일하게 처리
- `SuperStruct` 체인만 따라가면 되므로 성능이 예측 가능

---

## 내 노트
