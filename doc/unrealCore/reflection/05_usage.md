# 리플렉션 활용 — GC, 직렬화, Blueprint, RPC, 에디터

리플렉션 타입 시스템이 실제로 어떻게 쓰이는지를 기능별로 정리한다.

---

## 가비지 컬렉션 (GC)

GC는 살아있는 UObject를 찾기 위해 **리플렉션으로 UObject* 포인터를 추적**한다.

```
GC Mark 단계
  → 루트셋(RF_RootSet 표시 객체)에서 출발
  → 각 UObject의 UClass 조회
  → UClass의 ChildProperties 링크드 리스트 순회
  → FObjectProperty / FWeakObjectProperty 발견 시
      ContainerPtrToValuePtr()로 실제 포인터 주소 계산
      → 참조된 UObject를 "도달 가능(Reachable)"으로 표시
  → 재귀 반복
  → 표시 안 된 UObject → GC 수집(Destroy) 대상
```

```cpp
// FObjectProperty::AddReferencedObjects (개념적 구현)
void FObjectProperty::AddReferencedObjects(
    UObject* Owner, FReferenceCollector& Collector)
{
    // Offset_Internal을 이용해 이 프로퍼티가 가리키는 UObject*를 찾음
    UObject** ObjPtr = ContainerPtrToValuePtr<UObject*>(Owner);
    Collector.AddReferencedObject(*ObjPtr);
}
```

`UPROPERTY()`가 없는 raw `UObject*` 멤버는 이 과정에 참여하지 않는다.  
GC가 모르는 참조이므로 해당 UObject가 수집되면 댕글링 포인터가 된다.

---

## 직렬화 (Serialization)

저장/로드, undo/redo, 네트워크 복제, CDO 기본값 복사는
모두 **FProperty::SerializeItem()** 으로 각 프로퍼티를 타입별로 처리한다.

```cpp
// UObject::Serialize (개념적 흐름)
void UObject::Serialize(FArchive& Ar)
{
    for (TFieldIterator<FProperty> It(GetClass()); It; ++It)
    {
        FProperty* Prop = *It;

        // Transient·NoSave 플래그가 있으면 건너뜀
        if (!Prop->ShouldSerializeValue(Ar)) continue;

        // 이 오브젝트 메모리 안에서 프로퍼티가 위치한 주소 계산
        void* PropAddr = Prop->ContainerPtrToValuePtr<void>(this);

        // 타입별 직렬화 — 서브클래스가 오버라이드
        Prop->SerializeItem(FStructuredArchive::FSlot(Ar), PropAddr, nullptr);
    }
}
```

`FArchive`의 구현체가 실제 목적지를 결정한다.

| FArchive 서브클래스 | 사용처 |
|---------------------|--------|
| `FObjectWriter` / `FObjectReader` | UObject 복사·붙여넣기 |
| `FMemoryWriter` / `FMemoryReader` | 메모리 버퍼 |
| `FNetBitWriter` / `FNetBitReader` | 네트워크 패킷 |
| `FSaveGameArchive` | 세이브 파일 |

---

## Blueprint VM

Blueprint 스크립트는 **리플렉션 타입 시스템 위에서 실행되는 VM**이다.

### 클래스 인스턴스화

```cpp
// Blueprint 에셋 → UClass* → 인스턴스 생성
UClass* BPClass = LoadClass<AActor>(
    nullptr,
    TEXT("/Game/Blueprints/BP_MyActor.BP_MyActor_C")
);
AActor* Actor = GetWorld()->SpawnActor<AActor>(BPClass, Transform);
```

`BP_MyActor_C`는 에디터가 런타임에 생성한 UClass다.
이 UClass도 StaticClass()가 있고 ChildProperties·FuncMap이 있어
C++ 클래스와 동일하게 리플렉션 API로 접근할 수 있다.

### 함수 호출 (ProcessEvent)

```cpp
UFunction* Func = Actor->FindFunctionChecked(TEXT("Fire"));
Actor->ProcessEvent(Func, nullptr);
// 파라미터가 있으면:
//   struct { int32 Ammo; float Speed; } Params = {10, 500.f};
//   Actor->ProcessEvent(Func, &Params);
```

`ProcessEvent` 내부:
1. `UFunction`에 FUNC_BlueprintImplementableEvent 플래그 있으면 Blueprint VM 실행
2. `_Implementation` 이 있으면 C++ 함수 포인터(`UFunction::Func`)로 직접 호출
3. RPC 플래그 있으면 NetDriver로 패킷 전송

### 프로퍼티 동적 읽기·쓰기

```cpp
FProperty* Prop = Actor->GetClass()->FindPropertyByName(TEXT("Health"));
if (FFloatProperty* FloatProp = CastField<FFloatProperty>(Prop))
{
    float Current = FloatProp->GetPropertyValue_InContainer(Actor);
    FloatProp->SetPropertyValue_InContainer(Actor, Current + 50.f);
}
```

Blueprint 변수 Get/Set 노드는 내부적으로 이 경로를 사용한다.

---

## 네트워크 RPC

RPC 호출 흐름은 리플렉션 + gen.cpp 생성 코드의 협업이다.

```
클라이언트에서 ServerFire(Dir) 호출
  → gen.cpp 래퍼 함수 실행
  → ProcessEvent(UFunction("ServerFire"), &Params)
  → UFunction 플래그 확인: FUNC_Net | FUNC_NetServer
  → 네트워크 경로 진입
  → FProperty로 파라미터 직렬화 (FNetBitWriter)
  → 서버로 패킷 전송
         │
         ▼ (서버 수신)
  → NetDriver가 패킷 역직렬화
  → Actor->ProcessEvent(UFunction("ServerFire"), DeserializedParams)
  → ServerFire_Implementation(Dir) 실행

  (WithValidation 있으면)
  → ServerFire_Validate(Dir) 먼저 실행
  → false 반환 시 연결 끊음
```

함수 플래그(FUNC_Net | FUNC_NetServer | FUNC_NetReliable 등)가
`UFunction` 객체에 저장되어 있어 NetDriver가 이를 읽어 라우팅을 결정한다.

---

## 에디터 Details 패널

에디터가 선택된 Actor의 Details 패널을 그릴 때:

```
선택된 AActor
  → GetClass()
  → TFieldIterator<FProperty> 순회
  → EditAnywhere / EditInstanceOnly 플래그 있는 것만 필터
  → FProperty 타입에 맞는 위젯 생성:
      FFloatProperty      → SNumericEntryBox<float>
      FBoolProperty       → SCheckBox
      FObjectProperty     → SObjectPropertyEntryBox (에셋 드래그·드롭)
      FStructProperty     → 구조체 내부를 재귀적으로 순회
      FArrayProperty      → 배열 원소 개수만큼 위젯 반복
  → 값 변경 → FProperty::SetValue_InContainer()
  → 에디터 트랜잭션 기록 → undo/redo 가능

  메타데이터 활용:
  → Prop->GetMetaData(TEXT("ClampMin"))  → 입력 범위 제한
  → Prop->GetMetaData(TEXT("DisplayName")) → 표시 이름
  → Prop->GetMetaData(TEXT("ToolTip"))   → 툴팁
```

`Category="Combat"` 지정자도 메타데이터로 저장되어
Details 패널이 카테고리별 섹션을 구성하는 데 사용한다.

---

## CDO 기본값 복사

`NewObject<T>()` 또는 `SpawnActor<T>()` 시 새 인스턴스의 초기값은
CDO에서 복사된다.

```
NewObject<AMyActor>() 호출
  → 메모리 할당
  → AMyActor::StaticClass()->ClassConstructor() 실행 (생성자 호출)
  → CDO 복사:
      UClass의 ChildProperties 순회
      각 FProperty->CopyCompleteValue(NewInst + Offset, CDO + Offset)
  → 신규 인스턴스 반환
```

`UPROPERTY()`로 선언된 멤버만 복사 대상이다.
UPROPERTY 없는 멤버는 생성자에서 직접 초기화해야 한다.

---

## 내 노트
