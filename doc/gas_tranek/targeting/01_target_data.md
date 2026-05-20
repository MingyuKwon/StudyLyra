# Target Data

> **GASDoc**: 4.11.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting"></a>
### GAS에서 타게팅이란 무엇이며 FGameplayAbilityTargetData의 역할은?

타게팅은 어빌리티가 영향을 미칠 대상(Actor, 위치, HitResult 등)을 결정하고, 그 정보를 클라이언트-서버 간에 전달하는 메커니즘이다. `FGameplayAbilityTargetData`가 이 데이터를 담는 구조체이며, GAS 파이프라인(GE Apply, ExecCalc, GameplayCue, AttributeSet 콜백) 전체에 데이터를 흘려보내는 역할을 한다.

<a name="concepts-targeting-data"></a>
#### FGameplayAbilityTargetData를 서브클래싱할 때 반드시 구현해야 하는 것은 무엇인가?

`FGameplayAbilityTargetData`는 직접 사용하지 않고 서브클래싱하여 사용한다. 서브클래스 구현 시 반드시 필요한 두 가지:
1. `GetScriptStruct()` 오버라이드 — 타입 안전성 검사에 필요
2. `NetSerialize()` 구현 + `TStructOpsTypeTraits`에 `WithNetSerializer = true` 선언 — 핸들 직렬화에 필수

```c++
USTRUCT(BlueprintType)
struct MYGAME_API FGameplayAbilityTargetData_CustomData : public FGameplayAbilityTargetData
{
    GENERATED_BODY()
public:

    UPROPERTY()
    FName CoolName = NAME_None;

    UPROPERTY()
    FPredictionKey MyCoolPredictionKey;

    virtual UScriptStruct* GetScriptStruct() const override
    {
        return FGameplayAbilityTargetData_CustomData::StaticStruct();
    }

    bool NetSerialize(FArchive& Ar, class UPackageMap* Map, bool& bOutSuccess)
    {
        CoolName.NetSerialize(Ar, Map, bOutSuccess);
        MyCoolPredictionKey.NetSerialize(Ar, Map, bOutSuccess);
        bOutSuccess = true;
        return true;
    }
};

template<>
struct TStructOpsTypeTraits<FGameplayAbilityTargetData_CustomData> : public TStructOpsTypeTraitsBase2<FGameplayAbilityTargetData_CustomData>
{
    enum { WithNetSerializer = true };
};
```

핸들에 TargetData를 추가할 때는 `new`로 생성한 포인터를 `Handle.Add()`에 넘긴다. 핸들이 메모리 소유권을 가져간다:

```c++
FGameplayAbilityTargetData_CustomData* MyCustomData = new FGameplayAbilityTargetData_CustomData();
MyCustomData->CoolName = CustomName;

FGameplayAbilityTargetDataHandle Handle;
Handle.Add(MyCustomData);
```

핸들에서 꺼낼 때는 반드시 `GetScriptStruct()`로 타입을 확인한 뒤 `static_cast`한다:

```c++
FGameplayAbilityTargetData* Data = Handle.Get(Index);
if (Data && Data->GetScriptStruct() == FGameplayAbilityTargetData_CustomData::StaticStruct())
{
    FGameplayAbilityTargetData_CustomData* CustomData = static_cast<FGameplayAbilityTargetData_CustomData*>(Data);
    return CustomData->CoolName;
}
```

---

### TargetData를 직접 RPC로 대체하지 못하는 이유는 무엇인가?

직접 RPC는 GAS 파이프라인 연결을 전부 수동으로 재구현해야 한다.

| | 직접 RPC | TargetData |
|---|---|---|
| EffectContext 연동 | 수동 연결 필요 | 자동 |
| Prediction 지원 | 수동 구현 필요 | PredictionKey 내장 |
| RPC 코드 작성 | 직접 써야 함 | AbilityTask가 대신 씀 |
| GE / Exec / Cue 접근 | 불가 | Context 통해 접근 |

GE를 Apply할 때 `FGameplayEffectContextHandle`이 함께 전달되고, ExecCalc / MMC / GameplayCue / AttributeSet의 `PostGameplayEffectExecute`가 모두 이 Context에서 데이터를 꺼낸다. 직접 RPC로 쏜 데이터는 Context 안에 없으므로 이 연결이 끊긴다. 또한 TargetData는 PredictionKey와 함께 `ServerSetReplicatedTargetData` RPC로 전송되어 타이밍 조율(확정/롤백)이 자동으로 처리된다.

---

### Lyra의 원거리 무기 사격에서 TargetData는 어떤 흐름으로 생성·전송·적용되는가?

#### Lyra는 왜 FGameplayAbilityTargetData를 서브클래싱하여 CartridgeID를 추가했는가?

엔진 기본 타입 `FGameplayAbilityTargetData_SingleTargetHit`(HitResult 포함)를 상속해 `CartridgeID`만 추가했다. CartridgeID는 산탄총처럼 같은 탄창에서 발사된 여러 총알을 묶는 식별자다.

```cpp
USTRUCT()
struct FLyraGameplayAbilityTargetData_SingleTargetHit
    : public FGameplayAbilityTargetData_SingleTargetHit
{
    UPROPERTY()
    int32 CartridgeID = -1;

    virtual void AddTargetDataToContext(FGameplayEffectContextHandle& Context,
                                        bool bIncludeActorArray) const override;

    bool NetSerialize(FArchive& Ar, UPackageMap* Map, bool& bOutSuccess);

    virtual UScriptStruct* GetScriptStruct() const override
    {
        return FLyraGameplayAbilityTargetData_SingleTargetHit::StaticStruct();
    }
};
```

#### AddTargetDataToContext()는 어떤 역할을 하며 커스텀 Context에 데이터를 어떻게 주입하는가?

GE가 Apply될 때 호출되어 TargetData의 데이터를 EffectContext로 복사한다. Lyra는 여기서 `CartridgeID`를 `FLyraGameplayEffectContext`에 주입한다:

```cpp
void FLyraGameplayAbilityTargetData_SingleTargetHit::AddTargetDataToContext(
    FGameplayEffectContextHandle& Context, bool bIncludeActorArray) const
{
    FGameplayAbilityTargetData_SingleTargetHit::AddTargetDataToContext(Context, bIncludeActorArray);

    if (FLyraGameplayEffectContext* TypedContext =
            FLyraGameplayEffectContext::ExtractEffectContext(Context))
    {
        TypedContext->CartridgeID = CartridgeID;
    }
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

Lyra는 `WaitTargetData` Task를 쓰지 않고 `AbilityTargetDataSetDelegate`에 직접 등록하는 방식이다. Task 없이 수동으로 처리하여 TargetData 전송 타이밍을 GA가 직접 제어한다.

---

### TargetData와 FGameplayEffectContext의 관계는 어떻게 되는가?

#### TargetData가 GE 파이프라인에서 Context로 이전되는 시점은 언제인가?

`ApplyGameplayEffect` 직전에 `AddTargetDataToContext()`가 호출되어 데이터가 Context에 복사된다. GE 파이프라인에 진입하는 순간부터는 TargetData Handle은 소비되고, Context만이 ExecCalc / MMC / GameplayCue / AttributeSet 콜백까지 따라다닌다.

```
TargetData (클라↔서버 전송, GA 로직)
    ↓ AddTargetDataToContext()
FGameplayEffectContext (GE 파이프라인 전체를 따라다니는 운반체)
    ↓
ExecCalc / MMC / GameplayCue / AttributeSet 콜백
```

#### 커스텀 FGameplayEffectContext가 필요한 기준은 무엇인가?

기본 Context에 없는 새 필드를 GE 파이프라인 안까지 흘려야 할 때만 필요하다.

| 상황 | 커스텀 TargetData | 커스텀 Context |
|---|---|---|
| HitResult + Actor만 필요 | 불필요 | 불필요 |
| 새 필드를 GA 코드에서만 쓸 때 | 필요 | 불필요 |
| 새 필드를 ExecCalc/Cue까지 흘릴 때 | 필요 | 필요 |

Lyra가 `CartridgeID`를 위해 `FLyraGameplayEffectContext`를 만든 것이 세 번째 케이스다.

---

### LyraDamageExecution에서 TargetData에서 흘러온 HitResult를 데미지 계산에 어떻게 활용하는가?

`LyraDamageExecution::Execute_Implementation()`은 Context에서 HitResult를 꺼내 세 가지 계산에 사용한다:

- **피격 대상 특정**: `CurHitResult.HitObjectHandle.FetchActor()` — 없으면 `TargetASC->GetAvatarActor()` 위치로 폴백
- **거리 감쇠**: `FVector::Dist(TypedContext->GetOrigin(), ImpactLocation)` → `GetDistanceAttenuation()` — 원거리일수록 데미지 감소
- **재질 감쇠(헤드샷 등)**: `TypedContext->GetPhysicalMaterial()` → `GetPhysicalMaterialAttenuation()` — 표면별 데미지 배율

최종 데미지 공식:
```
DamageDone = BaseDamage
           × DistanceAttenuation
           × PhysicalMaterialAttenuation
           × DamageInteractionAllowedMultiplier  // 팀킬 방지 (0 or 1)
```
