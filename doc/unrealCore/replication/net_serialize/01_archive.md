# FArchive / FBitWriter / FBitReader

> 소스:  
> `Engine/Source/Runtime/Core/Public/Serialization/Archive.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitWriter.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitReader.h`

직렬화 스택의 가장 낮은 레이어.
모든 네트워크 데이터는 결국 이 비트 스트림을 통해 흐른다.

---

## FArchive — 읽기/쓰기 양방향 추상화

`FArchive`는 "스트림에 데이터를 넣거나 꺼내는 것"을 추상화한 기반 클래스다.
파일 저장, 패키지 로딩, 네트워크 전송이 모두 `FArchive` 서브클래스를 공유한다.

핵심 설계: **같은 코드가 직렬화·역직렬화 양쪽을 처리한다.**

```cpp
// Archive.h
bool IsLoading() const  { return ArIsLoading; }   // true → 읽기 (역직렬화)
bool IsSaving()  const  { return ArIsSaving; }    // true → 쓰기 (직렬화)
```

`operator<<`는 방향에 따라 자동으로 읽기 또는 쓰기로 동작한다.

```cpp
// FBitWriter에서 쓰기
FBitWriter Writer;
int32 Value = 42;
Writer << Value;   // Writer에 42를 기록

// FBitReader에서 읽기
FBitReader Reader(...);
int32 Value;
Reader << Value;   // Reader에서 42를 읽어 Value에 저장
```

NetSerialize를 구현할 때 `Ar << SomeField`라고 쓰면,
서버에서는 쓰기, 클라이언트에서는 읽기로 자동 동작한다.
코드 한 벌로 직렬화·역직렬화를 모두 처리하는 이유다.

---

## FBitWriter — 비트 단위 쓰기

네트워크 전송은 바이트 단위가 아닌 **비트 단위**로 패킹한다.
대역폭을 아끼기 위해서다.

```cpp
// BitWriter.h
class FBitWriter : public FArchive
{
    TArray<uint8> Buffer;   // 비트를 담는 바이트 배열
    int64 Num;              // 현재까지 기록된 비트 수
    int64 Max;              // 버퍼 용량 (비트 단위)
};
```

기본 타입 직렬화 예시:

```cpp
// bool → 1비트
bool bFlag = true;
Writer.WriteBit(bFlag ? 1 : 0);

// uint32 → 최대 32비트, 하지만 SerializeInt로 범위 지정 가능
uint32 Value = 3;
Writer.SerializeInt(Value, 10);  // 0~9 범위면 4비트로 충분

// float → 32비트 고정
float F = 1.5f;
Writer << F;   // 32비트 그대로
```

`SerializeInt(Value, MaxValue)`는 `MaxValue`가 표현되려면 몇 비트가 필요한지 계산해
그 비트 수만큼만 전송한다. 상태값처럼 범위가 고정된 정수에 유용하다.

---

## FBitReader — 비트 단위 읽기

`FBitWriter`가 쓴 것을 같은 순서·같은 크기로 읽는다.

```cpp
// BitReader.h
class FBitReader : public FArchive
{
    TArray<uint8> Buffer;   // 수신한 바이트 배열
    int64 Pos;              // 현재 읽기 위치 (비트 단위)
    int64 Num;              // 전체 비트 수
};
```

핵심 제약: **서버가 쓴 순서와 정확히 같은 순서로 읽어야 한다.**
순서가 어긋나면 엉뚱한 값을 읽어 조용히 오류가 발생한다.

```cpp
bool IsError() const;  // 읽기 범위를 벗어났거나 오류 발생 시 true
```

NetSerialize에서 `bOutSuccess = !Ar.IsError()`로 오류를 상위로 전파하는 이유다.

---

## FInBunch / FOutBunch — 네트워크 Bunch

실제 네트워크에서 쓰이는 것은 `FBitWriter`·`FBitReader`를 상속한
`FOutBunch`와 `FInBunch`다.

```cpp
// DataBunch.h
class FOutBunch : public FBitWriter { ... };  // 서버 → 클라 전송용
class FInBunch  : public FBitReader { ... };  // 클라 수신용
```

`UActorChannel::ReplicateActor()`가 `FOutBunch`에 프로퍼티를 기록하고,
그 Bunch가 `UNetConnection`을 통해 패킷으로 조립되어 전송된다.

클라이언트 수신 측에서는 패킷을 `FInBunch`로 분해한 뒤
`UActorChannel::ReceivedBunch()`에서 읽어 값을 적용한다.

---

## 비트 패킹 예시 — 왜 비트 단위인가

바이트 경계에 맞추면 낭비가 크다.

| 데이터 | 바이트 직렬화 | 비트 직렬화 |
|--------|--------------|------------|
| bool (true/false) | 1바이트 = 8비트 | **1비트** |
| 0~7 범위 정수 | 1바이트 = 8비트 | **3비트** |
| 0~255 범위 정수 | 1바이트 | 8비트 (동일) |
| 4개의 bool | 4바이트 | **4비트** |

초당 60 틱, 플레이어 100명, 매 틱 프로퍼티 수십 개가 오가는 환경에서
비트 단위 패킹은 대역폭을 눈에 띄게 줄인다.
