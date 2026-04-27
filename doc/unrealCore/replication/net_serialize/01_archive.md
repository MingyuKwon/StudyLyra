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

## operator<< 가 양방향으로 동작하는 실제 메커니즘

겉으로는 같은 `Ar << Value` 한 줄인데, 서버에서는 쓰고 클라이언트에서는 읽는다.
이게 가능한 이유는 `operator<<`가 내부적으로 가상함수 `Serialize`를 호출하고,
FBitWriter와 FBitReader가 그것을 각각 반대 방향으로 오버라이드하기 때문이다.

**1단계: operator<< — Serialize 가상함수에 위임**

```cpp
// Archive.h:1580
inline friend FArchive& operator<<(FArchive& Ar, int32& Value)
{
    Ar.ByteOrderSerialize(reinterpret_cast<uint32&>(Value));
    //       ↑ 결국 Ar.Serialize(&Value, sizeof(Value)) 를 호출
    return Ar;
}
```

`Value`는 항상 **non-const 참조**로 전달된다.
쓸 때는 읽어가고, 읽을 때는 채워 넣는다.
`Serialize`가 가상함수이므로 실제 동작은 Ar의 실제 타입에 따라 달라진다.

**2단계: FBitWriter::Serialize — 포인터에서 버퍼로 (쓰기)**

```cpp
// BitWriter.h:64
virtual void Serialize(void* Src, int64 LengthBytes) override;
// → Src가 가리키는 메모리를 읽어서 내부 Buffer에 비트를 추가
```

서버에서 `Ar << Health`가 호출되면:
- `Ar`은 `FBitWriter` (또는 `FOutBunch`)
- `Serialize(&Health, 4)` → `Health` 변수의 4바이트를 Buffer에 기록

**3단계: FBitReader::Serialize — 버퍼에서 포인터로 (읽기)**

```cpp
// BitReader.h:143
UE_FORCEINLINE_HINT void Serialize(void* Dest, int64 LengthBytes)
{
    SerializeBits(Dest, LengthBytes * 8);
    // → 내부 Buffer의 현재 Pos에서 LengthBytes*8 비트를 읽어 Dest에 복사
}
```

클라이언트에서 `Ar << Health`가 호출되면:
- `Ar`은 `FBitReader` (또는 `FInBunch`)
- `Serialize(&Health, 4)` → Buffer의 현재 위치에서 4바이트를 읽어 `Health`에 저장

**전체 흐름을 코드로 표현**

```cpp
// [서버] Ar = FBitWriter (FOutBunch)
//   Health = 80 (현재 값)
Ar << Health;
// → operator<<(Ar, Health)
// → Ar.Serialize(&Health, 4)
// → FBitWriter::Serialize: Buffer에 0x00000050 기록
// → Buffer: [..., 80, ...]

// ─── 네트워크 전송 ───

// [클라이언트] Ar = FBitReader (FInBunch)
//   Health = ? (아직 모름)
Ar << Health;
// → operator<<(Ar, Health)
// → Ar.Serialize(&Health, 4)
// → FBitReader::Serialize: Buffer에서 0x00000050 읽어 Health에 저장
// → Health = 80
```

`operator<<` 코드 자체는 서버/클라이언트 모두 동일하다.
차이는 `Ar`의 실제 타입뿐이다.
NetSerialize 함수 하나로 직렬화·역직렬화를 모두 처리할 수 있는 이유다.

**NetSerialize에서 이 원리를 활용하는 패턴**

```cpp
bool FMyData::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    // 아래 세 줄은 서버/클라이언트에서 완전히 동일한 코드
    Ar << Health;     // 서버: Buffer에 기록 / 클라이언트: Buffer에서 읽기
    Ar << Position;   // 서버: Buffer에 기록 / 클라이언트: Buffer에서 읽기
    Ar << TeamIndex;  // 서버: Buffer에 기록 / 클라이언트: Buffer에서 읽기

    bOutSuccess = !Ar.IsError();
    return true;
}
```

단, `IsLoading()`으로 분기해야 하는 경우가 있다.
중간 계산이나 조건부 직렬화처럼 "쓸 때와 읽을 때 로직이 다른" 상황이다.

```cpp
bool FMyData::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    // 유효한 필드만 보내는 비트마스크 패턴
    uint8 ValidFields = 0;

    if (Ar.IsSaving())  // 서버: 보내기 전에 마스크 계산
    {
        if (Health > 0)    ValidFields |= (1 << 0);
        if (bHasPosition)  ValidFields |= (1 << 1);
    }

    Ar << ValidFields;  // 마스크 자체는 양방향 동일

    if (ValidFields & (1 << 0))  Ar << Health;    // 있을 때만 읽기/쓰기
    if (ValidFields & (1 << 1))  Ar << Position;

    bOutSuccess = !Ar.IsError();
    return true;
}
// 서버가 쓴 마스크를 클라이언트가 읽어, 같은 조건 분기로 같은 필드만 읽는다.
// 마스크가 일치하므로 "어떤 필드가 오는지"를 별도 메타데이터 없이 처리한다.
```

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
