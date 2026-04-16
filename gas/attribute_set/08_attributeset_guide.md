# AttributeSet 완전 가이드

GAS 공식 문서 4.4 AttributeSet 섹션을 엔진 코드와 대조한 정리.

---

## 설계 전략 — 모놀리식 vs 분리형

### 모놀리식
모든 Actor가 하나의 거대한 AttributeSet을 공유. 쓰지 않는 Attribute는 그냥 무시.

```cpp
// 모든 캐릭터가 ManaSet도 들고 다님 (미니언도 포함)
class UAllInOneAttributeSet : public UAttributeSet
{
    FGameplayAttributeData Health;
    FGameplayAttributeData Mana;       // 미니언은 안 씀
    FGameplayAttributeData BaseDamage;
    // ...
};
```

### 분리형 (Lyra 방식)
필요한 것만 골라서 부여.

```
영웅: HealthSet + ManaSet + CombatSet
미니언: HealthSet + CombatSet         ← ManaSet 없음
```

**동일 클래스는 하나만 허용.**
`SpawnedAttributes.AddUnique(Set)` — 같은 클래스를 두 번 넣으면 두 번째는 무시된다.
ASC가 Attribute를 찾을 때 `GetAttributeSubobject(AttributeClass)`로 클래스 기준 첫 번째 인스턴스를 반환하기 때문.

### 서브클래싱
부모의 Attribute는 부모 클래스명을 접두사로 유지한다.

```cpp
class UBaseSet : public UAttributeSet { FGameplayAttributeData Health; };
class UHeroSet : public UBaseSet      { FGameplayAttributeData Mana;   };
```

```
내부 참조명:
  UBaseSet.Health   ← HeroSet으로 서브클래싱해도 여전히 UBaseSet.Health
  UHeroSet.Mana
```

---

## 서브 컴포넌트 패턴 (4.4.2.1)

Pawn에 독립적으로 피해를 받는 컴포넌트(갑옷 부위 등)가 여러 개 있을 때.

**핵심 문제:** ASC는 Actor당 하나다. 컴포넌트마다 Attribute를 따로 줄 수 없다.

**해결책 A — 슬롯 Attribute 미리 정의:**

```cpp
class UArmorAttributeSet : public UAttributeSet
{
    FGameplayAttributeData ArmorHealth0;  // 머리
    FGameplayAttributeData ArmorHealth1;  // 몸통
    FGameplayAttributeData ArmorHealth2;  // 다리
};
```

각 갑옷 컴포넌트 인스턴스가 "나는 슬롯 1번"이라는 정보를 들고, GA/ExecCalc에서 슬롯 번호 → Attribute로 매핑.

```
머리 피격 → GA: "슬롯 0" → GE가 ArmorHealth0 수정
몸통 피격 → GA: "슬롯 1" → GE가 ArmorHealth1 수정
```

슬롯보다 적은 컴포넌트가 있어도 문제없다. 쓰지 않는 Attribute는 메모리 낭비가 미미하다.

**해결책 B — 컴포넌트에 일반 float 직접 저장 (슬롯이 많을 때):**

GAS 없이 컴포넌트가 직접 `float` 보유. 탄약처럼 GE 워크플로가 꼭 필요하지 않으면 이 방식이 단순하다.

---

## 런타임 추가/제거 (4.4.2.2)

장비 장착/해제처럼 게임 중 AttributeSet을 동적으로 붙이고 뗄 수 있다.

```cpp
// 추가
AbilitySystemComponent->GetSpawnedAttributes_Mutable().AddUnique(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();

// 제거
AbilitySystemComponent->GetSpawnedAttributes_Mutable().Remove(WeaponAttributeSetPointer);
AbilitySystemComponent->ForceReplication();
```

> `GetSpawnedAttributes_Mutable()`은 UE 5.1부터 Deprecated.
> 대신 `AddAttributeSetSubobject()` / `RemoveSpawnedAttribute()` 사용 권장.

**크래시 위험:**
클라이언트가 서버보다 먼저 AttributeSet을 제거했을 때,
서버에서 해당 Attribute 변경이 복제되어 오면 클라이언트에서 AttributeSet을 못 찾아 크래시.

```
서버: Damage Attribute 변경 → 복제 시작
클라이언트: AttributeSet 이미 제거 → 복제 수신 시 크래시
```

---

## 아이템 Attribute 3가지 구현 방법 (4.4.2.3)

무기 탄약처럼 "아이템이 Attribute를 가지는" 경우의 구현 선택지.

### 방법 1. 아이템에 float 직접 저장 (권장)

GAS 없이 무기 클래스에 `float` 값으로 탄약 보관.

```cpp
// 무기 클래스
UPROPERTY(Replicated)
int32 CurrentAmmo;

UPROPERTY(Replicated)
int32 ReserveAmmo;
```

자동 사격 중 로컬 예측값이 서버 값으로 덮어씌워지는 걸 막으려면 `PreReplication()`에서 조건부 복제:

```cpp
void AGSWeapon::PreReplication(IRepChangedPropertyTracker& ChangedPropertyTracker)
{
    // 발사 중에는 탄약 복제 비활성화 (로컬 예측 유지)
    DOREPLIFETIME_ACTIVE_OVERRIDE(AGSWeapon, PrimaryClipAmmo,
        !AbilitySystemComponent->HasMatchingGameplayTag(WeaponIsFiringTag));
}
```

장점: AttributeSet 동일 클래스 제한 없음, 구현 단순
단점: Cost GE 등 GAS 워크플로 사용 불가. GA에서 float 기준으로 비용 직접 체크해야 함.

### 방법 2. 아이템에 별도 AttributeSet

무기마다 고유 AttributeSet 클래스를 만들고, 인벤토리 추가 시 ASC에 붙임.

```cpp
// 무기 BeginPlay에서 생성 (생성자에서 하면 컴파일 오류 가능)
void AGSWeapon::BeginPlay()
{
    if (!AttributeSet)
    {
        AttributeSet = NewObject<UGSWeaponAttributeSet>(this);
    }
}

// 인벤토리 추가 시
ASC->AddAttributeSetSubobject(Weapon->AttributeSet);
```

장점: Cost GE 등 GAS 워크플로 그대로 사용 가능
단점:
- 동일 클래스 하나 제한 → 같은 무기 종류를 두 개 인벤토리에 못 넣음
- AttributeSet 제거 타이밍 크래시 위험

### 방법 3. 아이템에 별도 ASC

아이템마다 ASC를 통째로 붙이는 극단적 방법. 실제 구현 사례 거의 없음. 엔지니어링 비용 미지수.

---

## Attribute 정의 패턴 (4.4.3)

### 복제되는 Attribute 선언 전체 패턴

**헤더 (.h):**

```cpp
// ① UPROPERTY + ReplicatedUsing
UPROPERTY(BlueprintReadOnly, Category = "Health", ReplicatedUsing = OnRep_Health)
FGameplayAttributeData Health;

// ② ATTRIBUTE_ACCESSORS로 4개 함수 자동 생성
ATTRIBUTE_ACCESSORS(UMyAttributeSet, Health)

// ③ OnRep 함수 선언
UFUNCTION()
void OnRep_Health(const FGameplayAttributeData& OldValue);
```

**소스 (.cpp):**

```cpp
// ④ OnRep 구현 — GAMEPLAYATTRIBUTE_REPNOTIFY 필수
void UMyAttributeSet::OnRep_Health(const FGameplayAttributeData& OldValue)
{
    GAMEPLAYATTRIBUTE_REPNOTIFY(UMyAttributeSet, Health, OldValue);
}

// ⑤ GetLifetimeReplicatedProps 등록
void UMyAttributeSet::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME_CONDITION_NOTIFY(UMyAttributeSet, Health, COND_None, REPNOTIFY_Always);
}
```

### GAMEPLAYATTRIBUTE_REPNOTIFY 내부 동작

`AttributeSet.h:403`

```cpp
#define GAMEPLAYATTRIBUTE_REPNOTIFY(ClassName, PropertyName, OldValue) \
{ \
    static FProperty* ThisProperty = FindFieldChecked<FProperty>(ClassName::StaticClass(), \
        GET_MEMBER_NAME_CHECKED(ClassName, PropertyName)); \
    GetOwningAbilitySystemComponentChecked()->SetBaseAttributeValueFromReplication( \
        FGameplayAttribute(ThisProperty), PropertyName, OldValue); \
}
```

단순히 값을 복제 수신하는 게 아니다.
`SetBaseAttributeValueFromReplication()`을 통해 **예측(Prediction)으로 미리 적용된 클라이언트 값을 서버 값으로 되감는(rewind)** 작업을 한다.

```
// GameplayEffect.cpp:3682
Aggregator->SetBaseValue(OldBaseValue, false);     // ① 서버의 이전 값으로 되감기
float OldEvaluatedValue = Aggregator->Evaluate();  // ② 이전 상태 평가
Aggregator->SetBaseValue(ServerBaseValue, false);  // ③ 서버 최신 값으로 설정
OnAttributeAggregatorDirty(...)                    // ④ 재계산 트리거
```

**REPNOTIFY_Always가 필요한 이유:**
기본값(`REPNOTIFY_OnChanged`)이면 예측으로 클라이언트가 이미 동일한 값을 들고 있을 때 OnRep이 호출되지 않는다.
`REPNOTIFY_Always`는 값이 같아도 항상 OnRep을 호출해서 서버 값으로 되감기를 보장한다.

### Meta Attribute는 OnRep 불필요

복제하지 않으므로 `OnRep`, `GetLifetimeReplicatedProps` 모두 생략.

```cpp
// 복제 없음 → OnRep 선언 없음, GetLifetimeReplicatedProps 등록 없음
UPROPERTY(BlueprintReadOnly, Category="Health", Meta=(HideFromModifiers))
FGameplayAttributeData Damage;
ATTRIBUTE_ACCESSORS(UMyAttributeSet, Damage)
```

---

## Attribute 초기화 (4.4.4)

### 방법 1. InitXxx() 직접 호출

`ATTRIBUTE_ACCESSORS`가 자동 생성한 `InitXxx()`를 사용.

```cpp
// 생성자에서
AttributeSet->InitHealth(100.0f);
// = Health.SetBaseValue(100.f); Health.SetCurrentValue(100.f);
```

### 방법 2. Instant GE 사용 (Epic 권장)

`GE_InitAttributes` 같은 Instant GE를 만들어서 Modifier로 초기값 설정.
`AbilitySet`의 `GrantedGameplayEffects`에 넣어두면 AttributeSet 부여 직후 자동 적용된다.

Epic이 이 방법을 권장하는 이유: 데이터 테이블이나 에디터에서 초기값을 조정할 수 있어서 C++ 재컴파일 없이 밸런스 조정 가능.

---

## PreAttributeChange (4.4.5)

`CurrentValue`가 변경되기 **직전** 호출. `NewValue`를 레퍼런스로 받아서 수정하면 Clamp 가능.

```cpp
void UMyAttributeSet::PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)
{
    if (Attribute == GetHealthAttribute())
    {
        NewValue = FMath::Clamp(NewValue, 0.f, GetMaxHealth());
    }
}
```

**⚠️ 중요한 함정**: 여기서 `NewValue`를 수정해도 **ASC Aggregator 안의 Modifier 값은 바뀌지 않는다.**

```
상황:
  BaseValue = 100, MaxHealth = 150
  Duration GE: Health += 200  (Aggregator Modifier로 저장됨)

PreAttributeChange 호출:
  NewValue = 300 → Clamp → NewValue = 150  ← 이 값이 CurrentValue에 들어감

하지만 Aggregator 안의 Modifier는 여전히 +200
→ Aggregator가 dirty 되어 재계산되면 300이 다시 나옴
→ PreAttributeChange가 다시 Clamp → 150

즉, Clamp가 매번 다시 적용되는 방식이지, 근본적으로 Modifier를 잘라내는 게 아님
```

`GameplayEffectExecutionCalculation`이나 `ModifierMagnitudeCalculation`에서 값을 계산할 때는
PreAttributeChange의 Clamp를 거치지 않으므로, 그쪽에서도 Clamp를 직접 구현해야 한다.

---

## PostGameplayEffectExecute (4.4.6)

**Instant GE**에 의해 Attribute의 `BaseValue`가 변경된 **직후** 호출.
(Duration/Infinite GE의 Modifier 재계산은 해당 없음)

```cpp
void UMyAttributeSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // 이 시점에 변경은 이미 적용됐지만 아직 클라이언트로 복제되지 않음
        // → 여기서 클램핑해도 네트워크 업데이트 2번 발생하지 않음
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), 0.f, GetMaxHealth()));
        SetDamage(0.f);
    }
}
```

`Data.EvaluatedData.Attribute` — 이번 GE가 수정한 Attribute.
`Data.EvaluatedData.Magnitude` — 적용된 크기 (Clamp 전 원본값).

---

## OnAttributeAggregatorCreated (4.4.7)

어떤 Attribute에 **처음으로 Duration/Infinite GE가 적용**되어 Aggregator가 생성되는 순간 호출된다.
`FAggregatorEvaluateMetaData`를 설정해서 Aggregator가 Modifier를 평가하는 방식을 커스터마이징한다.

**호출 위치** (`GameplayEffect.cpp:3368`):

```cpp
FAggregator* NewAttributeAggregator = new FAggregator(CurrentBaseValueOfProperty);
// OnDirty 델리게이트 등록 ...
const UAttributeSet* Set = Owner->GetAttributeSubobject(Attribute.GetAttributeSetClass());
Set->OnAttributeAggregatorCreated(Attribute, NewAttributeAggregator);  // ← 여기서 호출
```

### FAggregatorEvaluateMetaData 동작 원리

Aggregator는 `Evaluate()` 시 `EvaluateQualificationForAllMods()`를 먼저 실행한다.
각 Modifier의 `Qualifies()` 플래그를 먼저 결정한 뒤, 자격 있는 Modifier만 합산한다.

```
// GameplayEffectAggregator.cpp:421
void FAggregator::EvaluateQualificationForAllMods(...)
{
    ModChannels.EvaluateQualificationForAllMods(Parameters); // 기본 Tag 조건 평가
    if (EvaluationMetaData && EvaluationMetaData->CustomQualifiesFunc)
        EvaluationMetaData->CustomQualifiesFunc(Parameters, this); // 커스텀 필터 적용
}
```

### MostNegativeMod_AllPositiveMods 구현

`GameplayEffectAggregatorLibrary.cpp:9`

"느려짐 효과가 여러 개 쌓여도 가장 강한 것 하나만 적용, 버프는 모두 누적" — Paragon 방식.

```cpp
void QualifierFunc_MostNegativeMod_AllPositiveMods(...)
{
    const FAggregatorMod* MostNegativeMod = nullptr;
    float CurrentMostNegativeDelta = 0.f;

    Aggregator->ForEachMod([&](const FAggregatorModInfo& ModInfo)
    {
        float ExpectedDelta = /* ModOp에 따라 BaseValue 대비 변화량 계산 */;

        if (ExpectedDelta < 0.f)  // 감소 효과라면
        {
            ModInfo.Mod->SetExplicitQualifies(false);  // 일단 전부 비활성화

            if (ExpectedDelta < CurrentMostNegativeDelta)  // 가장 강한 것 추적
            {
                CurrentMostNegativeDelta = ExpectedDelta;
                MostNegativeMod = ModInfo.Mod;
            }
        }
        // 증가 효과는 건드리지 않음 → 기본 Qualifies 상태 유지
    });

    if (MostNegativeMod)
        MostNegativeMod->SetExplicitQualifies(true);  // 가장 강한 것만 다시 활성화
}

// 정적 인스턴스로 등록
FAggregatorEvaluateMetaData FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods(
    QualifierFunc_MostNegativeMod_AllPositiveMods);
```

### 사용 방법

```cpp
void UMyAttributeSet::OnAttributeAggregatorCreated(
    const FGameplayAttribute& Attribute, FAggregator* NewAggregator) const
{
    Super::OnAttributeAggregatorCreated(Attribute, NewAggregator);
    if (!NewAggregator) return;

    if (Attribute == GetMoveSpeedAttribute())
    {
        // 이 Attribute의 Aggregator에 커스텀 평가 규칙 적용
        NewAggregator->EvaluationMetaData =
            &FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods;
    }
}
```

결과:
```
이동속도 버프 +30%, +20%  → 둘 다 적용
이동속도 디버프 -40%, -20% → -40%만 적용 (-20%는 무시)
```
