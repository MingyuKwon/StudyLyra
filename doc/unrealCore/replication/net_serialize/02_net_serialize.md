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

UPROPERTY가 붙은 구조체는 엔진이 **자동으로** 필드를 순서대로 직렬화한다.
커스텀 `NetSerialize`가 없으면 엔진이 반사(reflection) 정보로 모든 UPROPERTY를 순회한다.

자동 직렬화의 단점:
- 필드 전체를 보낸다 — 일부 조건에서 특정 필드를 생략하는 최적화 불가
- 정밀도를 선택할 수 없다 — `FVector`를 96비트(float 3개) 대신 48비트로 보내려면 커스텀이 필요
- 불필요한 데이터가 포함될 수 있다

커스텀 `NetSerialize`를 쓰면:
- 보낼 필드와 건너뛸 필드를 직접 선택
- 수치 정밀도를 낮춰 대역폭 절약 (양자화, quantization)
- 서버에서만 의미 있는 필드는 직렬화에서 제외

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
