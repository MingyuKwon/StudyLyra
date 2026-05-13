# 특수 배열

---

## TChunkedArray\<T\> — 재할당 없는 대용량 배열

`TArray`는 커질 때 통째로 새 메모리를 할당하고 기존 데이터를 전부 복사한다.  
원소 수가 수만 개면 재할당 한 번에 O(n) 복사 비용이 발생한다.

`TChunkedArray`는 메모리를 고정 크기 **청크 단위**로 나눠 들고 있어서 재할당 없이 늘어난다.  
기존 원소의 주소도 바뀌지 않는다.

```
TArray:
  [1][2][3][4][5] → 재할당 → [1][2][3][4][5][6][7][8]  (전체 복사)

TChunkedArray:
  청크0: [1][2][3][4]
  청크1: [5][6][7][8]   ← 새 청크 추가, 기존 청크 그대로
```

```cpp
#include "Containers/ChunkedArray.h"

TChunkedArray<FMyStruct> BigArray;          // 기본 청크 = 16KB
TChunkedArray<FMyStruct, 4096> SmallChunk;  // 청크 크기 4KB로 지정

BigArray.AddElement(MyStruct);

BigArray.Num();
BigArray[0];

for (FMyStruct& S : BigArray) { }
```

**단점**: 메모리가 연속적이지 않아 캐시 효율이 `TArray`보다 떨어진다.  
연속 접근이 빈번하면 `TArray`가 낫고, 삽입이 빈번하고 크기가 예측 불가면 `TChunkedArray`가 낫다.

---

## TIndirectArray\<T\> — 포인터 안정성 보장 배열

원소 각각을 **힙에 개별 할당**한다.  
배열이 커져서 내부 버퍼가 재할당돼도 기존 원소의 메모리 주소가 바뀌지 않는다.

```
TArray:
  버퍼 재할당 → 모든 원소 새 주소로 이동 → 외부 포인터 무효화

TIndirectArray:
  버퍼에는 포인터만 있음 → 재할당해도 포인터 값은 그대로 → 외부 포인터 유효
```

```cpp
#include "Containers/IndirectArray.h"

TIndirectArray<FMyObject> Arr;

Arr.Add(new FMyObject());           // 소유권 이전
FMyObject* Ptr = Arr[0];            // 배열이 커져도 Ptr 유효

Arr.Add(new FMyObject());
Arr.Add(new FMyObject());

// 소멸 시 각 원소 자동 delete
Arr.RemoveAt(0);                    // delete 호출 후 제거
Arr.Empty();                        // 전부 delete

Arr.Num();
for (FMyObject* Obj : Arr) { }
```

`TArray<TUniquePtr<T>>`와 역할은 비슷하지만 더 UE 스타일이다.

---

## TSparseArray\<T\> — 안정 인덱스 배열

원소를 제거해도 인덱스가 재배치되지 않는다.  
제거된 자리는 빈 슬롯(hole)으로 남고, 다음 삽입 시 hole이 재사용된다.

외부에서 인덱스를 오래 들고 있어야 하면서 빈번한 삽입·삭제가 있을 때 적합하다.

```
TArray:  [A][B][C] → RemoveAt(1) → [A][C]       (인덱스 재배치)
TSparse: [A][B][C] → RemoveAt(1) → [A][_][C]    (hole, 인덱스 그대로)
```

```cpp
TSparseArray<FString> SArr;

int32 Idx0 = SArr.Add(TEXT("A"));   // 0
int32 Idx1 = SArr.Add(TEXT("B"));   // 1
int32 Idx2 = SArr.Add(TEXT("C"));   // 2

SArr.RemoveAt(1);                   // hole 발생, Idx2는 여전히 2

int32 Idx3 = SArr.Add(TEXT("D"));   // hole인 1번 슬롯 재사용 → Idx3 = 1

// 유효성 확인
SArr.IsValidIndex(1);   // true (범위 내)
SArr.IsAllocated(1);    // true (hole 아닌 유효 원소)
SArr.IsAllocated(0);

// 유효 원소만 순회 (hole 자동 건너뜀)
for (const FString& S : SArr) { }
```

---

## TBitArray — 비트 배열

각 원소가 1비트. 메모리 효율적인 bool 배열.  
`TArray<bool>`과 달리 실제로 비트 단위로 저장한다.

```cpp
TBitArray<> Bits(false, 64);        // 64비트, 초기값 false

Bits[0] = true;
Bits[10] = true;

bool Val = Bits[0];

Bits.SetRange(0, 8, true);          // 인덱스 0~7 일괄 설정
int32 SetCount = Bits.CountSetBits();
Bits.Num();

// 비트 연산
TBitArray<> Other(false, 64);
Other[0] = true;
TBitArray<> Result = TBitArray<>::BitwiseAND(Bits, Other, EBitwiseOperatorFlags::MaxSize);
```

---

## TInlineAllocator\<N\> — 힙 할당 줄이기

`TArray`에 인라인 버퍼를 붙여 원소 수가 N개 이하일 때 힙 할당을 없앤다.  
N개를 초과하면 자동으로 힙으로 이동한다.

```cpp
// N개 이하면 힙 없이 인라인, 초과 시 힙으로 자동 이동
TArray<int32, TInlineAllocator<4>> SmallArr;
SmallArr.Add(1);    // 힙 없음
SmallArr.Add(2);
SmallArr.Add(3);
SmallArr.Add(4);
SmallArr.Add(5);    // 5번째 — 힙으로 이동

// 고정 크기 — 초과 시 assert (절대 힙 안 씀)
TArray<int32, TFixedAllocator<4>> FixedArr;
```

Delegate의 `InlineStorage` 16바이트도 같은 원리다.  
크기가 거의 고정된 소형 배열에서 malloc 비용을 없앨 때 유용하다.

---

## 비교

| | TArray | TChunkedArray | TIndirectArray | TSparseArray |
|--|--------|--------------|---------------|-------------|
| 메모리 | 연속 | 청크 단위 연속 | 원소별 개별 | 연속 (hole 포함) |
| 재할당 시 복사 | O(n) | 없음 | 없음 | O(n) |
| 포인터 안정성 | X | O (청크 내) | O | O |
| 인덱스 안정성 | X | X | X | O |
| 캐시 효율 | 높음 | 중간 | 낮음 | 중간 |
| 주요 용도 | 범용 | 대용량 동적 배열 | 포인터 참조 많을 때 | 외부 인덱스 참조 |

---

## 내 노트
