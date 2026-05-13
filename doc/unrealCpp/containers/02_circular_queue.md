# 원형 버퍼 · 큐

---

## TCircularBuffer\<T\> — 고정 크기 원형 배열

크기가 고정된 원형 배열.

**크기는 반드시 2의 거듭제곱**이어야 한다.  
내부적으로 `IndexMask = Capacity - 1`을 써서 나머지 연산 대신 비트 AND로 인덱스를 wrap한다.

```
(Index + 1) & IndexMask   ←  % Capacity 와 동일, 비트 연산이라 빠름
```

버퍼 자체는 최신/오래된 개념이 없는 **단순 원형 배열**이다.  
write 위치, 유효 원소 수는 **호출자가 직접 관리**해야 한다.

### 제공하는 API

```cpp
Buf[Index]                      // 읽기/쓰기
Buf.GetNextIndex(Index)         // (Index + 1) & IndexMask
Buf.GetPreviousIndex(Index)     // (Index - 1) & IndexMask
Buf.Capacity()                  // 생성 시 지정한 크기
```

### 기본 사용법

```cpp
#include "Containers/CircularBuffer.h"

TCircularBuffer<float> Buf(8);  // 반드시 2의 거듭제곱
uint32 LatestIndex = 0;
uint32 Count = 0;

// 쓰기
void Push(float Val)
{
    if (Count > 0)
        LatestIndex = Buf.GetNextIndex(LatestIndex);
    Buf[LatestIndex] = Val;
    Count = FMath::Min(Count + 1, Buf.Capacity());
}

// 읽기
float Latest  = Buf[LatestIndex];
float OnePrev = Buf[Buf.GetPreviousIndex(LatestIndex)];

// N단계 전
uint32 Idx = LatestIndex;
for (uint32 i = 0; i < N; ++i)
    Idx = Buf.GetPreviousIndex(Idx);
float PrevN = Buf[Idx];
```

가득 찼을 때 새 값을 쓰면 가장 오래된 슬롯을 덮어쓰는데, 이는 버퍼가 판단하는 게 아니라 인덱스가 한 바퀴 돌아서 그 슬롯에 덮어쓰이는 것이다.

### 실전 예시 — Lag Compensation 위치 히스토리

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

버퍼 크기 = 허용 최대 레이턴시 × 서버 틱 레이트. 동적 할당 없이 O(1) 접근.

---

## TCircularQueue\<T\> — Lock-Free SPSC 큐

고정 크기 + **Single Producer / Single Consumer** 전용 락-프리 큐.  
게임 스레드 → 렌더 스레드처럼 생산자·소비자가 각각 하나인 경우에 사용한다.

```cpp
#include "Containers/CircularQueue.h"

TCircularQueue<int32> Queue(64);    // 크기 2의 거듭제곱

// 생산자 스레드
bool bOk = Queue.Enqueue(42);       // 가득 찼으면 false

// 소비자 스레드
int32 Val;
bool bGot = Queue.Dequeue(Val);

Queue.IsEmpty();
Queue.Count();
```

---

## TQueue\<T\> — 동적 스레드 안전 큐

노드 기반 동적 큐. `EQueueMode`로 스레드 안전 모드를 선택한다.

```cpp
#include "Containers/Queue.h"

// MPSC — Multiple Producer, Single Consumer (기본)
TQueue<int32> Queue;
TQueue<int32, EQueueMode::Mpsc> MpscQueue;

// SPSC — Single Producer, Single Consumer (더 빠름)
TQueue<int32, EQueueMode::Spsc> SpscQueue;

// 생산자
Queue.Enqueue(1);
Queue.Enqueue(2);

// 소비자
int32 Val;
Queue.Peek(Val);        // 앞 조회 (제거 안 함)
Queue.Dequeue(Val);     // 앞에서 꺼냄

Queue.IsEmpty();
Queue.Empty();
```

`TCircularQueue`와 달리 동적 크기지만 원소마다 노드를 힙 할당한다.

---

## 비교

| | TCircularBuffer | TCircularQueue | TQueue |
|--|----------------|---------------|--------|
| 크기 | 고정 (2의 거듭제곱) | 고정 (2의 거듭제곱) | 동적 |
| 힙 할당 | X | X | 원소마다 |
| 스레드 안전 | X | SPSC | SPSC / MPSC |
| head/tail 자동 관리 | X (호출자가) | O | O |
| 주요 용도 | 히스토리 버퍼 | 스레드 간 단방향 (고정) | 스레드 간 큐 (동적) |

---

## 내 노트
