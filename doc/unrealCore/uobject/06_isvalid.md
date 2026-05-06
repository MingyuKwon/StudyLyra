# MarkPendingKill / IsValid / IsValidLowLevel

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectBaseUtility.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Object.h`  
> `Engine/Source/Runtime/CoreUObject/Public/Templates/Casts.h`

---

## MarkPendingKill (UE4) / MarkAsGarbage (UE5)

UObject를 **즉시 메모리에서 삭제하지 않고** "수거 예약" 상태로 만드는 함수다.

```cpp
// UE4
MyObj->MarkPendingKill();

// UE5 (MarkPendingKill은 deprecated, MarkAsGarbage로 대체)
MyObj->MarkAsGarbage();
```

호출 직후 일어나는 일:
1. 객체에 `RF_BeginDestroyed` 플래그 설정
2. GC가 다음 사이클에서 이 객체를 수거 대상으로 처리
3. UPROPERTY로 참조 중이던 포인터는 자동으로 **null로 바뀜** (RF_BeginDestroyed를 GC가 감지)

즉, MarkAsGarbage 직후 해당 UObject의 모든 UPROPERTY 참조가 자동으로 null이 된다.  
raw pointer는 null이 되지 않으므로 dangling pointer가 된다.

---

## IsValid()

```cpp
bool IsValid(const UObject* Test);
```

두 가지를 동시에 검사한다:

```cpp
// 내부 동작 (의사 코드)
bool IsValid(const UObject* Test)
{
    return Test != nullptr && !Test->IsUnreachable() && !Test->IsPendingKillOrUnreachable();
}
```

| 검사 항목 | 의미 |
|-----------|------|
| `!= nullptr` | 포인터 자체가 null인지 |
| `!IsPendingKillOrUnreachable()` | MarkAsGarbage 됐거나 GC가 수거 중인지 |

```cpp
// 올바른 패턴
if (IsValid(MyActor))
{
    MyActor->DoSomething();
}

// 틀린 패턴 — nullptr만 체크, PendingKill 체크 없음
if (MyActor != nullptr)
{
    MyActor->DoSomething();  // MarkAsGarbage 된 객체에도 접근 가능 → 위험
}
```

**액터·컴포넌트 등 게임플레이 코드에서는 항상 `IsValid()`를 쓴다.**

---

## IsValidLowLevel()

```cpp
bool UObject::IsValidLowLevel() const;
```

GC 플래그가 아니라 **메모리 레벨에서 이 객체가 유효한 UObject인지** 검사한다.

```cpp
// 내부 동작 (의사 코드)
bool IsValidLowLevel() const
{
    return GUObjectArray.IsValid(this);  // UObject 글로벌 배열에 이 주소가 있는가
}
```

| 항목 | IsValid | IsValidLowLevel |
|------|---------|-----------------|
| nullptr 체크 | O | O |
| PendingKill 체크 | O | X |
| 메모리 레벨 유효성 | X | O (GUObjectArray 검사) |
| 비용 | 저 | 중 (배열 검색) |
| 용도 | 게임플레이 코드 | 엔진 내부, 직렬화, 에디터 |

**언제 IsValidLowLevel을 쓰는가?**  
완전히 알 수 없는 포인터(외부에서 역직렬화된 포인터 등)가 진짜 UObject를 가리키는지 메모리 레벨에서 확인해야 할 때.  
일반 게임플레이 코드에서 IsValidLowLevel을 써야 한다면 설계를 재고하는 것이 맞다.

---

## 요약 — 무엇을 언제 쓰는가

```
게임플레이에서 Actor/UObject 참조 체크
  → IsValid(Ptr)

엔진 내부, 에디터 코드에서 포인터가 실제 UObject인지 확인
  → Ptr->IsValidLowLevel()

즉시 파괴하고 싶은 UObject (Actor 제외)
  → Ptr->MarkAsGarbage()

즉시 파괴하고 싶은 Actor
  → Actor->Destroy()
```

---

## 내 노트

