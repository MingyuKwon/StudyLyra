# GAS — AttributeSet

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 2. AttributeSet 클래스 계층

```
UAttributeSet
  └─ ULyraAttributeSet           (AbilitySystem/Attributes/LyraAttributeSet.h)
        ├─ ULyraHealthSet         (AbilitySystem/Attributes/LyraHealthSet.h)
        └─ ULyraCombatSet         (AbilitySystem/Attributes/LyraCombatSet.h)
```

### ULyraAttributeSet — 베이스
- `GetWorld()` / `GetLyraAbilitySystemComponent()` 헬퍼만 추가
- `ATTRIBUTE_ACCESSORS` 매크로 정의 (4개 함수 생성: PropertyGetter / ValueGetter / ValueSetter / ValueInitter)

### ULyraHealthSet — 피격자 소유
Attributes:
- `Health` (replicated, `COND_None`, `HideFromModifiers`) — 복제됨
- `MaxHealth` (replicated, `COND_None`) — 복제됨
- `Damage` (Meta, `HideFromModifiers`, NOT replicated) — 서버 전용
- `Healing` (Meta, NOT replicated) — 서버 전용

멤버 변수:
- `bool bOutOfHealth` — 사망 중복 이벤트 방지 플래그
- `float HealthBeforeAttributeChange` / `MaxHealthBeforeAttributeChange` — Pre에서 스냅샷, Post에서 delta 계산용

델리게이트 (6파라미터: Instigator, Causer, EffectSpec*, Magnitude, OldValue, NewValue):
- `OnHealthChanged` / `OnMaxHealthChanged` / `OnOutOfHealth`

### ULyraCombatSet — 공격자 소유
Attributes:
- `BaseDamage` (replicated, `COND_OwnerOnly`) — Owner에게만 복제
- `BaseHeal` (replicated, `COND_OwnerOnly`)

---

## 3. AttributeSet 등록 방법

### 경로 A — CreateDefaultSubobject (항상 존재)
```cpp
// Player/LyraPlayerState.cpp ctor
HealthSet = CreateDefaultSubobject<ULyraHealthSet>(TEXT("HealthSet"));
CombatSet = CreateDefaultSubobject<ULyraCombatSet>(TEXT("CombatSet"));
```

자동 수집 코드 위치: `AbilitySystemComponent_Abilities.cpp:57` — `UAbilitySystemComponent::InitializeComponent()`

```cpp
// "Look for DSO AttributeSets" 주석과 함께
TArray<UObject*> ChildObjects;
GetObjectsWithOuter(Owner, ChildObjects, false /*재귀 없음*/, RF_NoFlags, EInternalObjectFlags::Garbage);

for (UObject* Obj : ChildObjects)
{
    UAttributeSet* Set = Cast<UAttributeSet>(Obj);
    if (Set)
        SpawnedAttributes.AddUnique(Set);  // ← 여기서 등록
}
```

동작 원리:
1. `CreateDefaultSubobject` → AttributeSet이 PlayerState의 서브오브젝트로 등록
2. ASC ctor에서 `bWantsInitializeComponent = true` 설정
3. 엔진이 `InitializeComponent()` 호출
4. `GetObjectsWithOuter(Owner)` 로 ASC Owner(PlayerState)의 직접 자식 오브젝트 전체 스캔
5. `UAttributeSet` 파생 클래스이면 `SpawnedAttributes`에 추가

### 경로 B — GiveToAbilitySystem (동적 부여/제거)
```cpp
// AbilitySystem/LyraAbilitySet.cpp
UAttributeSet* NewSet = NewObject<UAttributeSet>(LyraASC->GetOwner(), SetToGrant.AttributeSet);
LyraASC->AddAttributeSetSubobject(NewSet);
OutGrantedHandles->AddAttributeSet(NewSet);  // 제거용 핸들 저장
```
호출 시점 3곳:
1. `LyraPlayerState::OnExperienceLoaded` — PawnData.AbilitySets 순회
2. `LyraEquipmentManagerComponent::EquipItem` — 장비 장착
3. `GameFeatureAction_AddAbilities::AddActorAbilities` — GameFeature 활성화

제거: `FLyraAbilitySet_GrantedHandles::TakeFromAbilitySystem()` → `RemoveSpawnedAttribute()`

---

## 5. AttributeSet 콜백 체인

```
GE 적용
  │
  ├─ PreGameplayEffectExecute(Data) → false 반환 시 GE 취소 가능
  │     Lyra: 면역 태그(TAG_Gameplay_DamageImmunity) 체크, GodMode 치트 체크
  │     Lyra: HealthBeforeAttributeChange 스냅샷
  │
  ├─ PreAttributeBaseChange(Attribute, NewValue&) → NewValue 수정으로 Clamp
  │     Lyra: ClampAttribute() — Health [0, MaxHealth], MaxHealth [1, ∞]
  │
  ├─ PreAttributeChange(Attribute, NewValue&) → CurrentValue Clamp
  │     Lyra: 동일하게 ClampAttribute()
  │
  ├─ [실제 값 반영]
  │
  ├─ PostGameplayEffectExecute(Data) → Meta Attribute 소비
  │     Lyra Damage 처리:
  │       피격메시지 BroadcastMessage(TAG_Lyra_Damage_Message)
  │       SetHealth(Clamp(Health - Damage, min, MaxHealth))
  │       SetDamage(0.0f)
  │     Lyra Healing 처리:
  │       SetHealth(Clamp(Health + Healing, min, MaxHealth))
  │       SetHealing(0.0f)
  │     OnHealthChanged.Broadcast (HealthBeforeAttributeChange != GetHealth() 일 때만)
  │     OnOutOfHealth.Broadcast (Health<=0 && !bOutOfHealth 일 때만)
  │
  └─ PostAttributeChange(Attribute, OldValue, NewValue)
        Lyra: MaxHealth 감소 시 Health > NewMaxHealth 이면 ApplyModToAttribute(Override, NewMaxHealth)
        Lyra: bOutOfHealth 복구 감지 (Health > 0 되면 false로)
```

---

## 7. 외부 시스템 구독 패턴

```
ULyraHealthSet::OnHealthChanged
  └─▶ ULyraHealthComponent::HandleHealthChanged (InitializeWithAbilitySystem에서 바인딩)
        └─▶ ULyraHealthComponent::OnHealthChanged (HUD, GameMode 등이 구독)

ULyraHealthSet::OnOutOfHealth
  └─▶ ULyraHealthComponent::HandleOutOfHealth
        └─▶ 사망 GA 활성화 등
```

`LyraHealthComponent::InitializeWithAbilitySystem(ASC)`:
```
HealthSet = ASC->GetSet<ULyraHealthSet>()
HealthSet->OnHealthChanged.AddUObject(this, HandleHealthChanged)
ASC->SetNumericAttributeBase(GetHealthAttribute(), HealthSet->GetMaxHealth())  // TEMP 초기화
```

클라이언트 `OnRep_Health`에서도 `OnHealthChanged`/`OnOutOfHealth` 브로드캐스트 (인자는 nullptr).

---

## 8. Clamp 처리 요약

| 콜백 | 수정 대상 | Lyra 구현 |
|------|----------|----------|
| `PreAttributeBaseChange` | BaseValue (Instant GE, SetXxx 호출) | `ClampAttribute()` |
| `PreAttributeChange` | CurrentValue (Duration GE Aggregator 재계산) | `ClampAttribute()` |
| `PostAttributeChange` | 파생값 수동 조정 | MaxHealth↓ → Health Override |
| `PostGameplayEffectExecute` | Meta 소비 후 최종 Clamp | `FMath::Clamp(Health, min, MaxHealth)` |

---

## 9. ATTRIBUTE_ACCESSORS 3가지 함수

```cpp
GetXxx()  → Xxx.GetCurrentValue()               // CurrentValue 읽기
SetXxx(v) → ASC->SetNumericAttributeBase(attr, v) // ASC 경유 → Aggregator 포함
InitXxx(v)→ Xxx.SetBaseValue(v); Xxx.SetCurrentValue(v)  // 직접, 초기화 전용
```

---

## 10. 파생 Attribute 3가지 방법

| 방법 | 자동갱신 | 참조수 | 설정위치 | Lyra 사용 |
|------|---------|-------|---------|----------|
| AttributeBased GE | Duration/Infinite O | 1개 | GE 에디터 | 미사용 |
| PostAttributeChange | 수동 | 제한없음 | C++ | O (MaxHealth→Health) |
| MMC | Duration/Infinite O | 여러개 | C+++GE에디터 | 미사용 |

---

## 23. FGameplayAttributeData 구조 — BaseValue / CurrentValue 분리 이유

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AttributeSet.h:21`

### 구조체

```cpp
struct FGameplayAttributeData
{
protected:
    float BaseValue;    // 영구적인 기저값
    float CurrentValue; // 버프/디버프가 반영된 현재값
};
```

### BaseValue vs CurrentValue

| | 언제 바뀌나 | 특징 |
|---|---|---|
| `BaseValue` | Instant GE, `SetXxx()` 호출 | GE 제거 후에도 유지 |
| `CurrentValue` | Aggregator 재계산 (Duration/Infinite GE) | 게임 코드에서 실제로 읽는 값, GE 제거 시 BaseValue 기준 복귀 |

```
BaseValue = 100
+ Duration GE "체력 +20" → CurrentValue = 120
GE 제거                  → CurrentValue = 100 (BaseValue로 복귀)
```

### ATTRIBUTE_ACCESSORS 매크로 생성 4개 함수 (AttributeSet.h:429)

```cpp
static FGameplayAttribute GetHealthAttribute(); // FProperty 포인터 (GE Modifier 지정용)
float GetHealth() const;                        // CurrentValue 읽기
void SetHealth(float NewVal);                   // ASC->SetNumericAttributeBase() 경유 → Aggregator 재계산 + 델리게이트 보장
void InitHealth(float NewVal);                  // BaseValue + CurrentValue 직접 세팅 (초기화 전용, Aggregator 없는 시점)
```

`SetXxx`가 ASC를 경유하는 이유: 직접 쓰면 Aggregator 재계산과 `PreAttributeBaseChange` 델리게이트가 발동하지 않음.

`ReplicatedLooseTags`는 `GetLifetimeReplicatedProps`에 `COND_None`으로 등록된 복제 프로퍼티.  
기본값 `None`을 쓰면 이 컨테이너에 들어가지 않아 복제가 일어나지 않는다.

**결론**: GE는 복제가 내장된 시스템이고, LooseGameplayTag는 GE 없이 수동 관리하는 탈출구라 복제 책임도 호출자에게 있다.

---

## 24. FOnAttributeChangeData / FGameplayEffectModCallbackData 구조

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayEffectTypes.h:1009`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayEffect.cpp:3724, 3912`

### FOnAttributeChangeData

`GetGameplayAttributeValueChangeDelegate()` 바인딩 콜백이 받는 구조체.

```cpp
struct FOnAttributeChangeData
{
    FGameplayAttribute                    Attribute;
    float                                 NewValue;
    float                                 OldValue;
    const FGameplayEffectModCallbackData* GEModData; // 서버만 유효, 클라이언트는 nullptr
};
```

Broadcast 발동 경로 두 곳:
- **서버 (GameplayEffect.cpp:3912)**: GE가 Attribute 변경 시 → `GEModData` 채워짐
- **클라이언트 (GameplayEffect.cpp:3724)**: 복제 수신 시 → `GEModData = nullptr`

---

## 24b. FGameplayEffectModCallbackData 구조

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayEffectExtension.h:17`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayEffectTypes.h:194`

`PreGameplayEffectExecute` / `PostGameplayEffectExecute` 콜백에 전달되는 일회용 컨텍스트 구조체.

```cpp
struct FGameplayEffectModCallbackData
{
    const FGameplayEffectSpec&         EffectSpec;    // GE 전체 스펙 (Instigator, 태그, 레벨 등)
    FGameplayModifierEvaluatedData&    EvaluatedData; // 계산 완료된 Modifier 결과
    UAbilitySystemComponent&           Target;        // 적용 대상 ASC
};

struct FGameplayModifierEvaluatedData
{
    FGameplayAttribute                Attribute;   // 건드린 Attribute
    TEnumAsByte<EGameplayModOp::Type> ModifierOp; // Add / Multiply / Override
    float                             Magnitude;   // 계산된 최종 수치
    FActiveGameplayEffectHandle       Handle;       // 이 Modifier를 만든 ActiveGE 핸들
};
```

주요 사용 패턴:
```cpp
// 어떤 Attribute가 건드려졌는지 확인
if (Data.EvaluatedData.Attribute == GetDamageAttribute()) { ... }

// 발동자 확인
Data.EffectSpec.GetContext().GetInstigator();
```

`FGameplayEffectModCallbackData`는 서버에서만 채워짐.
클라이언트 측 `FOnAttributeChangeData` 델리게이트 콜백에서 이 포인터는 nullptr일 수 있음.
