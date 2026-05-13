# 유틸리티 타입

---

## TOptional\<T\> — 값이 없을 수 있는 타입

`std::optional`에 대응. 힙 할당 없이 스택에 T를 인라인 저장한다.  
포인터처럼 null 개념이 필요하지만 소유권·할당 비용을 피하고 싶을 때 사용한다.

```cpp
#include "Misc/Optional.h"

TOptional<int32> Find(const TArray<int32>& Arr, int32 Target)
{
    for (int32 V : Arr)
        if (V == Target) return V;
    return {};      // 빈 Optional
}

TOptional<int32> Result = Find(Arr, 42);

if (Result.IsSet())
    int32 Val = Result.GetValue();  // 없을 때 호출 시 assert

int32 Val = Result.Get(0);          // 없으면 기본값 0 반환
```

---

## TVariant\<Types...> — 타입-안전 유니온

`std::variant`에 대응. 나열된 타입 중 하나를 보유한다.

```cpp
#include "Templates/Variant.h"

TVariant<int32, float, FString> Var;

Var.Set<int32>(42);
Var.Set<FString>(TEXT("hello"));

bool bIsStr = Var.IsType<FString>();

FString& S = Var.Get<FString>();    // 타입 불일치 시 assert

// 방문자 패턴
Visit(TOverload{
    [](int32  V) { /* int 처리 */ },
    [](float  V) { /* float 처리 */ },
    [](FString& V) { /* string 처리 */ },
}, Var);
```

---

## TPair\<KeyType, ValueType\> — 키-값 쌍

`std::pair`에 대응. `TMap` 순회 시 반환 타입이기도 하다.

```cpp
#include "Templates/Tuple.h"

TPair<FString, int32> P(TEXT("HP"), 100);
P.Key;
P.Value;

// TMap 순회
TMap<FString, int32> Map;
for (TPair<FString, int32>& Pair : Map)
{
    Pair.Key;
    Pair.Value;
}
```

---

## TTuple\<Types...> — N-원소 튜플

`std::tuple`에 대응. 함수에서 여러 값을 반환할 때 유용하다.

```cpp
#include "Templates/Tuple.h"

TTuple<int32, float, FString> T = MakeTuple(1, 3.14f, TEXT("hi"));

int32   A = T.Get<0>();
float   B = T.Get<1>();
FString C = T.Get<2>();

// 함수 반환 예시
TTuple<bool, FVector> TraceResult(const FVector& Start, const FVector& End)
{
    FHitResult Hit;
    bool bHit = GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Visibility, {});
    return MakeTuple(bHit, Hit.Location);
}

auto [bHit, HitLoc] = TraceResult(Start, End);  // C++17 구조 바인딩
```

---

## TDoubleLinkedList\<T\> — 양방향 연결 리스트

각 노드를 힙 개별 할당. 임의 위치 삽입·삭제가 O(1).  
순차 접근이 주라면 `TArray`가 캐시 효율 면에서 훨씬 낫다.

```cpp
#include "Containers/List.h"

TDoubleLinkedList<int32> List;

List.AddHead(1);
List.AddTail(2);
List.AddTail(3);

TDoubleLinkedList<int32>::TDoubleLinkedListNode* Node = List.GetHead();
while (Node)
{
    int32 Val = Node->GetValue();
    Node = Node->GetNextNode();
}

List.RemoveNode(List.GetHead());    // O(1) 제거

List.Num();
```

임의 노드 포인터를 들고 있으면 해당 위치에서 O(1) 삽입·삭제가 가능하다. 노드 포인터가 없으면 탐색(O(n))이 필요하다.

---

## 비교

| | TOptional | TVariant | TPair | TTuple | TDoubleLinkedList |
|--|-----------|---------|-------|--------|------------------|
| 힙 할당 | X | X | X | X | 노드마다 |
| 크기 | 1개 값 | 1개 (택일) | 2개 | N개 | 동적 |
| 주요 용도 | nullable 값 | 타입 유니온 | 키-값 쌍 | 다중 반환 | O(1) 삽입·삭제 |

---

## 내 노트
