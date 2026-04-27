# NetSerialize & TStructOpsTypeTraits

> 소스:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/Engine/Public/Net/UnrealNetwork.h`  
> `Engine/Source/Runtime/GameplayAbilities/Public/GameplayEffectTypes.h`  
> `Engine/Source/Runtime/GameplayAbilities/Public/GameplayTagContainer.h`

구조체가 직렬화 방식을 직접 제어하는 방법.
`TStructOpsTypeTraits`로 엔진에 알리고, `NetSerialize`에서 비트를 직접 쓰고 읽는다.

---

## 자동 직렬화 vs 커스텀 NetSerialize

### 자동 직렬화 — UPROPERTY 필드만, CPF_RepSkip 제외

구조체에 커스텀 `NetSerialize`가 없으면 RepLayout이 반사(reflection) 정보로 필드를 순회한다.
**이때 보이는 것은 `UPROPERTY()`가 붙은 필드뿐이다.**

```cpp
// RepLayout.cpp:5620 — 구조체 내부 필드 순회
for (TFieldIterator<FProperty> It(Struct); It; ++It)
{
    if (It->PropertyFlags & CPF_RepSkip)  // UPROPERTY(NotReplicated) 는 건너뜀
        continue;

    NetProperties.Add(*It);  // UPROPERTY 필드만 여기 들어옴
}
```

`TFieldIterator<FProperty>`는 UHT(Unreal Header Tool)가 생성한 `FProperty` 객체를 순회한다.
`UPROPERTY()` 매크로가 없는 필드는 UHT가 `FProperty`를 생성하지 않으므로
이터레이터에 아예 나타나지 않는다.

```cpp
USTRUCT()
struct FMyStruct
{
    GENERATED_BODY()

    UPROPERTY() float Health;     // ← FProperty 생성됨 → 자동 직렬화 대상
    UPROPERTY() FVector Position; // ← FProperty 생성됨 → 자동 직렬화 대상
    float CachedValue;            // ← FProperty 없음   → 완전히 투명, 직렬화 안 됨
    int32 LocalDebugId;           // ← FProperty 없음   → 완전히 투명, 직렬화 안 됨
};
```

`UPROPERTY()`가 붙어있어도 `NotReplicated` 지정자가 있으면 `CPF_RepSkip` 플래그가 세팅되어 건너뛴다.

```cpp
UPROPERTY(NotReplicated) int32 ServerOnlyData;  // CPF_RepSkip → 직렬화에서 제외
```

### STRUCT_NetSerializeNative — 커스텀 분기점

RepLayout이 구조체 필드를 재귀 탐색하다가 중첩 구조체를 만나면,
그 구조체에 `STRUCT_NetSerializeNative` 플래그가 있는지 먼저 확인한다.

```cpp
// RepLayout.cpp:5720
if (EnumHasAnyFlags(Struct->StructFlags, STRUCT_NetSerializeNative))
{
    // 커스텀 NetSerialize가 있다 → 내부 필드 탐색하지 않고 NetSerialize 직접 호출
    Cmd.Type = ERepLayoutCmdType::NetSerializeStructWithObjectReferences;
    ...
}
else
{
    // 커스텀 없음 → UPROPERTY 필드 재귀 탐색
    return InitFromStructProperty<BuildType>(...);
}
```

`STRUCT_NetSerializeNative`는 `TStructOpsTypeTraits`에 `WithNetSerializer = true`를 선언하면
UHT가 자동으로 설정한다.
커스텀 `NetSerialize`가 있는 구조체는 내부가 블랙박스로 취급되고 함수 하나로 직렬화가 위임된다.

### 자동 직렬화의 한계

```cpp
USTRUCT()
struct FCharacterState
{
    GENERATED_BODY()

    UPROPERTY() float Health;       // 32비트 — 항상 전송
    UPROPERTY() float MaxHealth;    // 32비트 — 항상 전송
    UPROPERTY() FVector Position;   // 96비트(float 3개) — 항상 전송
    UPROPERTY() bool bIsAlive;      // 32비트 (bool은 legacy로 4바이트)
    // 합계: 매번 최소 160비트 전송
};
```

자동 직렬화의 한계:
- **필드 전체를 보낸다** — `bIsAlive`만 바뀌어도 구조체 전체가 전송됨
- **정밀도를 선택할 수 없다** — `Position`을 96비트 대신 30비트로 양자화 불가
- **조건부 생략 불가** — `Health`가 MaxHealth와 같을 때 생략하는 최적화 불가
- **서버 전용 필드 혼입** — 서버만 쓰는 필드가 UPROPERTY라면 클라이언트에도 전송됨

### 커스텀 NetSerialize로 해결

```cpp
USTRUCT()
struct FCharacterState
{
    GENERATED_BODY()

    UPROPERTY() float    Health;
    UPROPERTY() float    MaxHealth;
    UPROPERTY() FVector  Position;
    UPROPERTY() bool     bIsAlive;
    float                CachedRatio;  // UPROPERTY 없음 → 직렬화 안 됨 (서버 계산용)

    bool NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
    {
        uint8 Flags = 0;

        if (Ar.IsSaving())
        {
            if (!bIsAlive)      Flags |= (1 << 0);  // 죽었을 때만 플래그
            if (Health < MaxHealth) Flags |= (1 << 1);  // 체력이 깎였을 때만 전송
        }

        Ar << Flags;  // 1바이트 — 무엇이 오는지 알림

        if (Flags & (1 << 0))
        {
            uint8 Bit = (Flags >> 0) & 1;
            Ar.SerializeBits(&Bit, 1);  // bIsAlive → 1비트
            if (Ar.IsLoading()) bIsAlive = !!Bit;
        }

        if (Flags & (1 << 1))
        {
            // Position을 FVector_NetQuantize10으로 양자화 (96비트 → ~60비트)
            FVector_NetQuantize10 QuantizedPos(Position);
            QuantizedPos.NetSerialize(Ar, Map, bOutSuccess);
            if (Ar.IsLoading()) Position = QuantizedPos;

            Ar << Health;  // 32비트 — 범위 제한 없어 그대로
        }

        // CachedRatio는 아예 없음 — 서버가 매번 재계산

        bOutSuccess = !Ar.IsError();
        return true;
    }
};

template<>
struct TStructOpsTypeTraits<FCharacterState> : public TStructOpsTypeTraitsBase2<FCharacterState>
{
    enum { WithNetSerializer = true };
};
```

결과 비교:

| 케이스 | 자동 직렬화 | 커스텀 NetSerialize |
|--------|------------|-------------------|
| 체력 풀 + 살아있음 | 160비트 항상 전송 | Flags 1바이트만 전송 |
| 체력 감소 + 이동 | 160비트 | Flags + Position(60비트) + Health(32비트) ≈ 100비트 |
| 사망 | 160비트 | Flags + bIsAlive(1비트) ≈ 9비트 |

---

## TStructOpsTypeTraits — 구조체 능력 등록

엔진이 "이 구조체는 NetSerialize를 직접 구현했다"고 알 수 있게 하는 등록 메커니즘.

```cpp
// 구조체 정의
USTRUCT()
struct FMyData
{
    GENERATED_BODY()

    float Position;
    bool  bIsActive;
    int32 Health;

    bool NetSerialize(FArchive& Ar, class UPackageMap* Map, bool& bOutSuccess);
};

// 엔진에 등록
template<>
struct TStructOpsTypeTraits<FMyData> : public TStructOpsTypeTraitsBase2<FMyData>
{
    enum
    {
        WithNetSerializer = true,   // NetSerialize 함수가 있다
    };
};
```

`WithNetSerializer = true`가 없으면 엔진은 이 구조체에 `NetSerialize`가 있어도
자동 직렬화 경로를 탄다. 반드시 함께 선언해야 한다.

자주 쓰이는 Traits 플래그:

| 플래그 | 의미 |
|--------|------|
| `WithNetSerializer` | `NetSerialize(FArchive&, UPackageMap*, bool&)` 활성화 |
| `WithNetDeltaSerializer` | `NetDeltaSerialize(FNetDeltaSerializeInfo&)` 활성화 (FFastArraySerializer용) |
| `WithNetSharedSerialization` | 여러 연결에 직렬화 결과를 공유 (읽기 전용 데이터 최적화) |
| `WithCopy` | 복사 연산자 지원 |

---

## NetSerialize 함수 시그니처

```cpp
bool FMyData::NetSerialize(FArchive& Ar, class UPackageMap* Map, bool& bOutSuccess)
{
    // Ar.IsLoading() == true  → 클라이언트에서 역직렬화 (읽기)
    // Ar.IsSaving()  == true  → 서버에서 직렬화 (쓰기)

    Ar << Health;         // 32비트 int
    Ar << Position;       // 32비트 float

    // bool은 SerializeBits로 1비트만
    uint8 Active = bIsActive ? 1 : 0;
    Ar.SerializeBits(&Active, 1);
    if (Ar.IsLoading()) bIsActive = Active != 0;

    bOutSuccess = !Ar.IsError();
    return true;
}
```

`UPackageMap* Map`은 오브젝트 참조를 직렬화할 때 쓴다.
`AActor*`, `UObject*` 같은 포인터는 주소값을 직접 보낼 수 없기 때문에
PackageMap이 `FNetworkGUID`(32비트 ID)로 변환해준다.

```cpp
// 오브젝트 포인터 직렬화
TWeakObjectPtr<AActor> TargetActor;
Map->SerializeObject(Ar, AActor::StaticClass(), (UObject*&)TargetActor);
```

---

## 양자화 (Quantization) — 정밀도를 낮춰 비트 절약

`FVector`를 96비트 그대로 보내는 대신, 게임에 필요한 정밀도만큼만 보낼 수 있다.

```cpp
// FVector를 30비트로 양자화 (각 축 10비트)
bool FMyPositionData::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    // 10비트, 범위 [-1024, 1024], 정밀도 ~2 유닛
    Position.NetSerialize(Ar, Map, bOutSuccess);  // FVector_NetQuantize10 쓰면 자동

    bOutSuccess = !Ar.IsError();
    return true;
}
```

엔진이 제공하는 양자화 타입:

| 타입 | 정밀도 | 비트 |
|------|--------|------|
| `FVector_NetQuantize` | 1 유닛 | ~57비트 |
| `FVector_NetQuantize10` | 0.1 유닛 | ~60비트 |
| `FVector_NetQuantize100` | 0.01 유닛 | ~63비트 |
| `FVector_NetQuantizeNormal` | 법선 벡터 전용 | 30비트 |

---

## 실제 예시 — FGameplayEffectContext

GAS의 `FGameplayEffectContext`는 `NetSerialize`를 직접 구현한다.

```cpp
// GameplayEffectTypes.h
template<>
struct TStructOpsTypeTraits<FGameplayEffectContext>
    : public TStructOpsTypeTraitsBase2<FGameplayEffectContext>
{
    enum
    {
        WithNetSerializer = true,
        WithCopy = true
    };
};
```

```cpp
// GameplayEffectTypes.cpp
bool FGameplayEffectContext::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    uint8 RepBits = 0;

    if (Ar.IsSaving())
    {
        // 어떤 필드가 유효한지 비트마스크로 먼저 기록
        if (Instigator.IsValid())   RepBits |= 1 << 0;
        if (EffectCauser.IsValid()) RepBits |= 1 << 1;
        if (HitResult.IsValid())    RepBits |= 1 << 2;
        // ...
    }

    Ar << RepBits;  // 유효 필드 비트마스크 전송

    // 해당 비트가 설정된 필드만 직렬화
    if (RepBits & (1 << 0)) Map->SerializeObject(Ar, AActor::StaticClass(), Instigator);
    if (RepBits & (1 << 1)) Map->SerializeObject(Ar, AActor::StaticClass(), EffectCauser);
    if (RepBits & (1 << 2)) { /* HitResult 직렬화 */ }

    bOutSuccess = !Ar.IsError();
    return true;
}
```

null인 필드는 아예 전송하지 않는다.
`RepBits` 비트마스크 1바이트로 "무엇이 오는지"를 알리고, 해당 데이터만 읽는다.
유효하지 않은 필드가 많은 경우 자동 직렬화보다 훨씬 작은 패킷이 만들어진다.

---

## Lyra의 FLyraGameplayEffectContext

Lyra는 `FGameplayEffectContext`를 서브클래싱하면서 `NetSerialize`도 오버라이드한다.

```cpp
// LyraGameplayEffectContext.cpp
bool FLyraGameplayEffectContext::NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess)
{
    FGameplayEffectContext::NetSerialize(Ar, Map, bOutSuccess);  // 부모 먼저

    // CartridgeID, AbilitySourceObject는 직렬화하지 않음
    // — CartridgeID는 로컬 식별자, AbilitySourceObject는 서버 전용
    return true;
}
```

추가 필드라도 복제가 필요 없으면 직렬화하지 않는다.
"이 필드는 서버에서만 쓴다"는 설계 결정이 NetSerialize 안에 표현된다.
