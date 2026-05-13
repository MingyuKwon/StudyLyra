# 연관 컨테이너

---

## TMap\<K, V\> — 해시 맵

`std::unordered_map`에 대응. 순서 없음. 키 하나에 값 하나.

```cpp
TMap<FString, int32> Map;

// 추가
Map.Add(TEXT("HP"), 100);
Map.Emplace(TEXT("MP"), 50);            // 이동 의미론

// 조회
int32* Ptr  = Map.Find(TEXT("HP"));     // 없으면 nullptr
int32& Ref  = Map.FindOrAdd(TEXT("HP")); // 없으면 기본값으로 추가
int32  Val  = Map.FindRef(TEXT("HP"));   // 없으면 기본값(0) 반환
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

Map.Num();
Map.IsEmpty();
Map.Reset();    // 비우기 (메모리 유지)
Map.Empty();    // 비우기 + 메모리 해제
```

---

## TMultiMap\<K, V\> — 같은 키에 여러 값

같은 키에 여러 값을 저장할 수 있다.

```cpp
TMultiMap<FString, int32> MMap;
MMap.Add(TEXT("Tag"), 1);
MMap.Add(TEXT("Tag"), 2);       // 같은 키, 다른 값

TArray<int32> Values;
MMap.MultiFind(TEXT("Tag"), Values);    // [1, 2]
MMap.Num(TEXT("Tag"));                  // 2

MMap.Remove(TEXT("Tag"), 1);            // 특정 값만 제거
MMap.RemoveAll(TEXT("Tag"));            // 해당 키 전부 제거

// 순회
for (auto& Pair : MMap)
{
    Pair.Key; Pair.Value;
}
```

---

## TSet\<T\> — 해시 셋

중복 없는 집합. 순서 없음.

```cpp
TSet<FName> Tags;
Tags.Add(FName("Enemy"));
Tags.Add(FName("Stunned"));
Tags.Add(FName("Enemy"));       // 중복 무시

Tags.Contains(FName("Enemy"));
Tags.Remove(FName("Stunned"));
Tags.Num();

// 집합 연산
TSet<FName> Other = { FName("Enemy"), FName("Boss") };
TSet<FName> Inter = Tags.Intersect(Other);    // 교집합
TSet<FName> Uni   = Tags.Union(Other);        // 합집합
TSet<FName> Diff  = Tags.Difference(Other);   // 차집합

// 순회
for (const FName& Tag : Tags) { }
```

---

## TSortedMap\<K, V\> — 정렬된 맵

순회 시 키 기준 오름차순이 보장된다.  
삽입·삭제마다 정렬을 유지하므로 `TMap`보다 삽입이 느리다.  
조회가 빈번하고 순서가 중요한 경우에 사용한다.

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
SMap.Contains(1);
SMap.Remove(1);
```

---

## 커스텀 KeyFuncs — 해시/비교 방식 변경

`TMap` / `TSet`은 `KeyFuncs` 템플릿 파라미터로 해시 함수와 비교 방식을 바꿀 수 있다.  
기본 타입이 아닌 커스텀 구조체를 키로 쓸 때 필요하다.

```cpp
struct FMyKey
{
    int32 X, Y;
};

struct FMyKeyFuncs : BaseKeyFuncs<TPair<FMyKey, int32>, FMyKey>
{
    static const FMyKey& GetSetKey(const TPair<FMyKey, int32>& Pair)
    {
        return Pair.Key;
    }
    static bool Matches(const FMyKey& A, const FMyKey& B)
    {
        return A.X == B.X && A.Y == B.Y;
    }
    static uint32 GetKeyHash(const FMyKey& Key)
    {
        return HashCombine(GetTypeHash(Key.X), GetTypeHash(Key.Y));
    }
};

TMap<FMyKey, int32, FDefaultSetAllocator, FMyKeyFuncs> CustomMap;
```

---

## 비교

| | TMap | TMultiMap | TSet | TSortedMap |
|--|------|----------|------|-----------|
| 키당 값 수 | 1 | 여러 개 | - | 1 |
| 순서 | 없음 | 없음 | 없음 | 키 오름차순 |
| 삽입 | O(1) avg | O(1) avg | O(1) avg | O(log n) |
| 조회 | O(1) avg | O(1) avg | O(1) avg | O(log n) |
| 주요 용도 | 키-값 저장 | 키에 여러 값 | 중복 없는 집합 | 정렬 순서 필요 |

---

## 내 노트
