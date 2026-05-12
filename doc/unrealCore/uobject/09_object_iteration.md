# UObject 순회 — TObjectIterator

> 소스:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/ObjectIterator.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectArray.h`

런타임에 메모리에 살아있는 UObject 인스턴스를 전체 순회하는 방법.

---

## 데이터 출처 — GUObjectArray

언리얼은 생성된 모든 UObject를 **전역 배열 `GUObjectArray`** 에 등록한다.

```
GUObjectArray (FUObjectArray)
  ├── FUObjectItem [0]  → UClass (AMyActor)       ← 타입 객체도 여기 있음
  ├── FUObjectItem [1]  → UClass (AActor)
  ├── FUObjectItem [2]  → AMyActor CDO
  ├── FUObjectItem [3]  → AMyActor 인스턴스 A
  ├── FUObjectItem [4]  → AMyActor 인스턴스 B
  ├── FUObjectItem [5]  → nullptr (삭제된 슬롯)
  └── ...
```

`FUObjectItem` 하나에는 `UObject*` 포인터와 내부 플래그(PendingKill 여부 등)가 들어있다.

UObject가 생성되는 순간 자동으로 등록된다.

```
NewObject<T>() / SpawnActor<T>()
  → StaticAllocateObject()
  → GUObjectArray.AllocateUObjectIndex()   ← 슬롯 배정
  → 이후부터 GUObjectArray에서 이 객체가 보임
```

파괴 시에는 슬롯이 즉시 비워지지 않고 `PendingKill` 플래그가 먼저 붙은 뒤
GC 사이클에서 실제로 제거된다.

---

## TObjectIterator 초기화와 동작

`TObjectIterator<T>`는 `GUObjectArray`를 인덱스 0부터 끝까지 순회하면서
`IsA(T::StaticClass())`로 타입을 필터링한다.

```cpp
// ObjectIterator.h (개념적 구현)
template<class T>
class TObjectIterator
{
    int32 Index;  // GUObjectArray 현재 인덱스

    void Advance()
    {
        while (++Index < GUObjectArray.GetObjectArrayNum())
        {
            FUObjectItem* Item = GUObjectArray.IndexToObject(Index);
            if (!Item || !Item->Object) continue;           // 빈 슬롯
            if (Item->HasAnyFlags(EInternalObjectFlags::PendingKill)) continue;
            if (Item->Object->IsA(T::StaticClass())) break; // 타입 일치
        }
    }
};
```

---

## 사용 예시

```cpp
for (TObjectIterator<UMyObject> It; It; ++It)
{
    UMyObject* Obj = *It;
    Obj->DoSomething();
}
```

---

## 주의사항

`GUObjectArray`는 게임 월드를 구분하지 않는다.  
다음 항목이 **모두 포함**되어 나온다.

| 포함되는 것 | 이유 |
|------------|------|
| CDO | 프로그램 시작 시 생성되어 GUObjectArray에 등록됨 |
| UClass, UFunction 등 타입 객체 | 이것들도 UObject |
| 에디터 오브젝트 | 에디터 모드에서는 에디터 전용 오브젝트도 여기 있음 |
| PIE 양쪽 월드 오브젝트 | Play In Editor 시 게임 월드와 에디터 월드가 섞임 |

실제 게임 인스턴스만 대상으로 하려면 필터가 필요하다.

```cpp
for (TObjectIterator<UMyObject> It; It; ++It)
{
    UMyObject* Obj = *It;

    // CDO 제외
    if (Obj->HasAnyFlags(RF_ClassDefaultObject)) continue;

    // PIE에서 게임 월드 오브젝트만
    if (Obj->GetWorld() && Obj->GetWorld()->IsGameWorld())
    {
        Obj->DoSomething();
    }
}
```

> `TObjectIterator`는 주로 **에디터 툴, 개발·디버깅** 용도로 쓴다.  
> 게임 런타임에서 Actor를 찾아야 하면 `TActorIterator`를 쓰는 것이 안전하다.  
> → [actor/03_actor_search.md](../actor/03_actor_search.md)

---

## 내 노트
