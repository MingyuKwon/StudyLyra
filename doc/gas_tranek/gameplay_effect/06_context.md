# Gameplay Effect Context

> **GASDoc**: 4.5.10 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-context"></a>
#### GameplayEffectContext는 어떤 정보를 담고 있으며, 서브클래싱이 필요한 이유는 무엇인가?

`GameplayEffectContext`는 GESpec의 인스티게이터와 TargetData 정보를 보유한다. MMC / Execution / GameplayCue 등 여러 곳에 임의의 데이터를 전달할 때 서브클래싱하기 좋은 구조체다.

서브클래싱 6단계:
1. `FGameplayEffectContext`를 서브클래스로 만든다
2. `GetScriptStruct()`를 오버라이드한다
3. `Duplicate()`를 오버라이드한다
4. 새로 추가한 데이터를 복제해야 한다면 `NetSerialize()`를 오버라이드한다
5. 서브클래스에 대해 `TStructOpsTypeTraits`를 구현한다
6. `AbilitySystemGlobals`에서 `AllocGameplayEffectContext()`를 오버라이드하여 서브클래스 객체를 반환한다

---

### Context에서 Instigator와 EffectCauser는 무엇이 다르며, 어떤 정보를 추가로 보유하는가?

> 소스: `GameplayEffectTypes.h:423`

```cpp
TWeakObjectPtr<AActor> Instigator;    // 능력을 소유한 Actor (보통 PlayerState)
TWeakObjectPtr<AActor> EffectCauser;  // 물리적으로 피해를 가한 Actor (총기, 발사체 등)
```

플레이어가 총을 쏜 경우 `Instigator = PlayerState`, `EffectCauser = Bullet`. 근접 공격이면 둘 다 캐릭터다.

그 외 Context가 보유하는 정보:

| 필드 | 설명 |
|---|---|
| `AbilityCDO` | 발동한 어빌리티 CDO (복제됨) |
| `SourceObject` | 효과 발생 원본 오브젝트 |
| `Actors` | TargetData로부터 채워지는 Actor 목록 |
| `HitResult` | 충돌 정보 |
| `WorldOrigin` | 효과 발생 위치 |

---

### GameplayEffectContext를 서브클래싱하면 커스텀 데이터가 MMC/Execution/GameplayCue 전체에 전달되는 이유는?

> 소스: `GameplayEffectTypes.h:493`, `GameplayEffectTypes.cpp:425`

Context는 `FGameplayEffectContextHandle`으로 감싸져 다닌다. Handle이 `TSharedPtr<FGameplayEffectContext>`를 들고 있어 서브클래스 타입도 그대로 보관·복제할 수 있다.

Handle의 `NetSerialize`가 `GetScriptStruct()`로 실제 타입을 판별한 뒤 역직렬화한다. 서브클래스가 `GetScriptStruct()`를 오버라이드하지 않으면 추가 필드가 전부 유실된다.

Context는 `FGameplayEffectSpec` 안에 `FGameplayEffectContextHandle`로 담겨, Spec이 흘러가는 모든 곳(MMC, Execution, GameplayCue)에 함께 전달된다.

---

### GameplayEffectContext를 서브클래싱하는 6단계를 Lyra 구현으로 어떻게 확인할 수 있는가?

> 소스: `LyraGameplayEffectContext.h`, `LyraGameplayEffectContext.cpp`, `LyraAbilitySystemGlobals.cpp:16`

**1단계: 서브클래스 만들기**

```cpp
struct FLyraGameplayEffectContext : public FGameplayEffectContext
{
    int32 CartridgeID = -1;
    TWeakObjectPtr<const UObject> AbilitySourceObject;
};
```

**2단계: GetScriptStruct() 오버라이드**

```cpp
virtual UScriptStruct* GetScriptStruct() const override
{
    return FLyraGameplayEffectContext::StaticStruct();
}
```

**3단계: Duplicate() 오버라이드** — `TSharedPtr<FHitResult>`는 딥카피가 필요하다.

```cpp
virtual FGameplayEffectContext* Duplicate() const override
{
    FLyraGameplayEffectContext* NewContext = new FLyraGameplayEffectContext();
    *NewContext = *this;
    if (GetHitResult())
        NewContext->AddHitResult(*GetHitResult(), true);
    return NewContext;
}
```

**4단계: NetSerialize() 오버라이드** — 추가 필드 중 복제가 필요한 것만 직렬화한다.

```cpp
bool FLyraGameplayEffectContext::NetSerialize(FArchive& Ar, ...)
{
    FGameplayEffectContext::NetSerialize(Ar, Map, bOutSuccess);
    // CartridgeID, AbilitySourceObject는 직렬화 안 함 — 로컬/서버 전용
    return true;
}
```

**5단계: TStructOpsTypeTraits 구현**

```cpp
template<>
struct TStructOpsTypeTraits<FLyraGameplayEffectContext>
    : public TStructOpsTypeTraitsBase2<FLyraGameplayEffectContext>
{
    enum { WithNetSerializer = true, WithCopy = true };
};
```

**6단계: AllocGameplayEffectContext() 오버라이드**

```cpp
// LyraAbilitySystemGlobals.cpp:16
FGameplayEffectContext* ULyraAbilitySystemGlobals::AllocGameplayEffectContext() const
{
    return new FLyraGameplayEffectContext();
}
```

---

### Lyra의 CartridgeID는 샷건처럼 여러 발이 동시에 나가는 무기에서 어떤 문제를 어떻게 해결하는가?

> 소스: `LyraGameplayEffectContext.h:64`

샷건은 한 번의 발사에서 여러 발의 탄환이 나가 각각 독립적인 GE를 적용한다. `CartridgeID`는 같은 발사에서 나온 탄들이 동일한 ID를 공유해서, GameplayCue 등에서 "이 탄들은 같은 발사에서 비롯됐다"고 식별할 수 있게 한다.

`CartridgeID`는 `NetSerialize`에서 직렬화되지 않는다 — 서버에서 GE를 Apply할 때 같은 발사 내에서만 의미 있는 로컬 식별자이기 때문이다.

서브클래스 포인터를 안전하게 꺼내는 패턴:

```cpp
FGameplayEffectContext* BaseEffectContext = Handle.Get();
if (BaseEffectContext &&
    BaseEffectContext->GetScriptStruct()->IsChildOf(FLyraGameplayEffectContext::StaticStruct()))
{
    return (FLyraGameplayEffectContext*)BaseEffectContext;
}
return nullptr;
```

RTTI 없이 `UScriptStruct` 계층으로 타입을 검사한 뒤 캐스트한다.
