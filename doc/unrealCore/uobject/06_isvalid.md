# MarkAsGarbage / IsValid / IsValidLowLevel

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/UObjectBaseUtility.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Object.h`

---

## MarkAsGarbage

UObject를 **즉시 메모리에서 삭제하지 않고** garbage 상태로 만드는 함수다.

```cpp
MyObj->MarkAsGarbage();
```

호출 직후:
1. garbage 플래그 설정 — 메모리는 아직 있음
2. 다음 GC 사이클에서 수거
3. 이 객체를 가리키는 UPROPERTY 포인터는 **GC 수거 시** 자동으로 null
4. raw pointer는 null이 되지 않음 → dangling pointer

`AActor::Destroy()`도 내부적으로 `MarkAsGarbage()`를 호출한다.

---

## IsValid()

```cpp
bool IsValid(const UObject* Test);
```

null 체크만으로 충분하지 않은 이유는 `Destroy()` 후 GC 수거 전 구간이다.

```cpp
UPROPERTY()
AActor* Target;

Target->Destroy();    // garbage 플래그 세워짐, 메모리는 아직 있음

Target != nullptr     // TRUE  — UPROPERTY auto-null은 GC 수거 시 일어남
IsValid(Target)       // FALSE — garbage 플래그 감지
```

GC 수거 이후는 UPROPERTY가 auto-null되므로 null 체크로 잡힌다.  
잡히지 않는 구간은 **"Destroy됐지만 아직 수거 전"**이다 — IsValid()가 이 구간을 커버한다.

```cpp
IsValid(Obj) = Obj != nullptr
            && !Obj->IsUnreachable()
            && !Obj->IsPendingKillOrUnreachable()  // garbage 플래그 확인
```

---

## 어떤 UObject에 IsValid()가 필요한가

핵심 기준: **명시적으로 Destroy / MarkAsGarbage 될 수 있는가.**

| 타입 | 죽는 방식 | 체크 |
|------|-----------|------|
| AActor | `Destroy()` → garbage 플래그 | `IsValid()` |
| UActorComponent | `DestroyComponent()` → garbage 플래그 | `IsValid()` |
| UDataAsset | 패키지 언로드 → GC 수거 → UPROPERTY auto-null | null 체크로 충분 |
| UGameInstance / UGameState | 게임 종료 → GC 수거 → UPROPERTY auto-null | null 체크로 충분 |

DataAsset 같은 에셋성 오브젝트는 명시적으로 Destroy되지 않는다.  
사라질 때는 GC가 UPROPERTY를 auto-null하므로 null 체크만으로 충분하다.

---

## IsValidLowLevel()

```cpp
bool UObject::IsValidLowLevel() const;
```

### 메모리 유효성 vs 논리적 유효성

`IsValid()`는 **"이 오브젝트가 논리적으로 살아있나"**를 묻는다.  
그 질문에 답하려면 메모리에서 garbage 플래그를 읽어야 한다.

여기서 전제가 하나 있다 — **읽으려는 메모리가 여전히 UObject 구조를 갖고 있어야 한다.**

Destroy됐지만 GC 수거 전인 오브젝트는 이 전제를 만족한다.  
메모리에 UObject가 그대로 있고, garbage 플래그도 거기 있으므로 IsValid()가 안전하게 읽을 수 있다.

```
Destroy 후 GC 수거 전:
  메모리: UObject 구조 그대로  → 플래그 읽기 안전
  garbage 플래그: 세워져 있음
  → IsValid() → false 반환  ✓

GC 수거된 raw pointer:
  메모리: 다른 데이터로 재사용됐을 수 있음  → 플래그 읽기 자체가 위험
  → IsValid() → 쓰레기값 or 크래시  ✗
```

UPROPERTY 포인터는 GC 수거 시 auto-null되므로 이 문제가 생기지 않는다.  
raw pointer는 수거 후에도 주소를 들고 있어서 문제가 생긴다.

### IsValidLowLevel()이 하는 것

플래그를 읽기 전에 **GUObjectArray에 이 주소가 등록되어 있는지 먼저 확인**한다.

```
IsValidLowLevel():
  GUObjectArray에 이 주소가 있는가?
    없으면 → false 반환  (플래그 읽기 전에 걸러냄)
    있으면 → 플래그 체크
```

| 항목 | IsValid | IsValidLowLevel |
|------|---------|-----------------|
| 논리적 유효성 (garbage 플래그) | O | X |
| 메모리 유효성 (GUObjectArray) | 가정함 | O |
| raw pointer 안전성 | X (수거 후 크래시 가능) | O |
| 비용 | 저 | 중 |
| 용도 | 게임플레이 코드 | 엔진 내부, 직렬화, 에디터 |

UPROPERTY를 올바르게 쓰면 raw pointer 문제가 생기지 않으므로  
일반 게임플레이 코드에서 IsValidLowLevel()을 써야 한다면 설계를 재고하는 것이 맞다.

---

## 요약

```
Destroy / MarkAsGarbage될 수 있는 오브젝트 (Actor, Component):
  → IsValid(Ptr)

에셋, GameInstance 등 명시적으로 죽지 않는 오브젝트:
  → Ptr != nullptr

포인터가 실제 UObject 메모리인지 확인해야 할 때 (엔진 내부):
  → Ptr->IsValidLowLevel()

Actor 파괴:   Actor->Destroy()
UObject 파괴: Ptr->MarkAsGarbage()
```

---

## 내 노트
