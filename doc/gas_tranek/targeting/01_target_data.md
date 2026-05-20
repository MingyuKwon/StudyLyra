# Target Data

> **GASDoc**: 4.11.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting"></a>
### GAS에서 타게팅이란 무엇이며 FGameplayAbilityTargetData의 역할은?

<a name="concepts-targeting-data"></a>
#### FGameplayAbilityTargetData를 서브클래싱할 때 반드시 구현해야 하는 것은 무엇인가?

[`FGameplayAbilityTargetData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/FGameplayAbilityTargetData/index.html)는 네트워크를 통해 전달하기 위한 범용 타게팅 데이터 구조체다. `TargetData`는 일반적으로 `AActor`/`UObject` 레퍼런스, `FHitResult`, 그 외 일반적인 위치/방향/원점 정보를 담는다. 그러나 서브클래싱을 통해 원하는 거의 모든 데이터를 넣을 수 있으며, `GameplayAbility` 내에서 클라이언트와 서버 사이에 데이터를 전달하는 간단한 수단으로 활용된다. 기본 구조체 `FGameplayAbilityTargetData`는 직접 사용하는 것이 아니라 서브클래싱하여 사용한다. `GAS`는 `GameplayAbilityTargetTypes.h`에 기본 제공하는 `FGameplayAbilityTargetData` 서브클래스 구조체들을 포함하고 있다.

`TargetData`는 일반적으로 `Target Actors`가 생성하거나 **수동으로 생성**되며, `AbilityTasks` 및 `GameplayEffects`에서 `EffectContext`를 통해 소비된다. `EffectContext`에 들어가 있기 때문에, `Executions`, `MMCs`, `GameplayCues`, 그리고 `AttributeSet` 백엔드 함수들이 `TargetData`에 접근할 수 있다.

우리는 보통 `FGameplayAbilityTargetData`를 직접 전달하지 않고, 대신 내부에 `FGameplayAbilityTargetData` 포인터의 `TArray`를 가진 [`FGameplayAbilityTargetDataHandle`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/FGameplayAbilityTargetDataHandle/index.html)을 사용한다. 이 중간 구조체는 `TargetData`의 다형성(polymorphism)을 지원한다.

`FGameplayAbilityTargetData` 서브클래싱 예시:
```c++
USTRUCT(BlueprintType)
struct MYGAME_API FGameplayAbilityTargetData_CustomData : public FGameplayAbilityTargetData
{
    GENERATED_BODY()
public:

    FGameplayAbilityTargetData_CustomData()
    { }

    UPROPERTY()
    FName CoolName = NAME_None;

    UPROPERTY()
    FPredictionKey MyCoolPredictionKey;

    // This is required for all child structs of FGameplayAbilityTargetData
    virtual UScriptStruct* GetScriptStruct() const override
    {
    	return FGameplayAbilityTargetData_CustomData::StaticStruct();
    }

	// This is required for all child structs of FGameplayAbilityTargetData
    bool NetSerialize(FArchive& Ar, class UPackageMap* Map, bool& bOutSuccess)
    {
	    // The engine already defined NetSerialize for FName & FPredictionKey, thanks Epic!
        CoolName.NetSerialize(Ar, Map, bOutSuccess);
        MyCoolPredictionKey.NetSerialize(Ar, Map, bOutSuccess);
        bOutSuccess = true;
        return true;
    }
}

template<>
struct TStructOpsTypeTraits<FGameplayAbilityTargetData_CustomData> : public TStructOpsTypeTraitsBase2<FGameplayAbilityTargetData_CustomData>
{
	enum
	{
        WithNetSerializer = true // This is REQUIRED for FGameplayAbilityTargetDataHandle net serialization to work
	};
};
```
핸들에 TargetData를 추가하는 예시:
```c++
UFUNCTION(BlueprintPure)
FGameplayAbilityTargetDataHandle MakeTargetDataFromCustomName(const FName CustomName)
{
	// Create our target data type, 
	// Handle's automatically cleanup and delete this data when the handle is destructed, 
	// if you don't add this to a handle then be careful because this deals with memory management and memory leaks so its safe to just always add it to a handle at some point in the frame!
	FGameplayAbilityTargetData_CustomData* MyCustomData = new FGameplayAbilityTargetData_CustomData();
	// Setup the struct's information to use the inputted name and any other changes we may want to do
	MyCustomData->CoolName = CustomName;
	
	// Make our handle wrapper for Blueprint usage
	FGameplayAbilityTargetDataHandle Handle;
	// Add the target data to our handle
	Handle.Add(MyCustomData);
	// Output our handle to Blueprint
	return Handle
}
```

핸들에서 값을 꺼낼 때는 타입 안전성 검사가 필요하다. 핸들의 TargetData에서 값을 가져오는 유일한 방법은 타입 안전하지 않은 일반 C/C++ 캐스팅을 사용하는 것인데, 이는 object slicing과 크래시를 유발할 수 있다. 타입 체크 방법은 여러 가지가 있으며, 대표적인 두 가지는 다음과 같다:
- **Gameplay Tag 사용**: 특정 코드 아키텍처의 기능이 실행될 때마다 기본 부모 타입으로 캐스팅하고 그 Gameplay Tag를 가져온 뒤, 이를 상속된 클래스로의 캐스팅 여부를 비교하는 서브클래스 계층 구조를 사용할 수 있다.
- **Script Struct & Static Struct 사용**: 직접적인 클래스 비교를 수행할 수 있다(많은 IF 문이나 템플릿 함수 작성이 필요할 수 있음). 기본적으로 어떤 `FGameplayAbilityTargetData`에서도 Script Struct를 얻어 원하는 타입인지 비교할 수 있다(이는 `USTRUCT`이고, 상속된 모든 클래스가 `GetScriptStruct`에서 구조체 타입을 명시해야 한다는 점에서 이점이 있다). 타입 체크에 이러한 함수를 활용하는 예시:
```c++
UFUNCTION(BlueprintPure)
FName GetCoolNameFromTargetData(const FGameplayAbilityTargetDataHandle& Handle, const int Index)
{   
    // NOTE, there is two versions of this '::Get(int32 Index)' function; 
    // 1) const version that returns 'const FGameplayAbilityTargetData*', good for reading target data values 
    // 2) non-const version that returns 'FGameplayAbilityTargetData*', good for modifying target data values
    FGameplayAbilityTargetData* Data = Handle.Get(Index); // This will valid check the index for you 
    
    // Valid check we have something to use, null data means nothing to cast for
    if(Data == nullptr)
    {
       	return NAME_None;
    }
    // This is basically the type checking pass, static_cast does not have type safety, this is why we do this check.
    // If we don't do this then it will object slice the struct and thus we have no way of making sure its that type.
    if(Data->GetScriptStruct() == FGameplayAbilityTargetData_CustomData::StaticStruct())
    {
        // Here is when you would do the cast because we know its the correct type already
        FGameplayAbilityTargetData_CustomData* CustomData = static_cast<FGameplayAbilityTargetData_CustomData*>(Data);    
        return CustomData->CoolName;
    }
    return NAME_None;
}
```

---

### TargetData를 직접 RPC로 대체하지 못하는 이유는 무엇인가?

TargetData가 RPC를 *대체*하는 게 아니라, **RPC를 쓰면서도 GAS 파이프라인 전체에 데이터를 흘려보내야 하는 문제**를 해결하는 구조다.

#### 이유 1 — EffectContext에 끼워져야 한다

GE를 Apply할 때 `FGameplayEffectContextHandle`이 함께 전달되며, ExecCalc / MMC / GameplayCue / AttributeSet의 `PostGameplayEffectExecute`가 전부 이 Context에서 데이터를 꺼낸다.

```
GA → ApplyGameplayEffect → FGameplayEffectSpec (Context 포함)
                                ↓
               ExecCalc / MMC / GameplayCue / AttributeSet 콜백
```

직접 RPC로 쏜 데이터는 Context 안에 없으므로, 히트 결과·발사 위치 같은 정보를 Execution이나 GameplayCue에서 꺼낼 방법이 없다.

#### 이유 2 — Prediction Key와 묶여야 한다

클라이언트가 어빌리티를 예측(predict)하면 PredictionKey가 발급된다. TargetData는 이 Key와 함께 `ServerSetReplicatedTargetData` RPC로 전송되고, 서버가 Key를 기준으로 확정/롤백을 처리한다. 직접 RPC를 만들면 이 타이밍 조율(어빌리티 활성 여부, 롤백 윈도우, 중복 방지 등)을 전부 수동으로 구현해야 한다.

#### 이유 3 — AbilityTask가 RPC를 대신 써준다

`WaitTargetData` AbilityTask를 쓰면 내부에서 `ServerSetReplicatedTargetData` RPC를 자동으로 호출한다. 개발자는 RPC 코드를 직접 작성할 필요 없이 **TargetData 구조체만 정의**하면 된다.

#### 비교 요약

| | 직접 RPC | TargetData |
|---|---|---|
| EffectContext 연동 | ❌ 수동 연결 | ✅ 자동 |
| Prediction 지원 | ❌ 수동 구현 | ✅ PredictionKey 내장 |
| RPC 코드 작성 | 직접 써야 함 | Task가 대신 씀 |
| GE / Exec / Cue 접근 | ❌ 불가 | ✅ Context 통해 접근 |

TargetData 자체는 결국 RPC로 전송되지만, GAS 파이프라인의 나머지 단계(GE Apply, ExecCalc, GameplayCue, AttributeSet 콜백)가 이 구조체를 **기본으로 기대**하기 때문에, 우회하면 그 연결을 전부 수동으로 재구현해야 한다.

---

### Lyra의 원거리 무기 사격에서 TargetData는 어떤 흐름으로 생성·전송·적용되는가?

원거리 무기(`ULyraGameplayAbility_RangedWeapon`)가 TargetData를 주고받는 전 과정이다.

#### Lyra는 왜 FGameplayAbilityTargetData를 서브클래싱하여 CartridgeID를 추가했는가?

`AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h`

```cpp
USTRUCT()
struct FLyraGameplayAbilityTargetData_SingleTargetHit
    : public FGameplayAbilityTargetData_SingleTargetHit  // 엔진 기본 타입 확장
{
    GENERATED_BODY()

    // 같은 탄창에서 발사된 여러 총알을 묶는 ID (산탄총 등)
    UPROPERTY()
    int32 CartridgeID = -1;

    // TargetData → EffectContext로 데이터를 복사하는 오버라이드
    virtual void AddTargetDataToContext(FGameplayEffectContextHandle& Context,
                                        bool bIncludeActorArray) const override;

    bool NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess);

    virtual UScriptStruct* GetScriptStruct() const override
    {
        return FLyraGameplayAbilityTargetData_SingleTargetHit::StaticStruct();
    }
};

// 핸들 직렬화에 필수
template<>
struct TStructOpsTypeTraits<FLyraGameplayAbilityTargetData_SingleTargetHit>
    : public TStructOpsTypeTraitsBase2<FLyraGameplayAbilityTargetData_SingleTargetHit>
{
    enum { WithNetSerializer = true };
};
```

**포인트**: 엔진 제공 `FGameplayAbilityTargetData_SingleTargetHit`(HitResult 포함)를 상속해서 `CartridgeID`만 추가했다.

#### AddTargetDataToContext()는 어떤 역할을 하며 커스텀 Context에 데이터를 어떻게 주입하는가?

`LyraGameplayAbilityTargetData_SingleTargetHit.cpp`

```cpp
void FLyraGameplayAbilityTargetData_SingleTargetHit::AddTargetDataToContext(
    FGameplayEffectContextHandle& Context, bool bIncludeActorArray) const
{
    // 부모 호출 — HitResult, Actor 배열 등 기본 데이터 복사
    FGameplayAbilityTargetData_SingleTargetHit::AddTargetDataToContext(Context, bIncludeActorArray);

    // Lyra 전용 Context 타입으로 꺼낸 뒤 CartridgeID 주입
    if (FLyraGameplayEffectContext* TypedContext =
            FLyraGameplayEffectContext::ExtractEffectContext(Context))
    {
        TypedContext->CartridgeID = CartridgeID;
    }
}
```

GE가 Apply될 때 이 함수가 호출되어, CartridgeID가 EffectContext 안으로 들어간다.  
이후 ExecCalc / GameplayCue / AttributeSet 콜백에서 `FLyraGameplayEffectContext::ExtractEffectContext()`로 꺼낼 수 있다.

#### 클라이언트에서 로컬 레이캐스트 결과를 TargetDataHandle로 패킹하는 방법은?

`Weapons/LyraGameplayAbility_RangedWeapon.cpp` — `StartRangedWeaponTargeting()`

```cpp
void ULyraGameplayAbility_RangedWeapon::StartRangedWeaponTargeting()
{
    // 로컬(클라이언트)에서 레이캐스트 실행
    TArray<FHitResult> FoundHits;
    PerformLocalTargeting(/*out*/ FoundHits);

    // HitResult 배열을 TargetDataHandle로 패킹
    FGameplayAbilityTargetDataHandle TargetData;
    TargetData.UniqueId = WeaponStateComponent->GetUnconfirmedServerSideHitMarkerCount();

    const int32 CartridgeID = FMath::Rand();  // 같은 발사 묶음 식별자

    for (const FHitResult& FoundHit : FoundHits)
    {
        FLyraGameplayAbilityTargetData_SingleTargetHit* NewTargetData =
            new FLyraGameplayAbilityTargetData_SingleTargetHit();
        NewTargetData->HitResult = FoundHit;
        NewTargetData->CartridgeID = CartridgeID;  // 산탄총이면 전부 같은 ID

        TargetData.Add(NewTargetData);  // 핸들이 메모리 소유권 가져감
    }

    // 콜백으로 바로 넘김 (Task 없이 수동 처리)
    OnTargetDataReadyCallback(TargetData, FGameplayTag());
}
```

#### 클라이언트가 서버로 TargetData를 전송하고 GE를 적용하는 흐름은 어떻게 되는가?

`OnTargetDataReadyCallback()` — 클라이언트와 서버 양쪽에서 실행된다.

```cpp
void ULyraGameplayAbility_RangedWeapon::OnTargetDataReadyCallback(
    const FGameplayAbilityTargetDataHandle& InData, FGameplayTag ApplicationTag)
{
    FScopedPredictionWindow ScopedPrediction(MyAbilityComponent);

    FGameplayAbilityTargetDataHandle LocalTargetDataHandle(
        MoveTemp(const_cast<FGameplayAbilityTargetDataHandle&>(InData)));

    // 클라이언트(로컬 컨트롤러, 비-Authority)면 서버로 RPC 전송
    const bool bShouldNotifyServer =
        CurrentActorInfo->IsLocallyControlled() && !CurrentActorInfo->IsNetAuthority();

    if (bShouldNotifyServer)
    {
        MyAbilityComponent->CallServerSetReplicatedTargetData(
            CurrentSpecHandle,
            CurrentActivationInfo.GetActivationPredictionKey(),  // PredictionKey와 묶음
            LocalTargetDataHandle,
            ApplicationTag,
            MyAbilityComponent->ScopedPredictionKey);
    }

    // 탄약 소모 및 GE 적용 (Blueprint에서 OnRangedWeaponTargetDataReady 구현)
    if (CommitAbility(CurrentSpecHandle, CurrentActorInfo, CurrentActivationInfo))
    {
        OnRangedWeaponTargetDataReady(LocalTargetDataHandle);  // Blueprint 이벤트
    }

    // 처리 완료 후 ASC 내부 캐시 정리
    MyAbilityComponent->ConsumeClientReplicatedTargetData(
        CurrentSpecHandle, CurrentActivationInfo.GetActivationPredictionKey());
}
```

#### TargetData 콜백은 ActivateAbility에서 어떻게 등록하고 EndAbility에서 어떻게 정리하는가?

```cpp
void ULyraGameplayAbility_RangedWeapon::ActivateAbility(...)
{
    // TargetData가 도착하면 OnTargetDataReadyCallback 호출되도록 구독
    OnTargetDataReadyCallbackDelegateHandle =
        MyAbilityComponent->AbilityTargetDataSetDelegate(
            CurrentSpecHandle,
            CurrentActivationInfo.GetActivationPredictionKey()
        ).AddUObject(this, &ThisClass::OnTargetDataReadyCallback);
    // ...
}

void ULyraGameplayAbility_RangedWeapon::EndAbility(...)
{
    // 구독 해제 + 서버 캐시 정리
    MyAbilityComponent->AbilityTargetDataSetDelegate(
        CurrentSpecHandle, CurrentActivationInfo.GetActivationPredictionKey()
    ).Remove(OnTargetDataReadyCallbackDelegateHandle);

    MyAbilityComponent->ConsumeClientReplicatedTargetData(
        CurrentSpecHandle, CurrentActivationInfo.GetActivationPredictionKey());
    // ...
}
```

#### 클라이언트→서버 TargetData 전체 흐름을 한 눈에 보면?

```
[클라이언트]
ActivateAbility()
  → AbilityTargetDataSetDelegate 구독
  → StartRangedWeaponTargeting()
      → PerformLocalTargeting() — 레이캐스트
      → FLyraGameplayAbilityTargetData_SingleTargetHit 생성 (HitResult + CartridgeID)
      → TargetDataHandle.Add(...)
      → OnTargetDataReadyCallback() 직접 호출
          → CallServerSetReplicatedTargetData() — 서버 RPC (PredictionKey 포함)
          → OnRangedWeaponTargetDataReady() — Blueprint에서 GE Apply

[서버]
ServerSetReplicatedTargetData() 수신
  → AbilityTargetDataSetDelegate.Broadcast()
      → OnTargetDataReadyCallback()
          → GE Apply 시 AddTargetDataToContext() 호출
              → CartridgeID → FLyraGameplayEffectContext 주입
          → ExecCalc / GameplayCue / AttributeSet 콜백에서 Context로 꺼내 사용
```

**핵심**: `WaitTargetData` Task를 쓰지 않고 직접 `AbilityTargetDataSetDelegate`를 구독하는 방식이다. Task 없이 수동으로 처리하는 패턴으로, TargetData 전송 타이밍을 GA가 직접 제어한다.

---

### TargetData와 FGameplayEffectContext의 관계는 어떻게 되는가?

#### TargetData가 GE 파이프라인에서 Context로 이전되는 시점은 언제인가?

TargetData는 주로 두 가지 목적으로 사용된다.

1. **GA 코드에서 직접 읽기** — GE Apply 이전에 GA가 Handle을 직접 순회해 게임 로직 처리
2. **Context로 이전** — `ApplyGameplayEffect` 직전에 `AddTargetDataToContext()`가 호출되어 데이터가 Context에 복사됨

GE 파이프라인에 진입하는 순간부터는 TargetData Handle은 소비되고, **Context만이 ExecCalc / MMC / GameplayCue / AttributeSet 콜백까지 따라다닌다**.

```
TargetData (클라↔서버 전송, GA 로직)
    ↓ AddTargetDataToContext()
FGameplayEffectContext (GE 파이프라인 전체를 따라다니는 운반체)
    ↓
ExecCalc / MMC / GameplayCue / AttributeSet 콜백
```

#### 커스텀 FGameplayEffectContext가 필요한 기준은 무엇인가?

`FGameplayEffectContext`는 이미 `HitResult`와 `Actors` 배열을 지원한다. TargetData가 이 필드만 주입하면 커스텀 Context 없이 동작한다.

**커스텀 Context가 필요한 기준은 딱 하나**: 기본 Context에 없는 새 필드를 GE 파이프라인 안까지 흘려야 할 때다.

| 상황 | 커스텀 TargetData | 커스텀 Context |
|---|---|---|
| HitResult + Actor만 필요 | 불필요 | 불필요 |
| 새 필드를 GA 코드에서만 쓸 때 | 필요 | **불필요** |
| 새 필드를 ExecCalc/Cue까지 흘릴 때 | 필요 | **필요** |

Lyra가 `CartridgeID`를 위해 `FLyraGameplayEffectContext`를 만든 것이 세 번째 케이스다.

#### 커스텀 TargetData와 커스텀 Context는 반드시 1:1로 대응해야 하는가?

Context는 TargetData가 주입하는 **대상**일 뿐이다. 여러 TargetData 타입이 같은 커스텀 Context에 주입할 수도 있고, 커스텀 TargetData가 기본 Context를 그대로 쓸 수도 있다. 커스텀 Context 한 개를 공유하면서 다양한 TargetData 타입이 각자의 `AddTargetDataToContext()`를 통해 같은 Context에 데이터를 채워 넣는 구조가 일반적이다.

---

### LyraDamageExecution에서 TargetData에서 흘러온 HitResult를 데미지 계산에 어떻게 활용하는가?

`LyraDamageExecution::Execute_Implementation()`은 Context에서 HitResult를 꺼내 세 가지 계산에 사용한다. TargetData를 들고 오지 않으면 이 계산들이 전부 폴백값으로 떨어진다.

```cpp
FLyraGameplayEffectContext* TypedContext =
    FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext());

const FHitResult* HitActorResult = TypedContext->GetHitResult();  // TargetData에서 흘러온 것
```

#### HitResult는 LyraDamageExecution에서 피격 대상과 위치를 어떻게 특정하는 데 쓰이는가?

```cpp
HitActor       = CurHitResult.HitObjectHandle.FetchActor();
ImpactLocation = CurHitResult.ImpactPoint;
```

HitResult가 없으면 `TargetASC->GetAvatarActor()` 위치로 폴백한다.

#### HitResult의 ImpactPoint는 거리 감쇠 계산에 어떻게 사용되는가?

```cpp
Distance = FVector::Dist(TypedContext->GetOrigin(), ImpactLocation);
DistanceAttenuation = AbilitySource->GetDistanceAttenuation(Distance, SourceTags, TargetTags);
```

발사 기원점 ~ 피격 지점 거리를 계산해 원거리일수록 데미지를 줄인다.

#### HitResult의 PhysicalMaterial은 헤드샷 등 재질별 감쇠를 어떻게 결정하는가?

```cpp
const UPhysicalMaterial* PhysMat = TypedContext->GetPhysicalMaterial(); // HitResult 내부
PhysicalMaterialAttenuation = AbilitySource->GetPhysicalMaterialAttenuation(PhysMat, ...);
```

HitResult에 담긴 PhysicalMaterial로 머리·몸통·방어구 등 표면별 데미지 배율을 적용한다.

#### Lyra의 최종 데미지 공식은 어떻게 구성되는가?

```
DamageDone = BaseDamage
           × DistanceAttenuation          // 거리 감쇠
           × PhysicalMaterialAttenuation  // 재질 감쇠 (헤드샷 등)
           × DamageInteractionAllowedMultiplier  // 팀킬 방지 (0 or 1)
```

#### 클라이언트 레이캐스트부터 최종 데미지 적용까지 흐름을 요약하면?

```
[클라이언트 레이캐스트]
  FHitResult (ImpactPoint, PhysicalMaterial, HitActor)
    ↓ TargetData에 담김
    ↓ AddTargetDataToContext()
  FLyraGameplayEffectContext.HitResult
    ↓ GE Apply → LyraDamageExecution
      → ImpactLocation  → 거리 계산 → DistanceAttenuation
      → PhysicalMaterial → 재질 판별 → PhysicalMaterialAttenuation
      → HitActor         → 팀킬 체크 → AllowedMultiplier
      → BaseDamage × 세 값 = 최종 데미지
```
