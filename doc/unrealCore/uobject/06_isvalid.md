# MarkAsGarbage / IsValid / IsValidLowLevel

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectBaseUtility.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Object.h`

---

## MarkAsGarbage

UObject를 **즉시 메모리에서 삭제하지 않고** garbage 상태로 만드는 함수다.  
UE4의 `MarkPendingKill`이 UE5에서 `MarkAsGarbage`로 대체됐다.

```cpp
MyObj->MarkAsGarbage();   // UE5
```

호출 직후:
1. 객체에 garbage 플래그 설정
2. 다음 GC 사이클에서 수거 대상으로 처리
3. 이 객체를 가리키는 **UPROPERTY 포인터는 GC 수거 시 자동으로 null**
4. raw pointer는 null이 되지 않음 → dangling pointer

`AActor::Destroy()`도 내부적으로 `MarkAsGarbage()`를 호출한다.  
Destroy 직후 액터는 garbage 플래그가 세워지지만 메모리에는 아직 있다.

---

## IsValid() — 왜 null 체크로 충분하지 않은가

```cpp
bool IsValid(const UObject* Test);
```

`Destroy()` / `MarkAsGarbage()` 호출 후 GC 수거 전 구간이 문제다.

```cpp
UPROPERTY()
AActor* Target;

Target->Destroy();       // garbage 플래그 세워짐, 메모리는 아직 있음

Target != nullptr        // TRUE  — UPROPERTY auto-null은 GC 수거 시 일어남
IsValid(Target)          // FALSE — garbage 플래그 감지
```

GC 수거 → UPROPERTY auto-null이므로, GC 수거 이후는 null 체크로 잡힌다.  
잡히지 않는 구간은 **"Destroy됐지만 아직 수거 전"** 이다. IsValid()가 이 구간을 커버한다.

```cpp
// 올바른 패턴
if (IsValid(Target))
{
    Target->DoSomething();
}

// 위험한 패턴
if (Target != nullptr)
{
    Target->DoSomething();  // Destroy 후 garbage 상태 액터에 접근 가능
}
```

IsValid() 내부:

```cpp
IsValid(Obj) = Obj != nullptr
            && !Obj->IsUnreachable()          // GC 수거 대상으로 표시됐는지
            && !Obj->IsPendingKillOrUnreachable() // MarkAsGarbage / Destroy 됐는지
```

---

## 어떤 UObject에 IsValid()가 필요한가

IsValid()가 필요한 조건은 **"명시적으로 Destroy / MarkAsGarbage 될 수 있는가"** 다.

| 타입 | 죽는 방식 | 필요한 체크 |
|------|-----------|------------|
| AActor | `Destroy()` → garbage 플래그 | `IsValid()` |
| UActorComponent | `DestroyComponent()` → garbage 플래그 | `IsValid()` |
| UDataAsset | 패키지 언로드 → GC 수거 → UPROPERTY auto-null | null 체크로 충분 |
| UGameInstance / UGameState | 게임 종료 시 GC 수거 → UPROPERTY auto-null | null 체크로 충분 |

DataAsset 같은 에셋성 오브젝트는 명시적으로 Destroy되지 않는다.  
사라질 때는 GC가 UPROPERTY를 auto-null해주므로 null 체크만으로 충분하다.

단, IsValid() 자체의 비용이 거의 없고, 오브젝트의 수명이 불확실하다면 IsValid()를 쓰는 것이 더 안전하다.

---

## IsValidLowLevel()

```cpp
bool UObject::IsValidLowLevel() const;
```

GC 플래그가 아니라 **이 포인터가 실제로 유효한 UObject 메모리를 가리키는지** 검사한다.  
`GUObjectArray`에 이 주소가 등록되어 있는지 확인하는 방식이다.

| 항목 | IsValid | IsValidLowLevel |
|------|---------|-----------------|
| nullptr 체크 | O | O |
| garbage 플래그 체크 | O | X |
| 메모리 레벨 유효성 | X | O (GUObjectArray 검사) |
| 비용 | 저 | 중 |
| 용도 | 게임플레이 코드 | 엔진 내부, 직렬화, 에디터 |

일반 게임플레이 코드에서 IsValidLowLevel을 써야 한다면 설계를 재고하는 것이 맞다.

---

## 요약

```
Destroy / MarkAsGarbage될 수 있는 오브젝트 (Actor, Component):
  → IsValid(Ptr)

에셋, GameInstance 등 명시적으로 죽지 않는 오브젝트:
  → Ptr != nullptr  (null 체크로 충분)

포인터가 실제 UObject 메모리인지 확인해야 할 때 (엔진 내부):
  → Ptr->IsValidLowLevel()

Actor 파괴:
  → Actor->Destroy()

Actor 외 UObject 파괴:
  → Ptr->MarkAsGarbage()
```

---

## 내 노트
