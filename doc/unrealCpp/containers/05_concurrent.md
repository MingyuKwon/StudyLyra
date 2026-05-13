# 락-프리 멀티스레드 컨테이너

---

## TLockFreePointerListLIFO\<T\> — 락-프리 스택

포인터 전용 락-프리 LIFO(스택) 컨테이너.  
ABA 문제를 막기 위해 포인터에 태그 비트를 끼워 넣는다.

```cpp
#include "LockFreeList.h"

TLockFreePointerListLIFO<FMyObject, PLATFORM_CACHE_LINE_SIZE> Stack;

// Push — 어느 스레드에서든 안전
FMyObject* Obj = new FMyObject();
Stack.Push(Obj);

// Pop — 어느 스레드에서든 안전
FMyObject* Got = Stack.Pop();   // 비어있으면 nullptr
```

**제약**: 포인터 타입만 다룰 수 있다. 값 타입을 저장하려면 별도 풀에 객체를 두고 포인터를 넣어야 한다.

---

## TLockFreePointerListFIFO\<T, PaddingForCacheContention\> — 락-프리 큐

포인터 전용 락-프리 FIFO(큐).  
`PaddingForCacheContention`은 생산자·소비자의 캐시 라인이 false sharing 없이 분리되도록 하는 패딩 크기다.

```cpp
#include "LockFreeList.h"

TLockFreePointerListFIFO<FMyObject, PLATFORM_CACHE_LINE_SIZE> Queue;

// 생산자 (여러 스레드 가능)
FMyObject* Item = new FMyObject();
Queue.Push(Item);

// 소비자 (여러 스레드 가능)
FMyObject* Got = Queue.Pop();   // 비어있으면 nullptr
```

`TCircularQueue`와 달리 동적 크기이고 MPMC를 지원하지만, 원소마다 노드를 힙 할당한다.

---

## TConsumeAllMpmcQueue\<T\> — 소비자 일괄 처리 큐

Multiple Producer / Multiple Consumer.  
소비자가 한 번에 큐 전체를 가져가는 "swap and consume" 패턴에 특화되어 있다.

```cpp
#include "MpscQueue.h"

TConsumeAllMpmcQueue<FMyData> MpmcQueue;

// 생산자 (여러 스레드)
MpmcQueue.Enqueue(FMyData{ ... });

// 소비자 — 전체를 배열로 꺼냄
TArray<FMyData> Batch;
MpmcQueue.PopAll(Batch);        // 큐 비우고 Batch에 담음

for (FMyData& Data : Batch)
{
    // 처리
}
```

매 프레임 게임 스레드가 여러 워커 스레드가 쌓아 둔 결과를 한 번에 소비할 때 유용하다.

---

## 비교

| | TLockFreePointerListLIFO | TLockFreePointerListFIFO | TConsumeAllMpmcQueue |
|--|--------------------------|--------------------------|----------------------|
| 순서 | LIFO | FIFO | FIFO |
| 생산자 | 여러 스레드 | 여러 스레드 | 여러 스레드 |
| 소비자 | 여러 스레드 | 여러 스레드 | 여러 스레드 |
| 힙 할당 | 원소마다 | 원소마다 | 원소마다 |
| 타입 | 포인터만 | 포인터만 | 값 타입 가능 |
| 주요 용도 | 오브젝트 풀 반환 | 작업 큐 | 프레임별 일괄 소비 |

락-프리 컨테이너는 스레드 간 타이밍이 까다로우므로, 단일 스레드에서 쓸 때는 단순 컨테이너를 사용한다.

---

## 내 노트
