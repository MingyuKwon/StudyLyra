# FFastArraySerializer — 배열 델타 직렬화

> 소스:  
> `Engine/Source/Runtime/Engine/Public/GameFramework/FastArraySerializer.h`  
> `Engine/Source/Runtime/Engine/Private/GameFramework/FastArraySerializer.cpp`  
> `Engine/Source/Runtime/GameplayAbilities/Private/GameplayTagStack.cpp`

배열을 통째로 보내지 않고, **바뀐 항목만** 보내는 델타 직렬화 시스템.
UPROPERTY 자동 복제는 배열을 전체 비교하지만, `FFastArraySerializer`는 항목별 변경 추적으로 훨씬 효율적이다.

---

## 왜 필요한가

UPROPERTY TArray를 그냥 복제하면:
- 배열 전체를 매 틱 비교 (Shadow Buffer)
- 항목 하나가 바뀌어도 변경 여부만 알 뿐, **어느 항목이 바뀌었는지** 모름
- 항목이 많아지면 전송량 증가 (기본 배열 복제는 변경된 배열 전체를 보냄)

`FFastArraySerializer`는 각 항목에 **ID와 버전 키**를 부여해 항목 단위로 추적한다.

---

## 기본 구조

```cpp
// FastArraySerializer.h

// 배열 항목 기반 구조체
struct FFastArraySerializerItem
{
    int32 ReplicationID  = INDEX_NONE;  // 이 항목의 안정적 네트워크 ID (서버가 배정)
    int32 ReplicationKey = INDEX_NONE;  // 항목이 변경될 때마다 증가하는 버전 키
    int32 MostRecentArrayReplicationKey = INDEX_NONE;  // 내부용
};

// 배열 컨테이너 기반 구조체
struct FFastArraySerializer
{
    int32 ArrayReplicationKey = INDEX_NONE;  // 배열 전체의 버전 (항목 추가/제거 시 증가)

    // 항목 추가/제거 시 내부에서 호출
    void MarkItemDirty(FFastArraySerializerItem& Item);  // 이 항목이 바뀌었음을 표시
    void MarkArrayDirty();  // 배열 전체 변경 표시 (항목 추가/제거)
};
```

---

## 사용 패턴 — FGameplayTagStackContainer 예시

```cpp
// GameplayTagStack.h

// 1. 항목 구조체: FFastArraySerializerItem 상속
struct FGameplayTagStack : public FFastArraySerializerItem
{
    FGameplayTag Tag;
    int32 StackCount = 0;
};

// 2. 컨테이너: FFastArraySerializer 상속
struct FGameplayTagStackContainer : public FFastArraySerializer
{
    // 콜백 선언
    void PreReplicatedRemove(const TArrayView<int32> RemovedIndices, int32 FinalSize);
    void PostReplicatedAdd(const TArrayView<int32> AddedIndices, int32 FinalSize);
    void PostReplicatedChange(const TArrayView<int32> ChangedIndices, int32 FinalSize);

    // NetDeltaSerialize 필수 — 이 함수가 실제 델타 직렬화를 호출
    bool NetDeltaSerialize(FNetDeltaSerializeInfo& DeltaParms)
    {
        return FFastArraySerializer::FastArrayDeltaSerialize<
            FGameplayTagStack,
            FGameplayTagStackContainer
        >(Stacks, DeltaParms, *this);
    }

private:
    UPROPERTY()
    TArray<FGameplayTagStack> Stacks;        // 복제됨 — 실제 데이터

    TMap<FGameplayTag, int32> TagToCountMap; // 복제 안 됨 — 로컬 캐시
};

// 3. TStructOpsTypeTraits 등록
template<>
struct TStructOpsTypeTraits<FGameplayTagStackContainer>
{
    enum { WithNetDeltaSerializer = true };
};
```

---

## 델타 직렬화 알고리즘

`FastArrayDeltaSerialize`가 서버에서 호출될 때:

```
[서버 — 직렬화]

1. 이전에 클라이언트에게 보낸 ArrayReplicationKey 확인
   (클라이언트별 상태를 FReplicationRecord에 저장)

2. 항목 순회:
   ├─ 새 항목 (ReplicationID == INDEX_NONE)
   │    → 새 ReplicationID 배정 → "추가" 목록에 넣기
   ├─ 기존 항목 (ReplicationKey가 마지막 전송 후 바뀜)
   │    → "변경" 목록에 넣기
   └─ 이전에 있었는데 지금 없는 항목
        → "제거" 목록에 넣기

3. FBitWriter에 기록:
   ├─ 제거된 항목들의 ReplicationID 목록
   ├─ 추가/변경된 항목들 (ID + 직렬화된 값)
   └─ 새 ArrayReplicationKey

[클라이언트 — 역직렬화]

1. FBitReader에서 읽기
2. 제거 목록 처리 → PreReplicatedRemove 콜백
3. 추가/변경 항목 적용
4. PostReplicatedAdd / PostReplicatedChange 콜백
```

---

## Pre/PostReplicated 콜백 — TMap 재건

콜백의 역할은 `Stacks` 배열과 `TagToCountMap`을 동기화하는 것이다.

```cpp
// GameplayTagStack.cpp

void FGameplayTagStackContainer::PreReplicatedRemove(
    const TArrayView<int32> RemovedIndices, int32 FinalSize)
{
    for (int32 Index : RemovedIndices)
    {
        const FGameplayTagStack& Stack = Stacks[Index];
        TagToCountMap.Remove(Stack.Tag);  // 제거될 항목을 TMap에서 삭제
    }
}

void FGameplayTagStackContainer::PostReplicatedAdd(
    const TArrayView<int32> AddedIndices, int32 FinalSize)
{
    for (int32 Index : AddedIndices)
    {
        const FGameplayTagStack& Stack = Stacks[Index];
        TagToCountMap.Add(Stack.Tag, Stack.StackCount);  // 새 항목을 TMap에 추가
    }
}

void FGameplayTagStackContainer::PostReplicatedChange(
    const TArrayView<int32> ChangedIndices, int32 FinalSize)
{
    for (int32 Index : ChangedIndices)
    {
        const FGameplayTagStack& Stack = Stacks[Index];
        TagToCountMap[Stack.Tag] = Stack.StackCount;  // 변경된 항목의 카운트 갱신
    }
}
```

콜백 순서:
1. `PreReplicatedRemove` — 아직 Stacks에 항목이 있을 때 호출 (제거 전 마지막 기회)
2. 엔진이 Stacks에서 항목 실제 제거
3. `PostReplicatedAdd` — Stacks에 새 항목이 이미 추가된 후 호출
4. `PostReplicatedChange` — Stacks의 값이 이미 갱신된 후 호출

`Pre`는 "제거되기 전에", `Post`는 "적용된 후에"라는 이름 그대로다.

---

## MarkItemDirty — 항목 변경 알림

서버에서 항목 값을 바꿨을 때 `MarkItemDirty`를 호출해야 한다.
호출하지 않으면 `ReplicationKey`가 바뀌지 않아 변경이 감지되지 않는다.

```cpp
void FGameplayTagStackContainer::AddStack(FGameplayTag Tag, int32 StackCount)
{
    // ... Stacks 배열에서 찾아서 StackCount 증가 ...

    FGameplayTagStack& Stack = Stacks[ExistingIndex];
    Stack.StackCount += StackCount;
    TagToCountMap[Tag] = Stack.StackCount;

    MarkItemDirty(Stack);  // ← 필수 — ReplicationKey 증가
}
```

항목 추가/제거는 `MarkArrayDirty()`도 함께 호출해 `ArrayReplicationKey`를 올린다.

---

## TMap은 왜 UPROPERTY가 없나

```cpp
TMap<FGameplayTag, int32> TagToCountMap;  // UPROPERTY 없음
```

`UPROPERTY`가 없으면 리플렉션 시스템이 이 필드를 모른다.
복제 파이프라인에서 완전히 투명한 존재다.

- 복제 안 됨 — 네트워크로 전송되지 않음
- 직렬화 안 됨 — 저장/로딩에도 관여하지 않음
- GC 추적 안 됨 — UObject 포인터가 아니라 값 타입이므로 문제없음

의도: TMap은 O(1) 조회를 위한 **인메모리 캐시**다.
진실의 원본은 `Stacks` 배열이고, TMap은 그것의 인덱스다.
복제할 것은 원본 데이터(배열)이고, 캐시(TMap)는 수신 측에서 콜백으로 재건한다.

---

## UPROPERTY 자동 복제 vs FFastArraySerializer 비교

| | UPROPERTY TArray | FFastArraySerializer |
|---|---|---|
| 변경 감지 | 배열 전체 Shadow 비교 | 항목별 ReplicationKey 비교 |
| 전송 단위 | 변경 있으면 배열 전체 | 변경된 항목만 |
| 콜백 | OnRep_Array (배열 통째로) | Pre/PostReplicated (항목 단위) |
| 적합한 경우 | 항목 적고 변경 빈번 | 항목 많고 일부만 변경 |
| 구현 복잡도 | 단순 | 상속 + 콜백 구현 필요 |

항목이 수십 개 이상이고, 매 틱 일부 항목만 변경되는 경우 `FFastArraySerializer`가 대역폭에서 유리하다.
인벤토리, 버프 목록, 태그 스택 같은 컬렉션이 전형적인 사용 사례다.
