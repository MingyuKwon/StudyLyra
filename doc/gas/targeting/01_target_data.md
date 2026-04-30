# Target Data

> **GASDoc**: 4.11.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-targeting"></a>
### 4.11 Targeting

<a name="concepts-targeting-data"></a>
#### 4.11.1 Target Data

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

## 내 분석

### TargetData가 필요한 이유 — 직접 RPC/Replicate로 대체하지 못하는 이유

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
