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

### FGameplayEffectContext — 구조와 역할

> 소스: `GameplayEffectTypes.h:248`

`FGameplayEffectContext`는 GE가 "누가, 어디서, 어떤 경위로 발생했는가"를 담는 컨텍스트 객체다. Spec이 "무엇을 어떻게 적용할지"를 담는다면, Context는 "누가 발생시켰는지"를 담는다.

```cpp
// GameplayEffectTypes.h:423 — 핵심 필드들
TWeakObjectPtr<AActor>                  Instigator;              // 능력을 소유한 Actor (PlayerState 등)
TWeakObjectPtr<AActor>                  EffectCauser;            // 물리적 발생원 (무기, 발사체 등)
TWeakObjectPtr<UGameplayAbility>        AbilityCDO;              // 발동한 능력의 CDO (복제됨)
TWeakObjectPtr<UGameplayAbility>        AbilityInstanceNotReplicated; // 능력 인스턴스 (복제 안 됨)
int32                                   AbilityLevel;
TWeakObjectPtr<UObject>                 SourceObject;            // 효과 발생 원본 오브젝트
TWeakObjectPtr<UAbilitySystemComponent> InstigatorAbilitySystemComponent; // 복제 안 됨
TArray<TWeakObjectPtr<AActor>>          Actors;
TSharedPtr<FHitResult>                  HitResult;               // 충돌 정보 (UPROPERTY 아님)
FVector                                 WorldOrigin;
```

**Instigator vs EffectCauser 구분**:

| 필드 | 예시 | 설명 |
|---|---|---|
| `Instigator` | PlayerState / Character | 능력 시스템 컴포넌트를 소유한 Actor |
| `EffectCauser` | 총기, 발사체, 폭발 오브젝트 | 실제로 피해를 가한 물리적 주체 |

플레이어가 총을 발사한 경우 `Instigator = PlayerState`, `EffectCauser = Bullet Actor`. 근접 공격이면 둘 다 캐릭터가 될 수 있다.

---

### 복제 구조 — 필드마다 다른 전략

> 소스: `GameplayEffectTypes.cpp:269`

Context는 각 필드를 7비트 플래그(`RepBits`)로 인코딩해서, 유효한 데이터가 있는 필드만 전송한다.

```cpp
// GameplayEffectTypes.cpp:275 — 7비트 선택적 직렬화
Ar.SerializeBits(&RepBits, 7);

// bit 0: Instigator        (bReplicateInstigator가 true면 포함)
// bit 1: EffectCauser      (bReplicateEffectCauser가 true면 포함)
// bit 2: AbilityCDO        (유효하면 포함)
// bit 3: SourceObject      (bReplicateSourceObject가 true면 포함)
// bit 4: Actors            (배열이 비어있지 않으면 포함)
// bit 5: HitResult         (유효하면 포함)
// bit 6: WorldOrigin       (bHasWorldOrigin가 true면 포함)
```

`bReplicateInstigator` 같은 플래그는 `AddInstigator()` 호출 시 Actor가 네트워크 복제를 지원하면 자동으로 true가 된다.

```cpp
// GameplayEffectTypes.cpp:212
bReplicateInstigator = CanActorReferenceBeReplicated(InInstigator);
```

`InstigatorAbilitySystemComponent`는 `NotReplicated` — 클라이언트에서 수신 후 `AddInstigator()`를 재호출해 로컬에서 채운다:

```cpp
// GameplayEffectTypes.cpp:353 — 수신 측 재구성
if (Ar.IsLoading())
{
    AddInstigator(Instigator.Get(), EffectCauser.Get());
    // → InstigatorAbilitySystemComponent를 로컬에서 다시 조회
}
```

---

### Handle이 필요한 이유 — 다형성 복제

> 소스: `GameplayEffectTypes.cpp:425`

`FGameplayEffectContext`는 서브클래싱이 가능한 가상 구조체다. Handle은 이 다형성을 지원하기 위해 `TSharedPtr<FGameplayEffectContext>`를 들고 있다.

```cpp
// GameplayEffectTypes.h:797
TSharedPtr<FGameplayEffectContext> Data;
```

Handle의 `NetSerialize`가 `GetScriptStruct()`로 실제 타입을 판별해서, 올바른 서브클래스 인스턴스로 역직렬화한다.

```cpp
// GameplayEffectTypes.cpp:432 — 타입 판별 후 복원
TCheckedObjPtr<UScriptStruct> ScriptStruct = Data->GetScriptStruct();
UAbilitySystemGlobals::Get().EffectContextStructCache.NetSerialize(Ar, ScriptStruct.Get());
// 타입이 다르면 올바른 타입으로 재할당:
if (Data->GetScriptStruct() != ScriptStruct.Get())
{
    FGameplayEffectContext* NewData = (FGameplayEffectContext*)FMemory::Malloc(ScriptStruct->GetStructureSize());
    ScriptStruct->InitializeStruct(NewData);
    Data = TSharedPtr<FGameplayEffectContext>(NewData, ...);
}
```

그래서 서브클래스를 만들 때 반드시 `GetScriptStruct()`를 오버라이드해야 한다 — 이게 없으면 Handle이 타입을 구분하지 못해 기본 타입으로 역직렬화된다.

---

### Lyra 서브클래싱 — FLyraGameplayEffectContext

> 소스: `LyraGameplayEffectContext.h`, `LyraGameplayEffectContext.cpp`, `LyraAbilitySystemGlobals.cpp:16`

Lyra는 `FGameplayEffectContext`를 `FLyraGameplayEffectContext`로 서브클래싱해서 두 가지 필드를 추가했다.

```cpp
// LyraGameplayEffectContext.h:64
UPROPERTY()
int32 CartridgeID = -1;         // 같은 탄창에서 나온 탄들 식별용

TWeakObjectPtr<const UObject> AbilitySourceObject;  // ILyraAbilitySourceInterface 구현체 (복제 안 됨)
```

**CartridgeID**: 샷건처럼 한 발사에서 여러 발이 나갈 때, 같은 탄창에서 나온 탄임을 식별하기 위한 ID. 단, NetSerialize에서 명시적으로 직렬화하지 않는다 — 복제 없이 로컬에서만 쓰인다.

```cpp
// LyraGameplayEffectContext.cpp:27 — CartridgeID 직렬화 안 함
bool FLyraGameplayEffectContext::NetSerialize(...)
{
    FGameplayEffectContext::NetSerialize(Ar, Map, bOutSuccess);
    // Not serialized for post-activation use: CartridgeID
    return true;
}
```

**AbilitySourceObject**: 무기나 장비 같은 `ILyraAbilitySourceInterface` 구현체를 참조한다. 데미지 계산 시 무기 고유 배율 등을 꺼내오는 데 사용한다. 이것도 복제 안 됨 — 서버에서만 의미 있다.

Lyra의 서브클래싱 패턴을 보면 GASDoc에서 말하는 6단계를 전부 지킨다:

| 단계 | Lyra 구현 |
|---|---|
| `FGameplayEffectContext` 서브클래스 | `FLyraGameplayEffectContext` |
| `GetScriptStruct()` 오버라이드 | `return FLyraGameplayEffectContext::StaticStruct()` |
| `Duplicate()` 오버라이드 | `new FLyraGameplayEffectContext()` + HitResult 딥카피 |
| `NetSerialize()` 오버라이드 | `Super::NetSerialize()` 호출 후 추가 필드 처리 |
| `TStructOpsTypeTraits` 구현 | `WithNetSerializer = true, WithCopy = true` |
| `AllocGameplayEffectContext()` 오버라이드 | `ULyraAbilitySystemGlobals::AllocGameplayEffectContext()` → `new FLyraGameplayEffectContext()` |

`ExtractEffectContext()`는 Handle에서 안전하게 서브클래스 포인터를 꺼내는 헬퍼 패턴이다:

```cpp
// LyraGameplayEffectContext.cpp:16
FGameplayEffectContext* BaseEffectContext = Handle.Get();
if (BaseEffectContext && BaseEffectContext->GetScriptStruct()->IsChildOf(FLyraGameplayEffectContext::StaticStruct()))
    return (FLyraGameplayEffectContext*)BaseEffectContext;
return nullptr;
```

`GetScriptStruct()->IsChildOf()`로 타입을 검사한 뒤 C 스타일 캐스트로 꺼낸다. RTTI 없이 UScriptStruct 계층으로 타입 안전성을 보장하는 GAS 관용 패턴이다.
