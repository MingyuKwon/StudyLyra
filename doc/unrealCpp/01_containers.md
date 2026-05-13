# UE5 컨테이너

> 소스: `Engine/Source/Runtime/Core/Public/Containers/`

---

## TArray\<T\> — 동적 배열

가장 범용적인 컨테이너. `std::vector`에 대응한다.

```cpp
TArray<int32> Arr;

// 추가
Arr.Add(10);
Arr.AddUnique(20);          // 중복이면 무시
Arr.Insert(99, 0);          // 인덱스 0에 삽입 (이후 원소 shift)
Arr.Emplace(30);            // 이동 의미론으로 생성

// 제거
Arr.Remove(10);             // 값으로 제거 (첫 번째 일치, O(n) shift)
Arr.RemoveAt(0);            // 인덱스로 제거 (O(n) shift, 순서 유지)
Arr.RemoveAtSwap(0);        // 인덱스로 제거 + 마지막 원소로 채움 (O(1), 순서 변경)
Arr.RemoveAll([](int32 V) { return V < 0; });  // 조건 제거

// 조회
int32* Ptr = Arr.Find(99);          // 포인터 반환, 없으면 nullptr
int32  Idx = Arr.IndexOfByValue(99);  // 인덱스 반환, 없으면 INDEX_NONE
bool   Has = Arr.Contains(99);

// 정보
Arr.Num();
Arr.IsEmpty();
Arr.IsValidIndex(2);

// 메모리
Arr.Reserve(100);       // 미리 메모리 확보 (재할당 방지)
Arr.Shrink();           // 실제 사용량에 맞게 메모리 축소
Arr.Empty();            // 비우기 (메모리 유지)
Arr.Reset();            // 비우기 (메모리 유지, Empty와 동일)
Arr.Empty(0);           // 비우기 + 메모리 해제

// 정렬
Arr.Sort();
Arr.Sort([](int32 A, int32 B) { return A > B; });   // 내림차순
Arr.StableSort();       // 동일 원소 상대 순서 보존

// 순회
for (int32& V : Arr) { }
for (int32 i = 0; i < Arr.Num(); ++i) { }
```

### TArray를 스택으로 사용

```cpp
TArray<int32> Stack;
Stack.Push(1);          // Add와 동일
Stack.Push(2);
int32 Top = Stack.Top();    // 마지막 원소 참조 (제거 안 함)
int32 Val = Stack.Pop();    // 마지막 원소 제거 후 반환
```

### TArray를 힙(우선순위 큐)으로 사용

```cpp
TArray<int32> Heap;
Heap.HeapPush(5);
Heap.HeapPush(1);
Heap.HeapPush(3);

int32 Min = Heap.HeapTop();     // 최솟값 조회 (제거 안 함)
Heap.HeapPop(Min);              // 최솟값 꺼내기

// 기존 배열을 힙으로 변환
TArray<int32> Arr = { 5, 1, 3 };
Arr.Heapify();
```

기본은 최소 힙. 커스텀 비교자로 최대 힙도 가능하다.

```cpp
// 내림차순 비교자 → 최대 힙
auto Pred = [](int32 A, int32 B) { return A > B; };
Heap.HeapPush(5, Pred);
Heap.HeapPop(Max, Pred);
```

---

## TStaticArray\<T, N\> — 고정 크기 배열

크기가 컴파일 타임에 결정되는 스택 배열. 힙 할당 없음.

```cpp
TStaticArray<int32, 5> Arr;   // 스택에 int32 5개

Arr[0] = 10;
Arr[1] = 20;
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

int32 F = Dq.First();   // 앞 조회
int32 L = Dq.Last();    // 뒤 조회

Dq.PopFirst();      // 앞에서 제거
Dq.PopLast();       // 뒤에서 제거

Dq.Num();
Dq.IsEmpty();
```

---

## TCircularBuffer\<T\> — 고정 크기 원형 배열

크기가 고정된 원형 배열. **크기는 반드시 2의 거듭제곱**이어야 한다.  
내부적으로 `IndexMask = Capacity - 1`을 써서 나머지 연산 대신 비트 AND로 인덱스를 wrap한다.

```
(Index + 1) & IndexMask   ← % Capacity 와 동일, 비트 연산이라 빠름
```

버퍼 자체는 최신/오래된 개념이 없는 **단순 원형 배열**이다.  
write 위치, 유효 원소 수, 최신/오래된 구분은 전부 **호출자가 직접 관리**해야 한다.

```cpp
#include "Containers/CircularBuffer.h"

TCircularBuffer<float> Buf(8);  // 반드시 2의 거듭제곱 (8, 16, 32, 64 ...)
uint32 LatestIndex = 0;
uint32 Count = 0;

// 쓰기
void Push(float Val)
{
    if (Count > 0)
        LatestIndex = Buf.GetNextIndex(LatestIndex);  // (LatestIndex + 1) & IndexMask
    Buf[LatestIndex] = Val;
    Count = FMath::Min(Count + 1, Buf.Capacity());
}

// 읽기
float Latest   = Buf[LatestIndex];
float OnePrev  = Buf[Buf.GetPreviousIndex(LatestIndex)];

// N단계 전 조회
uint32 Idx = LatestIndex;
for (uint32 i = 0; i < N; ++i)
    Idx = Buf.GetPreviousIndex(Idx);
float PrevN = Buf[Idx];
```

### 제공하는 API

```cpp
Buf[Index];                      // 읽기/쓰기
Buf.GetNextIndex(Index);         // (Index + 1) & IndexMask
Buf.GetPreviousIndex(Index);     // (Index - 1) & IndexMask
Buf.Capacity();                  // 생성 시 지정한 크기
```

### 실전 예시 — 위치 히스토리 버퍼 (Lag Compensation)

```cpp
struct FPositionSnapshot
{
    float    Timestamp;
    FVector  Location;
    FRotator Rotation;
};

// 60Hz 서버, 500ms 허용 → 30프레임 → 다음 2의 거듭제곱 = 32
TCircularBuffer<FPositionSnapshot> HistoryBuffer(32);
uint32 LatestIndex = 0;
uint32 Count = 0;

// 매 서버 틱 호출
void RecordSnapshot()
{
    if (Count > 0)
        LatestIndex = HistoryBuffer.GetNextIndex(LatestIndex);

    HistoryBuffer[LatestIndex] = {
        GetWorld()->GetTimeSeconds(),
        GetActorLocation(),
        GetActorRotation()
    };
    Count = FMath::Min(Count + 1, HistoryBuffer.Capacity());
}

// 클라이언트 샷 RPC 수신 — 특정 타임스탬프로 rewind
const FPositionSnapshot* FindSnapshot(float TargetTime) const
{
    uint32 Idx = LatestIndex;
    for (uint32 i = 0; i < Count; ++i)
    {
        if (HistoryBuffer[Idx].Timestamp <= TargetTime)
            return &HistoryBuffer[Idx];
        Idx = HistoryBuffer.GetPreviousIndex(Idx);
    }
    return nullptr;
}
```

---

## TQueue\<T\> — 동적 스레드 안전 큐

노드 기반 동적 큐. `EQueueMode`로 스레드 안전 모드 선택.

```cpp
#include "Containers/Queue.h"

// MPSC (Multiple Producer, Single Consumer) — 기본
TQueue<int32> Queue;
TQueue<int32, EQueueMode::Mpsc> MpscQueue;

// SPSC (Single Producer, Single Consumer) — 더 빠름
TQueue<int32, EQueueMode::Spsc> SpscQueue;

// 생산자
Queue.Enqueue(1);
Queue.Enqueue(2);

// 소비자
int32 Val;
Queue.Peek(Val);        // 앞 조회 (제거 안 함)
Queue.Dequeue(Val);     // 앞에서 꺼냄

Queue.IsEmpty();
Queue.Empty();          // 전부 비우기
```

---

## TCircularQueue\<T\> — Lock-Free SPSC 큐

고정 크기 + Single Producer / Single Consumer 전용 락-프리 큐.  
게임 스레드 → 렌더 스레드처럼 생산자와 소비자가 각각 하나인 경우에 사용한다.

```cpp
#include "Containers/CircularQueue.h"

TCircularQueue<int32> Queue(64);    // 크기 2의 거듭제곱

// 생산자 스레드
bool bOk = Queue.Enqueue(42);   // 가득 찼으면 false

// 소비자 스레드
int32 Val;
bool bGot = Queue.Dequeue(Val);

Queue.IsEmpty();
Queue.Count();
```

`TQueue`(동적 노드 기반)보다 고정 크기지만 할당이 없어서 더 빠르다.

---

## TMap\<K, V\> — 해시 맵

`std::unordered_map`에 대응. 순서 없음.

```cpp
TMap<FString, int32> Map;

// 추가
Map.Add(TEXT("HP"), 100);
Map.Emplace(TEXT("MP"), 50);        // 이동 의미론

// 조회
int32* Ptr  = Map.Find(TEXT("HP"));         // 없으면 nullptr
int32& Ref  = Map.FindOrAdd(TEXT("HP"));    // 없으면 기본값으로 추가
int32  Val  = Map.FindRef(TEXT("HP"));      // 없으면 기본값(0) 반환
bool   Has  = Map.Contains(TEXT("HP"));

// 제거
Map.Remove(TEXT("MP"));

// 순회 (순서 보장 없음)
for (auto& Pair : Map)
{
    Pair.Key;
    Pair.Value;
}

// 키/값 배열로 추출
TArray<FString> Keys;
TArray<int32>   Vals;
Map.GetKeys(Keys);
Map.GenerateValueArray(Vals);
```

---

## TMultiMap\<K, V\> — 같은 키에 여러 값

```cpp
TMultiMap<FString, int32> MMap;
MMap.Add(TEXT("Tag"), 1);
MMap.Add(TEXT("Tag"), 2);   // 같은 키, 다른 값

TArray<int32> Values;
MMap.MultiFind(TEXT("Tag"), Values);   // [1, 2]
MMap.Num(TEXT("Tag"));                 // 2
MMap.Remove(TEXT("Tag"), 1);           // 특정 값만 제거
MMap.RemoveAll(TEXT("Tag"));           // 해당 키 전부 제거
```

---

## TSet\<T\> — 해시 셋

중복 없는 집합. 순서 없음.

```cpp
TSet<FName> Tags;
Tags.Add(FName("Enemy"));
Tags.Add(FName("Stunned"));
Tags.Add(FName("Enemy"));    // 중복 무시

Tags.Contains(FName("Enemy"));
Tags.Remove(FName("Stunned"));
Tags.Num();

// 집합 연산
TSet<FName> Other = { FName("Enemy"), FName("Boss") };
TSet<FName> Inter = Tags.Intersect(Other);   // 교집합
TSet<FName> Uni   = Tags.Union(Other);       // 합집합
TSet<FName> Diff  = Tags.Difference(Other);  // 차집합

// 순회
for (const FName& Tag : Tags) { }
```

---

## TSortedMap\<K, V\> — 정렬된 맵

순회 시 키 기준 오름차순이 보장된다.  
삽입·삭제 시 정렬 유지 비용이 있으므로 조회가 빈번하고 삽입이 적을 때 적합하다.

```cpp
#include "Containers/SortedMap.h"

TSortedMap<int32, FString> SMap;
SMap.Add(3, TEXT("C"));
SMap.Add(1, TEXT("A"));
SMap.Add(2, TEXT("B"));

// 순회 시 항상 키 오름차순 (1→2→3)
for (auto& Pair : SMap)
{
    Pair.Key; Pair.Value;
}

SMap.Find(2);
SMap.Remove(1);
```

---

## TSparseArray\<T\> — 안정 인덱스 배열

원소를 제거해도 인덱스가 재배치되지 않는다. 빈 슬롯(hole)이 생기지만 외부에서 가지고 있는 인덱스가 무효화되지 않는다.  
빈번한 삽입·삭제 + 외부에서 인덱스로 참조하는 구조에 적합하다.

```cpp
TSparseArray<FString> SArr;

int32 Idx0 = SArr.Add(TEXT("A"));   // 0
int32 Idx1 = SArr.Add(TEXT("B"));   // 1
int32 Idx2 = SArr.Add(TEXT("C"));   // 2

SArr.RemoveAt(1);   // "B" 제거, 인덱스 1은 hole

int32 Idx3 = SArr.Add(TEXT("D"));   // hole인 1번 슬롯 재사용

SArr.IsValidIndex(1);   // true (인덱스 범위 내)
SArr.IsAllocated(1);    // true (hole 아닌 유효 원소)

// 유효 원소만 순회 (hole 자동 건너뜀)
for (const FString& S : SArr) { }
```

---

## TBitArray — 비트 배열

각 원소가 1비트. 메모리 효율적인 bool 배열.

```cpp
TBitArray<> Bits(false, 64);   // 64비트, 초기값 false

Bits[0] = true;
Bits[10] = true;

bool Val = Bits[0];

Bits.SetRange(0, 8, true);      // 인덱스 0~7 일괄 설정
int32 SetCount = Bits.CountSetBits();

// AND / OR / XOR 연산
TBitArray<> Other(false, 64);
TBitArray<> Result = TBitArray<>::BitwiseAND(Bits, Other, EBitwiseOperatorFlags::MaxSize);
```

---

## TInlineAllocator — 힙 할당 줄이기

`TArray`에 인라인 버퍼를 붙여 작은 크기에서 힙 할당을 없앤다.

```cpp
// N개 이하면 힙 없이 인라인, 초과 시 힙으로 자동 이동
TArray<int32, TInlineAllocator<4>> SmallArr;
SmallArr.Add(1);   // 힙 없음
SmallArr.Add(2);
SmallArr.Add(3);
SmallArr.Add(4);
SmallArr.Add(5);   // 5번째 — 힙으로 이동

// 고정 크기 — 초과 시 assert (절대 힙 안 씀)
TArray<int32, TFixedAllocator<4>> FixedArr;
```

Delegate의 `InlineStorage` 16바이트도 같은 원리다.

---

## TDoubleLinkedList\<T\> — 양방향 연결 리스트

임의 위치 삽입·삭제가 O(1). 단, 캐시 비효율적이라 일반적으로는 `TArray`를 선호한다.

```cpp
TDoubleLinkedList<int32> List;

List.AddHead(1);
List.AddTail(2);
List.AddTail(3);

// 순회
auto* Node = List.GetHead();
while (Node)
{
    int32 Val = Node->GetValue();
    Node = Node->GetNextNode();
}

// 특정 노드 앞뒤에 삽입
auto* Head = List.GetHead();
List.InsertNode(new TDoubleLinkedList<int32>::TDoubleLinkedListNode(99), Head);

// 제거
List.RemoveNode(List.GetHead());
List.Num();
```

---

## TOptional\<T\> — 있을 수도 없을 수도 있는 값

`std::optional`에 대응.

```cpp
#include "Misc/Optional.h"

TOptional<float> FindHealth(AActor* Actor)
{
    if (!Actor) return {};              // 없음
    return Actor->GetHealth();          // 있음
}

TOptional<float> HP = FindHealth(SomeActor);
if (HP.IsSet())
    float Val = HP.GetValue();

float Safe = HP.Get(0.f);   // 없으면 0.f 반환
```

---

## TVariant\<Types...\> — 타입 안전 공용체

`std::variant`에 대응. 여러 타입 중 하나를 저장한다.

```cpp
#include "Misc/Variant.h"

TVariant<int32, float, FString> Var;

Var.Set<int32>(42);
if (Var.IsType<int32>())
    int32 Val = Var.Get<int32>();

Var.Set<FString>(TEXT("Hello"));
FString& Str = Var.Get<FString>();
```

---

## TPair\<A, B\> / TTuple\<...\>

```cpp
// TPair
TPair<FString, int32> Pair(TEXT("Score"), 100);
Pair.Key;    // "Score"
Pair.Value;  // 100

// TTuple
TTuple<int32, float, FString> Tuple(1, 2.5f, TEXT("Hi"));
Tuple.Get<0>();   // 1
Tuple.Get<1>();   // 2.5f
Tuple.Get<2>();   // "Hi"
```

---

## 용도별 선택 가이드

| 상황 | 선택 |
|------|------|
| 범용 순차 컨테이너 | `TArray` |
| 컴파일 타임 고정 크기 배열 | `TStaticArray` |
| 앞/뒤 삽입·삭제 O(1) | `TDeque` |
| 고정 크기 히스토리 버퍼 | `TCircularBuffer` |
| 스레드 간 단방향 (SPSC, 고정 크기) | `TCircularQueue` |
| 스레드 간 단방향 (동적 크기) | `TQueue<T, EQueueMode::Spsc>` |
| 키-값 저장, 순서 무관 | `TMap` |
| 같은 키에 여러 값 | `TMultiMap` |
| 중복 없는 집합 | `TSet` |
| 키 정렬 순서 필요 | `TSortedMap` |
| 빈번한 삽입·삭제, 외부 인덱스 참조 | `TSparseArray` |
| 메모리 효율적인 bool 집합 | `TBitArray` |
| 작은 배열에서 힙 할당 제거 | `TArray<T, TInlineAllocator<N>>` |
| 있을 수도 없을 수도 있는 값 | `TOptional` |
| 여러 타입 중 하나 | `TVariant` |

---

## 내 노트
