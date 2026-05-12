# 가비지 컬렉션

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Private/UObjectGlobals.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/GarbageCollection.cpp`

---

## UObject가 삭제되는 시점

UObject는 `delete`를 직접 호출하지 않는다.  
엔진 GC가 주기적으로 돌면서 "참조되지 않는" UObject를 찾아 수거한다.

삭제 흐름:

```
1. 참조 카운트가 0이 됨 (아무 UPROPERTY도 이 객체를 가리키지 않음)
2. 다음 GC 사이클에서 "도달 불가" 판정
3. ConditionalBeginDestroy() → BeginDestroy() 호출
4. IsReadyForFinishDestroy() == true 확인 후
5. FinishDestroy() 호출
6. 메모리 해제
```

GC 주기는 기본적으로 매 프레임은 아니고 일정 간격(약 60초마다 또는 메모리 압박 시)으로 실행된다.  
따라서 참조를 끊었다고 해서 **즉시** 메모리가 해제되지는 않는다.

---

## GC가 참조를 추적하는 방법 — Token Stream

GC는 **UPROPERTY로 선언된 참조만** 추적한다.  
Mark-and-Sweep 방식: 루트셋에서 시작해 도달 가능한 모든 UObject를 "살아있음"으로 표시한다.

UHT는 UPROPERTY를 파싱해 각 UClass마다 **Token Stream**을 생성한다.  
Token Stream은 해당 클래스 인스턴스 안에서 UPROPERTY 포인터가 있는 **메모리 오프셋 목록**이다.

```
AMyActor의 Token Stream (UHT가 generated 코드에 심어둠):
  offset 0x40 → UPROPERTY UMyObject* Target
  offset 0x48 → UPROPERTY AActor*   Owner
  ...
```

GC는 Mark 단계에서 이 Token Stream을 읽어 각 슬롯이 가리키는 객체를 "살아있음"으로 표시한다.  
raw pointer는 Token Stream에 없으므로 GC가 전혀 모른다.

```cpp
UPROPERTY()
UMyObject* MyObj;   // Token Stream에 있음 → GC가 추적, 살아있는 한 수거 안 됨

UMyObject* MyObj;   // Token Stream에 없음 → GC가 모름 → 수거 후 dangling
```

---

## UPROPERTY 참조가 자동으로 null이 되는 원리

UPROPERTY로 들고 있으면 GC가 수거하지 않는다.  
auto-null은 객체가 **명시적으로 파괴될 때** 일어난다 (`Destroy()` / `MarkAsGarbage()`).

GC 전체 단계:

```
1. Mark 단계
   루트셋에서 출발 → Token Stream 따라 도달 가능한 객체 전부 "살아있음" 표시

2. 명시적 파괴 (Destroy / MarkAsGarbage 호출)
   → 해당 객체에 RF_BeginDestroyed 플래그 설정
   → IsValid() 즉시 false 반환

3. Null Reference 단계
   살아있는 모든 UObject를 순회
   → 각 객체의 Token Stream을 읽어 UPROPERTY 슬롯 확인
   → 슬롯이 가리키는 객체가 RF_BeginDestroyed이면 → null로 덮어씀
   (raw pointer는 Token Stream에 없으므로 이 단계에서 건드리지 못함)

4. Destroy 단계
   RF_BeginDestroyed 객체 실제 메모리 해제
```

```cpp
UPROPERTY()
UMyObject* Target;      // SomeObj를 가리키고 있음

SomeObj->MarkAsGarbage();
// → GC Null Reference 단계에서 Token Stream 순회
// → Target 슬롯이 SomeObj를 가리킴 확인
// → Target = nullptr 로 덮어씀

// 이후
if (IsValid(Target)) { ... }   // nullptr이므로 안전하게 false
```

raw pointer는 Token Stream에 없으므로 3단계에서 건드리지 못한다 → dangling pointer 위험.

---

## 루트셋 — AddToRoot

GC 루트셋에 직접 추가하면 참조가 없어도 수거되지 않는다.

```cpp
MyObj->AddToRoot();     // GC 수거 대상에서 제외
MyObj->RemoveFromRoot(); // 다시 수거 대상으로 포함
```

싱글턴처럼 영구적으로 유지해야 하는 UObject에 사용한다.  
`RemoveFromRoot()`를 빠뜨리면 메모리 누수가 된다.

---

## TWeakObjectPtr

UPROPERTY 없이 UObject를 참조하되 dangling pointer를 방지하고 싶을 때 사용한다.  
참조 대상이 수거되면 자동으로 null이 된다.

```cpp
TWeakObjectPtr<AMyActor> WeakRef = SomeActor;

if (WeakRef.IsValid())
{
    WeakRef->DoSomething();
}
```

GC 추적 대상이 아니므로 WeakObjectPtr 혼자서는 객체를 살려두지 못한다.

---

## 수동 삭제가 필요한 경우

즉시 파괴하고 싶을 때는 명시적 함수를 사용한다.

```cpp
// Actor 파괴
Actor->Destroy();           // 다음 틱 전에 BeginDestroy까지 진행

// 일반 UObject 즉시 파괴
MyObj->MarkAsGarbage();     // UE5에서 MarkPendingKill 대체
// 또는
MyObj->ConditionalBeginDestroy();
```

`Destroy()`는 Actor 전용이다. 일반 UObject에는 사용할 수 없다.

---

## 케이스별 GC 추적 여부

### 컨테이너(TArray / TMap / TSet)에 UObject를 넣어둔 경우

컨테이너 자체에 UPROPERTY가 있느냐 없느냐가 기준이다.  
GC는 `FArrayProperty` / `FMapProperty` / `FSetProperty`가 컨테이너 안을 재귀적으로 들여다본다.

```cpp
UPROPERTY()
TArray<UObject*> TrackedArray;   // GC가 내부 UObject* 추적 → 수집 안 됨

TArray<UObject*> UntrackedArray; // GC 모름 → 수집됨
```

**수집 방지**: 컨테이너 선언에 `UPROPERTY()` 를 붙인다.  
컨테이너 안의 개별 UObject*에 UPROPERTY를 붙이는 것은 의미 없다 — 컨테이너 자체가 추적 대상이 되어야 한다.

### USTRUCT 안에 UPROPERTY UObject 멤버가 있는 경우

USTRUCT 내부 UPROPERTY만으로는 부족하다.  
**USTRUCT 인스턴스 자체가 GC 추적 경로 안에 있어야 한다.**

GC는 UClass → FStructProperty → 구조체 내부 FProperty 순으로 재귀 탐색한다.  
USTRUCT 인스턴스가 추적 경로에서 끊기면 내부 UPROPERTY도 의미 없다.

```cpp
USTRUCT()
struct FMyStruct
{
    GENERATED_BODY()

    UPROPERTY()
    UMyObject* Obj;
};

UCLASS()
class AMyActor : public AActor
{
    UPROPERTY()
    FMyStruct MyStruct;   // 구조체에 UPROPERTY → GC가 내부 Obj까지 재귀 탐색 → 수집 안 됨

    FMyStruct MyStruct2;  // UPROPERTY 없음 → GC가 구조체 자체를 모름 → 내부 Obj도 수집됨
};
```

**수집 방지**: 구조체 멤버 UPROPERTY와 **구조체 인스턴스 선언 모두** UPROPERTY가 있어야 한다.  
둘 중 하나라도 빠지면 GC 추적 체인이 끊긴다.

### 네이티브 C++ 클래스/구조체에 UPROPERTY를 붙인 경우

UPROPERTY가 아무 효과가 없다.  
UHT는 `GENERATED_BODY()`가 없는 클래스·구조체를 처리하지 않으므로 FProperty가 생성되지 않는다.  
GC는 이 포인터의 존재를 전혀 모른다.

```cpp
struct FNativeStruct   // USTRUCT 아님, GENERATED_BODY() 없음
{
    UPROPERTY()        // UHT가 무시 → FProperty 생성 안 됨 → GC 추적 안 됨
    UMyObject* Obj;    // → 수집됨
};
```

**수집 방지**: 네이티브 C++ 클래스에서는 UPROPERTY로 UObject를 보호할 수 없다.  
아래 중 하나를 선택해야 한다.

```cpp
// ① 클래스를 UCLASS로 변경
UCLASS()
class UMyClass : public UObject
{
    GENERATED_BODY()

    UPROPERTY()
    UMyObject* Obj;   // 이제 GC 추적됨
};

// ② AddToRoot로 UObject 자체를 루트셋에 고정
Obj->AddToRoot();     // GC 수거 대상에서 제외 (RemoveFromRoot() 잊지 말 것)

// ③ FGCObject 상속 — 네이티브 클래스에서 UObject 참조를 GC에 알리는 공식 방법
class FMyNativeClass : public FGCObject
{
public:
    UMyObject* Obj;

    virtual void AddReferencedObjects(FReferenceCollector& Collector) override
    {
        Collector.AddReferencedObject(Obj);   // GC에 직접 참조 등록
    }

    virtual FString GetReferencerName() const override
    {
        return TEXT("FMyNativeClass");
    }
};
```

`FGCObject`는 네이티브 C++ 클래스가 UCLASS 없이 UObject 참조를 GC에 등록할 수 있는 공식 인터페이스다.

### 요약

| 케이스 | GC 추적 | 수집 방지 방법 |
|--------|---------|--------------|
| 컨테이너에 UPROPERTY 있음 | O | (이미 안전) |
| 컨테이너에 UPROPERTY 없음 | X | 컨테이너에 `UPROPERTY()` 추가 |
| USTRUCT 내 UPROPERTY + 구조체 인스턴스도 UPROPERTY | O | (이미 안전) |
| USTRUCT 내 UPROPERTY + 구조체 인스턴스는 UPROPERTY 없음 | X | 구조체 인스턴스 선언에도 `UPROPERTY()` 추가 |
| 네이티브 C++ 클래스에 UPROPERTY | X | `FGCObject` 상속 또는 `AddToRoot()` |

---

## 내 노트

