# Gameplay Effect Context

> **GASDoc**: 4.5.10 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-context"></a>
#### 4.5.10 Gameplay Effect Context

[`GameplayEffectContext`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayEffectContext/index.html) 구조체는 `GameplayEffectSpec`의 인스티게이터(instigator)와 [`TargetData`](#concepts-targeting-data) 정보를 보유한다. 또한 [`ModifierMagnitudeCalculations`](#concepts-ge-mmc) / [`GameplayEffectExecutionCalculations`](#concepts-ge-ec), [`AttributeSets`](#concepts-as), [`GameplayCues`](#concepts-gc) 등 여러 곳에 임의의 데이터를 전달할 때 서브클래싱하기 좋은 구조체이기도 하다.

`GameplayEffectContext`를 서브클래싱하는 방법:

1. `FGameplayEffectContext`를 서브클래스로 만든다
1. `FGameplayEffectContext::GetScriptStruct()`를 오버라이드한다
1. `FGameplayEffectContext::Duplicate()`를 오버라이드한다
1. 새로 추가한 데이터를 복제해야 한다면 `FGameplayEffectContext::NetSerialize()`를 오버라이드한다
1. 부모 구조체 `FGameplayEffectContext`와 마찬가지로 서브클래스에 대해 `TStructOpsTypeTraits`를 구현한다
1. [`AbilitySystemGlobals`](#concepts-asg) 클래스에서 `AllocGameplayEffectContext()`를 오버라이드하여 서브클래스 객체를 반환하도록 한다

[GASShooter](https://github.com/tranek/GASShooter)는 서브클래싱된 `GameplayEffectContext`를 사용해 `TargetData`를 추가한다. 이 `TargetData`는 `GameplayCues`에서 접근할 수 있으며, 특히 여러 적을 동시에 맞힐 수 있는 샷건에서 활용된다.

---

## 내 분석

### "인스티게이터와 TargetData 정보를 보유한다"

> 소스: `GameplayEffectTypes.h:423`

"인스티게이터"라고 단순히 표현되어 있지만, 실제로는 두 개의 Actor 포인터를 구분해서 들고 있다.

```cpp
TWeakObjectPtr<AActor> Instigator;    // 능력을 소유한 Actor (보통 PlayerState)
TWeakObjectPtr<AActor> EffectCauser;  // 물리적으로 피해를 가한 Actor (총기, 발사체 등)
```

플레이어가 총을 쏜 경우 `Instigator = PlayerState`, `EffectCauser = Bullet`. 근접 공격이면 둘 다 캐릭터다. `GetInstigatorAbilitySystemComponent()`는 이 `Instigator`로부터 ASC를 찾아 반환하는데, 이 ASC 포인터 자체는 복제되지 않고 수신 측에서 로컬 재조회한다.

그 외 Context가 보유하는 정보:

```cpp
TWeakObjectPtr<UGameplayAbility> AbilityCDO;          // 발동한 어빌리티 CDO (복제됨)
TWeakObjectPtr<UObject>          SourceObject;         // 효과 발생 원본 오브젝트
TArray<TWeakObjectPtr<AActor>>   Actors;               // TargetData로부터 채워지는 Actor 목록
TSharedPtr<FHitResult>           HitResult;            // 충돌 정보
FVector                          WorldOrigin;          // 효과 발생 위치
```

"TargetData 정보를 보유한다"는 것은 `Actors`와 `HitResult`가 TargetData로부터 Context로 옮겨와 저장된다는 뜻이다. Context가 MMC / Execution / GameplayCue로 흘러갈 때 이 타겟 정보를 함께 들고 간다.

---

### "여러 곳에 임의의 데이터를 전달할 때 서브클래싱하기 좋다"

> 소스: `GameplayEffectTypes.h:493`, `GameplayEffectTypes.cpp:425`

Context는 직접 전달되는 게 아니라 `FGameplayEffectContextHandle`로 감싸져 다닌다. Handle이 `TSharedPtr<FGameplayEffectContext>`를 들고 있어서, 서브클래스 타입도 그대로 보관·복제할 수 있다.

```cpp
// GameplayEffectTypes.h:797
TSharedPtr<FGameplayEffectContext> Data;  // 서브클래스 포인터도 들어갈 수 있음
```

Handle의 `NetSerialize`가 `GetScriptStruct()`로 실제 타입을 판별한 뒤 그에 맞게 역직렬화한다. 서브클래스가 `GetScriptStruct()`를 오버라이드하지 않으면 Handle이 타입을 구분하지 못해 기본 타입으로 역직렬화되므로, 추가 필드가 전부 유실된다.

Context는 `FGameplayEffectSpec` 안에 `FGameplayEffectContextHandle`로 담겨, Spec이 흘러가는 모든 곳(MMC, Execution, GameplayCue)에 함께 전달된다. 커스텀 데이터를 Spec과 함께 어디든 실어 보낼 수 있는 이유다.

---

### "서브클래싱하는 방법 6단계" — Lyra 구현으로 보기

> 소스: `LyraGameplayEffectContext.h`, `LyraGameplayEffectContext.cpp`, `LyraAbilitySystemGlobals.cpp:16`

Lyra가 각 단계를 실제로 어떻게 구현했는지 코드로 확인한다.

**1단계: FGameplayEffectContext 서브클래스 만들기**

```cpp
// LyraGameplayEffectContext.h:16
struct FLyraGameplayEffectContext : public FGameplayEffectContext
{
    int32 CartridgeID = -1;                          // 추가 필드: 탄창 ID
    TWeakObjectPtr<const UObject> AbilitySourceObject; // 추가 필드: 무기/장비 소스
};
```

**2단계: GetScriptStruct() 오버라이드** — Handle이 타입을 판별할 수 있게 한다.

```cpp
virtual UScriptStruct* GetScriptStruct() const override
{
    return FLyraGameplayEffectContext::StaticStruct();
}
```

**3단계: Duplicate() 오버라이드** — `TSharedPtr<FHitResult>`는 포인터만 복사되므로 딥카피가 필요하다.

```cpp
virtual FGameplayEffectContext* Duplicate() const override
{
    FLyraGameplayEffectContext* NewContext = new FLyraGameplayEffectContext();
    *NewContext = *this;
    if (GetHitResult())
        NewContext->AddHitResult(*GetHitResult(), true);  // 딥카피
    return NewContext;
}
```

**4단계: NetSerialize() 오버라이드** — 추가 필드 중 복제가 필요한 것만 직렬화한다.

```cpp
// LyraGameplayEffectContext.cpp:27
bool FLyraGameplayEffectContext::NetSerialize(FArchive& Ar, ...)
{
    FGameplayEffectContext::NetSerialize(Ar, Map, bOutSuccess);
    // CartridgeID는 직렬화 안 함 — 로컬 전용
    // AbilitySourceObject도 직렬화 안 함 — 서버 전용
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

**6단계: AllocGameplayEffectContext() 오버라이드** — GAS가 Context를 새로 할당할 때 이 함수를 통한다. 여기서 서브클래스를 반환해야 시스템 전체에서 서브클래스 Context가 쓰인다.

```cpp
// LyraAbilitySystemGlobals.cpp:16
FGameplayEffectContext* ULyraAbilitySystemGlobals::AllocGameplayEffectContext() const
{
    return new FLyraGameplayEffectContext();
}
```

---

### "샷건에서 TargetData 활용" — Lyra의 CartridgeID

> 소스: `LyraGameplayEffectContext.h:64`

GASShooter 예시에서 말하는 "여러 적을 동시에 맞히는 샷건 패턴"을 Lyra도 동일하게 구현한다. 샷건은 한 번의 발사에서 여러 발의 탄환이 나가 각각 독립적인 GE를 적용한다. `CartridgeID`는 같은 발사에서 나온 탄들이 동일한 ID를 공유해서 "이 탄들은 같은 발사에서 비롯됐다"는 것을 GameplayCue 등에서 식별할 수 있게 한다.

`CartridgeID`는 `NetSerialize`에서 직렬화되지 않는다 — 서버에서 GE를 Apply할 때 같은 발사 내에서만 의미 있는 로컬 식별자이기 때문이다.

서브클래스 포인터를 안전하게 꺼내는 패턴도 Lyra에서 확인할 수 있다:

```cpp
// LyraGameplayEffectContext.cpp:16 — ExtractEffectContext
FGameplayEffectContext* BaseEffectContext = Handle.Get();
if (BaseEffectContext &&
    BaseEffectContext->GetScriptStruct()->IsChildOf(FLyraGameplayEffectContext::StaticStruct()))
{
    return (FLyraGameplayEffectContext*)BaseEffectContext;
}
return nullptr;
```

RTTI 없이 `UScriptStruct` 계층으로 타입을 검사한 뒤 캐스트한다. 이 헬퍼를 Execution과 GameplayCue에서 호출해 커스텀 필드를 꺼낸다.
