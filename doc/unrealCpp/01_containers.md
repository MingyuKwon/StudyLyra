# 컨테이너 — TArray · TDeque · TCircularBuffer · TCircularQueue

> 소스:  
> `Engine/Source/Runtime/Core/Public/Containers/Array.h`  
> `Engine/Source/Runtime/Core/Public/Containers/Deque.h`  
> `Engine/Source/Runtime/Core/Public/Containers/CircularBuffer.h`  
> `Engine/Source/Runtime/Core/Public/Containers/CircularQueue.h`

---

## TArray로 deque를 흉내내면 안 되는 이유

`TArray`는 동적 배열이라 뒤에 추가하는 건 O(1)이지만, 앞에서 제거하면 전체 원소를 한 칸씩 당겨야 해서 O(n)이다.

```cpp
TArray<int32> Arr;
Arr.Add(1);         // O(1) — 뒤에 추가
Arr.RemoveAt(0);    // O(n) — 전체 shift 발생
```

매 틱 add/remove가 일어나는 히스토리 버퍼나 큐 구조에 쓰면 프레임마다 O(n) 비용이 누적된다.

---

## TDeque — 진짜 deque (UE5.1+)

> `Engine/Source/Runtime/Core/Public/Containers/Deque.h`

앞·뒤 삽입·삭제가 모두 O(1). 동적 크기.

```cpp
#include "Containers/Deque.h"

TDeque<int32> Dq;

// 추가
Dq.PushLast(10);    // 뒤에 추가
Dq.PushFirst(5);    // 앞에 추가

// 제거
Dq.PopFirst();      // 앞에서 제거
Dq.PopLast();       // 뒤에서 제거

// 조회
Dq.First();         // 앞 원소
Dq.Last();          // 뒤 원소
Dq.Num();           // 크기
```

크기가 가변적이어야 하거나, 양방향 접근이 필요한 경우에 사용한다.

---

## TCircularBuffer — 고정 크기 원형 버퍼

> `Engine/Source/Runtime/Core/Public/Containers/CircularBuffer.h`

크기가 고정된 원형 배열. 가득 찼을 때 새 원소를 추가하면 가장 오래된 것부터 자동으로 덮어쓴다.  
동적 할당이 없고 인덱스 접근이 O(1)이라 **히스토리 버퍼에 최적**이다.

### 구조

```
버퍼 크기 = 5, 현재 인덱스 = 2

Index:  0    1    2    3    4
      [f3] [f4] [f5] [f1] [f2]   ← f5가 최신, f1이 가장 오래됨
                ↑
           LatestIndex
```

인덱스가 원형으로 돌면서 오래된 슬롯을 덮어쓴다. 앞에서 빼는 연산 자체가 없다.

### 사용법

```cpp
#include "Containers/CircularBuffer.h"

TCircularBuffer<float> Buffer(8);   // 크기 8로 고정

uint32 Idx = 0;

// 추가
uint32 Next = Buffer.GetNextIndex(Idx);
Buffer[Next] = 3.14f;
Idx = Next;

// 조회
float Val = Buffer[Idx];

// 이전 원소 (한 단계 전)
float Prev = Buffer[Buffer.GetPreviousIndex(Idx)];

// 크기
Buffer.Capacity();   // 항상 생성 시 지정한 값 (8)
```

### 히스토리 버퍼 실전 예시 — Lag Compensation용 위치 기록

서버 사이드 리와인드를 구현할 때 캐릭터의 과거 위치를 일정 시간만큼 기록해두는 용도다.

```cpp
// 스냅샷 구조체
struct FPositionSnapshot
{
    float  Timestamp;
    FVector  Location;
    FRotator Rotation;
};

// 틱 60Hz 기준 500ms = 30프레임
static constexpr uint32 HistorySize = 30;

TCircularBuffer<FPositionSnapshot> HistoryBuffer(HistorySize);
uint32 LatestIndex = 0;

// 매 틱 호출
void RecordSnapshot()
{
    uint32 Next = HistoryBuffer.GetNextIndex(LatestIndex);
    HistoryBuffer[Next] = {
        GetWorld()->GetTimeSeconds(),
        GetActorLocation(),
        GetActorRotation()
    };
    LatestIndex = Next;
}

// 클라이언트 RPC 수신 시 — 특정 시점으로 rewind
const FPositionSnapshot* FindSnapshotAtTime(float TargetTime) const
{
    uint32 Idx = LatestIndex;
    for (uint32 i = 0; i < HistorySize; ++i)
    {
        const FPositionSnapshot& Snap = HistoryBuffer[Idx];
        if (Snap.Timestamp <= TargetTime)
            return &Snap;

        Idx = HistoryBuffer.GetPreviousIndex(Idx);
    }
    return nullptr;
}
```

버퍼 크기 = 허용할 최대 레이턴시 × 서버 틱 레이트.  
500ms 허용, 60Hz 서버 → 크기 30.

---

## TCircularQueue — 스레드 안전 SPSC 큐

> `Engine/Source/Runtime/Core/Public/Containers/CircularQueue.h`

Single Producer / Single Consumer 전용 락-프리 원형 큐.  
게임 스레드 → 렌더 스레드처럼 **생산자와 소비자가 각각 하나**인 경우에만 안전하다.

```cpp
#include "Containers/CircularQueue.h"

TCircularQueue<int32> Queue(64);   // 크기 64

// 생산자 스레드
Queue.Enqueue(42);

// 소비자 스레드
int32 Val;
if (Queue.Dequeue(Val))
{
    // Val 사용
}
```

멀티 스레드 환경에서 `TArray` + Mutex 대신 쓸 수 있지만, SPSC 제약을 지켜야 한다.

---

## 용도별 선택 가이드

| 상황 | 선택 |
|------|------|
| 앞/뒤 삽입·삭제, 동적 크기 | `TDeque` |
| 고정 크기 히스토리 버퍼 (최신 N개만 유지) | `TCircularBuffer` |
| 스레드 간 단방향 데이터 전달 (SPSC) | `TCircularQueue` |
| 뒤에만 추가, 앞 제거 없음 | `TArray` |
| 앞에서 제거 필요한데 `TDeque` 없는 버전 | `TArray` + `int32 HeadIndex` 수동 관리 |

---

## 내 노트
