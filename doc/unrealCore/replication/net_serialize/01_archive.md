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

```cpp
// Archive.h
bool IsLoading() const { return ArIsLoading; }  // true → 읽기 (역직렬화)
bool IsSaving()  const { return ArIsSaving; }   // true → 쓰기 (직렬화)
```

핵심 설계: **같은 코드 한 벌이 직렬화·역직렬화 양쪽을 처리한다.**
NetSerialize 안에서 `Ar << Health`라고 쓰면 서버에서는 기록하고 클라이언트에서는 읽는다.

---

## operator<< 가 양방향으로 동작하는 메커니즘

`Ar << Value` 한 줄이 서버에서는 쓰고 클라이언트에서는 읽는다.
`operator<<`가 내부적으로 가상함수 `Serialize`를 호출하고,
FBitWriter와 FBitReader가 그것을 반대 방향으로 오버라이드하기 때문이다.

**1단계: operator<< — Serialize 가상함수에 위임**

```cpp
// Archive.h:1580
inline friend FArchive& operator<<(FArchive& Ar, int32& Value)
{
    Ar.ByteOrderSerialize(reinterpret_cast<uint32&>(Value));
    // 결국 Ar.Serialize(&Value, sizeof(Value)) 호출
    return Ar;
}
```

`Value`는 항상 non-const 참조로 전달된다.
`Serialize`가 가상함수이므로 Ar의 실제 타입에 따라 동작이 달라진다.

**2단계: FBitWriter::Serialize — 포인터에서 버퍼로 (쓰기)**

```cpp
// BitWriter.h:64
virtual void Serialize(void* Src, int64 LengthBytes) override;
// Src가 가리키는 메모리를 읽어서 내부 Buffer에 비트를 추가
```

**3단계: FBitReader::Serialize — 버퍼에서 포인터로 (읽기)**

```cpp
// BitReader.h:143
void Serialize(void* Dest, int64 LengthBytes)
{
    SerializeBits(Dest, LengthBytes * 8);
    // 내부 Buffer의 현재 Pos에서 비트를 읽어 Dest에 복사
}
```

**한 눈에 보기**

```
서버 (FBitWriter)                      클라이언트 (FBitReader)

Ar << Health   → Serialize(&Health, 4)   Ar << Health   → Serialize(&Health, 4)
               → Buffer에 4바이트 기록                  → Buffer에서 4바이트 읽기
                                                          → Health 에 저장
```

`operator<<` 코드 자체는 양쪽이 동일하다. 차이는 `Ar`의 실제 타입뿐이다.

---

## 코드가 곧 프로토콜 — Writer와 Reader가 맞는 이유

서버가 쓴 순서·크기를 클라이언트가 어떻게 아는지에 대한 답은 단순하다:
**서버와 클라이언트가 완전히 동일한 소스에서 빌드된 바이너리를 실행한다.**
별도 합의나 메타데이터가 없다. NetSerialize 함수 코드 자체가 프로토콜이다.

```cpp
bool FMyData::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    Ar << Health;     // ① 4바이트
    Ar << Position;   // ② 12바이트
    Ar << TeamIndex;  // ③ 4바이트
    return true;
}
```

FBitReader는 `Pos` 커서를 들고 있다. `Serialize`를 호출할 때마다 읽은 비트 수만큼 Pos가 전진한다.
Writer가 4바이트 썼으면 Reader도 4바이트 읽어 Pos가 정확히 같은 양만큼 이동한다.
`sizeof(int32) = 4`는 양쪽이 동일하므로 보폭이 항상 맞는다.

```
서버 (FBitWriter)          클라이언트 (FBitReader, Pos = 0)

① Health(80) 기록          ① 4바이트 읽기 → Health = 80   (Pos → 32비트)
② Position 기록            ② 12바이트 읽기 → Position = … (Pos → 128비트)
③ TeamIndex 기록           ③ 4바이트 읽기 → TeamIndex = … (Pos → 160비트)
```

### 버전이 달라지면 어떻게 되나

서버만 `Health` 다음에 `Armor` 필드를 추가하면:

```
서버가 쓴 것        클라이언트가 읽는 것

[Health  = 80  ]   → Health = 80     ✓
[Armor   = 50  ]   → Position.X = ?  ← Armor를 Position으로 읽어버림
[Position = …  ]   → Position.Y = ?  ← 이후 전부 어긋남
```

Pos가 어긋나는 순간 이후 모든 필드가 쓰레기값이 된다.
오류 메시지도 없이 조용히 망가진다.
서버/클라이언트 빌드를 항상 같이 배포해야 하는 이유다.

### 조건부 직렬화 — 비트마스크 패턴

일부 필드가 상황에 따라 없을 수 있을 때는 "무엇이 오는지"를 데이터로 먼저 보낸다.

```cpp
bool FMyData::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    uint8 ValidFields = 0;

    if (Ar.IsSaving())                         // 서버만: 마스크 계산
    {
        if (Health > 0)   ValidFields |= (1 << 0);
        if (bHasPosition) ValidFields |= (1 << 1);
    }

    Ar << ValidFields;                         // 마스크를 먼저 전송

    if (ValidFields & (1 << 0)) Ar << Health;  // 양쪽이 같은 마스크로 분기
    if (ValidFields & (1 << 1)) Ar << Position;

    bOutSuccess = !Ar.IsError();
    return true;
}
```

클라이언트가 마스크를 읽은 뒤 같은 조건으로 분기하므로 Pos가 항상 일치한다.
"어떤 필드가 오는지"를 별도 메타데이터 없이 처리하는 방식이다.

---

## FBitWriter — 비트 단위 쓰기

네트워크 전송은 바이트 단위가 아닌 **비트 단위**로 패킹한다.

```cpp
// BitWriter.h
class FBitWriter : public FBitArchive
{
    TArray<uint8> Buffer;  // 비트를 담는 바이트 배열
    int64 Num;             // 현재까지 기록된 비트 수
    int64 Max;             // 버퍼 용량 (비트 단위)
};
```

범위가 고정된 정수는 `SerializeInt`로 필요한 비트 수만큼만 전송할 수 있다.

```cpp
uint32 Value = 3;
Writer.SerializeInt(Value, 10);  // 0~9 범위 → 4비트로 충분 (log2(10) ≒ 4)

float F = 1.5f;
Writer << F;                     // float → 32비트 고정
```

---

## FBitReader — 비트 단위 읽기

`FBitWriter`가 쓴 것을 같은 순서·같은 크기로 읽는다.

```cpp
// BitReader.h
class FBitReader : public FBitArchive
{
    TArray<uint8> Buffer;  // 수신한 바이트 배열
    int64 Pos;             // 현재 읽기 위치 (비트 단위)
    int64 Num;             // 전체 비트 수
};
```

```cpp
bool IsError() const;  // Pos가 Num을 넘겼거나 오류 발생 시 true
```

NetSerialize에서 `bOutSuccess = !Ar.IsError()`로 오류를 상위로 전파한다.
Pos가 어긋나서 범위를 벗어나면 IsError가 true가 되고,
이 구조체를 적용한 GE나 GameplayCue가 무시된다.

---

## FInBunch / FOutBunch — 실제 네트워크에서 쓰이는 것

```cpp
// DataBunch.h
class FOutBunch : public FBitWriter { ... };  // 서버 → 클라 전송용
class FInBunch  : public FBitReader { ... };  // 클라 수신용
```

`UActorChannel::ReplicateActor()`가 `FOutBunch`에 프로퍼티를 기록하고,
Bunch가 `UNetConnection`을 통해 UDP 패킷으로 조립되어 전송된다.

클라이언트는 패킷을 `FInBunch`로 분해한 뒤
`UActorChannel::ReceivedBunch()`에서 읽어 값을 적용한다.

---

## 비트 패킹 — 왜 비트 단위인가

| 데이터 | 바이트 직렬화 | 비트 직렬화 |
|--------|--------------|------------|
| bool | 1바이트 = 8비트 | **1비트** |
| 0~7 범위 정수 | 1바이트 = 8비트 | **3비트** |
| 4개의 bool | 4바이트 | **4비트** |

초당 60 틱, 플레이어 100명, 매 틱 프로퍼티 수십 개가 오가는 환경에서
비트 단위 패킹은 대역폭을 눈에 띄게 줄인다.
