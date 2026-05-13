# 순차 컨테이너

---

## TArray\<T\> — 동적 배열

가장 범용적인 컨테이너. `std::vector`에 대응한다.  
내부는 힙에 연속 할당된 메모리 블록이다.

```cpp
TArray<int32> Arr;

// 추가
Arr.Add(10);
Arr.AddUnique(20);                              // 중복이면 무시
Arr.Insert(99, 0);                              // 인덱스 0에 삽입 (이후 원소 shift)
Arr.Emplace(30);                                // 이동 의미론으로 생성

// 제거
Arr.Remove(10);                                 // 값으로 제거 (첫 번째 일치, O(n) shift)
Arr.RemoveAt(0);                                // 인덱스로 제거 (O(n) shift, 순서 유지)
Arr.RemoveAtSwap(0);                            // 인덱스로 제거 + 마지막 원소로 채움 (O(1), 순서 변경)
Arr.RemoveAll([](int32 V) { return V < 0; });   // 조건 제거

// 조회
int32* Ptr = Arr.Find(99);                      // 포인터 반환, 없으면 nullptr
int32  Idx = Arr.IndexOfByValue(99);            // 인덱스 반환, 없으면 INDEX_NONE
bool   Has = Arr.Contains(99);

// 정보
Arr.Num();
Arr.IsEmpty();
Arr.IsValidIndex(2);

// 메모리
Arr.Reserve(100);       // 미리 메모리 확보 (재할당 방지)
Arr.Shrink();           // 실제 사용량에 맞게 메모리 축소
Arr.Empty();            // 비우기 (메모리 유지)
Arr.Empty(0);           // 비우기 + 메모리 해제

// 정렬
Arr.Sort();
Arr.Sort([](int32 A, int32 B) { return A > B; });
Arr.StableSort();       // 동일 원소 상대 순서 보존

// 순회
for (int32& V : Arr) { }
for (int32 i = 0; i < Arr.Num(); ++i) { }
```

### TArray를 스택으로

```cpp
TArray<int32> Stack;
Stack.Push(1);
Stack.Push(2);
int32 Top = Stack.Top();    // 마지막 원소 참조 (제거 안 함)
int32 Val = Stack.Pop();    // 마지막 원소 제거 후 반환
```

### TArray를 힙(우선순위 큐)으로

기본은 최소 힙.

```cpp
TArray<int32> Heap;
Heap.HeapPush(5);
Heap.HeapPush(1);
Heap.HeapPush(3);

int32 Min = Heap.HeapTop();     // 최솟값 조회
Heap.HeapPop(Min);              // 최솟값 꺼내기

// 기존 배열을 힙으로 변환
TArray<int32> Arr = { 5, 1, 3 };
Arr.Heapify();

// 커스텀 비교자 — 최대 힙
auto MaxPred = [](int32 A, int32 B) { return A > B; };
Heap.HeapPush(5, MaxPred);
Heap.HeapPop(Max, MaxPred);
```

---

## TStaticArray\<T, N\> — 고정 크기 배열

크기가 컴파일 타임에 결정되는 스택 배열. 힙 할당 없음.

```cpp
TStaticArray<int32, 5> Arr;
Arr[0] = 10;
Arr.Num();   // 항상 5
```

---

## TDeque\<T\> — 양방향 큐 (UE5.1+)

앞·뒤 삽입·삭제가 모두 O(1). 동적 크기.

```cpp
#include "Containers/Deque.h"

TDeque<int32> Dq;

Dq.PushFirst(1);    // 앞에 추가
Dq.PushLast(2);     // 뒤에 추가

Dq.First();         // 앞 조회
Dq.Last();          // 뒤 조회

Dq.PopFirst();      // 앞에서 제거
Dq.PopLast();       // 뒤에서 제거

Dq.Num();
Dq.IsEmpty();
```

---

## TArrayView\<T\> / TConstArrayView\<T\> — 비소유 슬라이스

`std::span`에 대응한다. 포인터 + 크기만 들고 있으며 **메모리를 소유하지 않는다.**  
함수 파라미터로 쓰면 `TArray`, `TStaticArray`, C 배열 등 어떤 배열 타입이든 복사 없이 받을 수 있다.

```cpp
// TArray, C배열, TStaticArray 모두 받을 수 있음
void Process(TConstArrayView<int32> Data)
{
    for (int32 V : Data) { }
    Data.Num();
    Data[0];
    Data.IsEmpty();
}

TArray<int32>        Arr  = { 1, 2, 3 };
TStaticArray<int32,3> SArr;
int32                 CArr[] = { 4, 5, 6 };

Process(Arr);
Process(SArr);
Process(MakeArrayView(CArr, 3));

// 슬라이싱
TConstArrayView<int32> Slice = TConstArrayView<int32>(Arr).Slice(1, 2);  // [2, 3]
```

UE5 엔진 내부 API에서 배열 파라미터 대부분이 `TConstArrayView`로 바뀌고 있다.

> **주의**: 원본 배열이 소멸하거나 재할당되면 View가 dangling pointer가 된다.  
> View는 원본보다 오래 살아남으면 안 된다.

---

## 비교

| | TArray | TStaticArray | TDeque | TArrayView |
|--|--------|-------------|--------|-----------|
| 크기 | 동적 | 고정 (컴파일 타임) | 동적 | 비소유 |
| 힙 할당 | O | X | O | X |
| 앞 삽입·삭제 | O(n) | X | O(1) | X |
| 뒤 삽입·삭제 | O(1) | X | O(1) | X |
| 주요 용도 | 범용 배열 | 소형 고정 배열 | 양방향 큐 | 함수 파라미터 |

---

## 내 노트
