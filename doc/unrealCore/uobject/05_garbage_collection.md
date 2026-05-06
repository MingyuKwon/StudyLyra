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

## GC가 참조를 추적하는 방법

GC는 `UGCObjectReferencer`로부터 시작해 **UPROPERTY로 선언된 참조만** 추적한다.  
Mark-and-Sweep 방식: 루트셋에서 시작해 도달 가능한 모든 UObject를 "살아있음"으로 표시한다.

```cpp
// GC가 추적함 — UPROPERTY 선언
UPROPERTY()
UMyObject* MyObj;

// GC가 모름 — raw pointer
UMyObject* MyObj;  // UPROPERTY 없음
```

UPROPERTY가 없는 raw pointer로 UObject를 들고 있으면:
- GC가 해당 객체를 "참조 없음"으로 판단해 수거할 수 있음
- 수거 후 포인터는 dangling pointer가 됨 → 크래시

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

## 내 노트

