# Lyra에서 AttributeSet 사용 방식

Lyra가 AttributeSet을 어떻게 설계하고 운용하는지 전체 흐름을 따라 정리한다.

---

## 클래스 계층

```
UAttributeSet  (GAS 엔진)
  └─ ULyraAttributeSet          ← 프로젝트 공통 베이스
        ├─ ULyraHealthSet        ← 피격자(타겟)가 보유. Health/MaxHealth/Damage(Meta)/Healing(Meta)
        └─ ULyraCombatSet        ← 공격자(소스)가 보유. BaseDamage/BaseHeal
```

`ULyraAttributeSet`은 얇은 베이스다. `GetWorld()`와 `GetLyraAbilitySystemComponent()` 헬퍼만 추가하고,
실제 로직은 모두 서브클래스에 있다.

---

## Attribute 역할 분리 설계

| AttributeSet | 소유 주체 | 역할 |
|---|---|---|
| `ULyraHealthSet` | 피격자(타겟) ASC | 생존 상태 관리. GE에 의해 수정됨 |
| `ULyraCombatSet` | 공격자(소스) ASC | 전투 스탯 보관. ExecCalc이 Capture해 감 |

두 AttributeSet이 직접 참조하지 않는다. `LyraDamageExecution`이 중간에서 Source의 `BaseDamage`를 Capture해
Target의 `Damage`(Meta Attribute)에 써주는 방식으로 연결된다.

```
[공격자 ASC]              [피격자 ASC]
CombatSet                 HealthSet
  BaseDamage ──Capture──▶ (ExecCalc 계산) ──▶ Damage(Meta) ──▶ Health
```

---

## AttributeSet 등록 방법 — 두 가지 경로

### 경로 1. PlayerState에서 직접 생성 (항상 존재)

`LyraPlayerState` 생성자에서 `CreateDefaultSubobject`로 만든다.
게임 내내 모든 플레이어가 반드시 갖는 기본 AttributeSet이다.

```cpp
// LyraPlayerState.cpp
AbilitySystemComponent = CreateDefaultSubobject<ULyraAbilitySystemComponent>(...);

// ASC의 Owner인 PlayerState를 Outer로 생성 → ASC가 자동으로 발견
HealthSet = CreateDefaultSubobject<ULyraHealthSet>(TEXT("HealthSet"));
CombatSet = CreateDefaultSubobject<ULyraCombatSet>(TEXT("CombatSet"));
```

`CreateDefaultSubobject`로 만들면 Owner(PlayerState)의 서브오브젝트가 된다.
ASC는 `InitializeComponent()` 시점에 Owner의 서브오브젝트를 스캔해서 `UAttributeSet` 파생 클래스를 자동 수집한다.

**자동 수집 코드 위치**: 엔진 `AbilitySystemComponent_Abilities.cpp` — `UAbilitySystemComponent::InitializeComponent()`

```cpp
// "Look for DSO AttributeSets" 주석
TArray<UObject*> ChildObjects;
GetObjectsWithOuter(Owner, ChildObjects, /*bIncludeNestedObjects=*/false, RF_NoFlags, EInternalObjectFlags::Garbage);

for (UObject* Obj : ChildObjects)
{
    UAttributeSet* Set = Cast<UAttributeSet>(Obj);
    if (Set)
    {
        SpawnedAttributes.AddUnique(Set);  // SpawnedAttributes 배열에 등록
    }
}
```

**동작 순서:**
1. `CreateDefaultSubobject<ULyraHealthSet>` → HealthSet이 PlayerState의 서브오브젝트로 생성
2. ASC ctor에서 `bWantsInitializeComponent = true` → 엔진이 나중에 `InitializeComponent()` 호출을 보장
3. `GetObjectsWithOuter(Owner)` → ASC Owner(PlayerState)의 **직접** 자식 오브젝트 전체 스캔 (재귀 없음)
4. `UAttributeSet` 파생이면 `SpawnedAttributes`에 추가

> **조건은 하나**: ASC의 Owner와 동일한 Outer를 가질 것.
> `CreateDefaultSubobject`는 자동으로 Owner를 Outer로 설정하므로, 선언만 해두면 자동 등록된다.

### 경로 2. ULyraAbilitySet을 통한 동적 부여

`ULyraAbilitySet`은 DataAsset으로 Ability + GE + AttributeSet을 묶어서 한 번에 부여하는 단위다.

```cpp
// LyraAbilitySet.cpp - GiveToAbilitySystem()
for (const FLyraAbilitySet_AttributeSet& SetToGrant : GrantedAttributes)
{
    // ① ASC Owner를 Outer로 AttributeSet 인스턴스 생성
    UAttributeSet* NewSet = NewObject<UAttributeSet>(LyraASC->GetOwner(), SetToGrant.AttributeSet);

    // ② ASC에 직접 등록
    LyraASC->AddAttributeSetSubobject(NewSet);

    // ③ 나중에 제거할 수 있도록 핸들 저장
    OutGrantedHandles->AddAttributeSet(NewSet);
}
```

이 방식은 세 곳에서 호출된다:

| 호출 위치 | 상황 |
|---|---|
| `LyraPlayerState::OnExperienceLoaded` | PawnData에 연결된 AbilitySet → Pawn 스폰 시 |
| `LyraEquipmentManagerComponent::EquipItem` | 장비 장착 시 무기 전용 AbilitySet 부여 |
| `GameFeatureAction_AddAbilities` | GameFeature 플러그인 활성화 시 동적 부여 |

### 동적 부여 제거

`FLyraAbilitySet_GrantedHandles::TakeFromAbilitySystem()`을 호출하면
부여했던 AttributeSet, Ability, GE를 모두 한 번에 정리한다.

```cpp
// 장비 해제 시
for (UAttributeSet* Set : GrantedAttributeSets)
{
    LyraASC->RemoveSpawnedAttribute(Set);
}
```

---

## AttributeSet 콜백 구조 (LyraHealthSet 기준)

GAS는 Attribute가 변경될 때 여러 시점에 콜백을 호출한다. Lyra는 이를 모두 구현한다.

```
GE 적용
  ├─ PreGameplayEffectExecute     ← 실행 전 차단 가능 (면역/GodMode 체크)
  │
  ├─ PreAttributeBaseChange       ← BaseValue 변경 직전 Clamp (Instant GE)
  ├─ PreAttributeChange           ← CurrentValue 변경 직전 Clamp (Duration GE)
  │
  ├─ PostGameplayEffectExecute    ← 실행 후 처리 (Meta → 실제 반영, 이벤트 브로드캐스트)
  │
  └─ PostAttributeChange          ← 값 변경 후 파생 처리 (MaxHealth↓ → Health 클램프)
```

### PreGameplayEffectExecute — 실행 전 차단

```cpp
bool ULyraHealthSet::PreGameplayEffectExecute(FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // 면역 태그가 있으면 Damage를 0으로 만들고 false 반환 → GE 실행 취소
        if (Data.Target.HasMatchingGameplayTag(TAG_Gameplay_DamageImmunity))
        {
            Data.EvaluatedData.Magnitude = 0.0f;
            return false;
        }
    }
    // 변경 전 값 스냅샷 (PostGameplayEffectExecute에서 delta 계산용)
    HealthBeforeAttributeChange = GetHealth();
    MaxHealthBeforeAttributeChange = GetMaxHealth();
    return true;
}
```

### PostGameplayEffectExecute — Meta Attribute 소비 + 이벤트 발행

```cpp
void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // ① 피격 메시지를 GameplayMessageSubsystem으로 브로드캐스트
        //    (HUD 히트마커, 킬피드 등이 TAG_Lyra_Damage_Message 채널을 구독)
        UGameplayMessageSubsystem::Get(...).BroadcastMessage(TAG_Lyra_Damage_Message, Message);

        // ② Health에 반영하고 Meta Attribute 초기화
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));
        SetDamage(0.0f);
    }
    else if (Data.EvaluatedData.Attribute == GetHealingAttribute())
    {
        SetHealth(FMath::Clamp(GetHealth() + GetHealing(), MinimumHealth, GetMaxHealth()));
        SetHealing(0.0f);
    }

    // ③ Health 변화 델리게이트 — LyraHealthComponent가 구독
    if (GetHealth() != HealthBeforeAttributeChange)
    {
        OnHealthChanged.Broadcast(Instigator, Causer, &Data.EffectSpec, Magnitude, OldValue, NewValue);
    }

    // ④ 사망 감지 — 한 번만 발동 (bOutOfHealth 플래그로 중복 방지)
    if ((GetHealth() <= 0.0f) && !bOutOfHealth)
    {
        OnOutOfHealth.Broadcast(...);
    }
    bOutOfHealth = (GetHealth() <= 0.0f);
}
```

---

## 외부 시스템과의 연결 — FLyraAttributeEvent 델리게이트

`ULyraHealthSet`은 직접 UI나 사망 처리를 하지 않는다.
대신 델리게이트를 발행하고, 외부 컴포넌트가 구독한다.

```cpp
// LyraHealthSet.h
DECLARE_MULTICAST_DELEGATE_SixParams(FLyraAttributeEvent,
    AActor* /*Instigator*/, AActor* /*Causer*/,
    const FGameplayEffectSpec*, float /*Magnitude*/,
    float /*OldValue*/, float /*NewValue*/
);

mutable FLyraAttributeEvent OnHealthChanged;
mutable FLyraAttributeEvent OnMaxHealthChanged;
mutable FLyraAttributeEvent OnOutOfHealth;
```

**구독하는 곳 — `ULyraHealthComponent`:**

```cpp
// LyraHealthComponent.cpp - InitializeWithAbilitySystem()
HealthSet = AbilitySystemComponent->GetSet<ULyraHealthSet>();

HealthSet->OnHealthChanged.AddUObject(this, &ThisClass::HandleHealthChanged);
HealthSet->OnMaxHealthChanged.AddUObject(this, &ThisClass::HandleMaxHealthChanged);
HealthSet->OnOutOfHealth.AddUObject(this, &ThisClass::HandleOutOfHealth);
```

`LyraHealthComponent`가 받아서 자신의 델리게이트(`OnHealthChanged`, `OnOutOfHealth`)로
다시 브로드캐스트한다. UI나 GameMode 등은 `LyraHealthComponent`의 델리게이트를 구독한다.

```
ULyraHealthSet::OnHealthChanged
  └─▶ ULyraHealthComponent::HandleHealthChanged
        └─▶ ULyraHealthComponent::OnHealthChanged   ← HUD, GameMode 등이 구독
```

---

## 복제 설정 차이

두 AttributeSet의 복제 조건이 다르다.

```cpp
// LyraHealthSet.cpp - 모든 클라이언트에 복제
DOREPLIFETIME_CONDITION_NOTIFY(ULyraHealthSet, Health,    COND_None, REPNOTIFY_Always);
DOREPLIFETIME_CONDITION_NOTIFY(ULyraHealthSet, MaxHealth, COND_None, REPNOTIFY_Always);

// LyraCombatSet.cpp - Owner 클라이언트에게만 복제
DOREPLIFETIME_CONDITION_NOTIFY(ULyraCombatSet, BaseDamage, COND_OwnerOnly, REPNOTIFY_Always);
DOREPLIFETIME_CONDITION_NOTIFY(ULyraCombatSet, BaseHeal,   COND_OwnerOnly, REPNOTIFY_Always);
```

| | ULyraHealthSet | ULyraCombatSet |
|---|---|---|
| 복제 조건 | `COND_None` (모든 클라이언트) | `COND_OwnerOnly` (Owner만) |
| 이유 | Health는 다른 플레이어 HUD에도 필요 | 공격력은 본인만 알면 됨 (치트 방지) |

---

## 전체 흐름 요약

```
[PlayerState 생성]
  └─ CreateDefaultSubobject → HealthSet, CombatSet 자동 등록

[PawnData 로드 완료]
  └─ AbilitySet->GiveToAbilitySystem()
        └─ 추가 AttributeSet 동적 부여 (NewObject + AddAttributeSetSubobject)

[장비 장착]
  └─ EquipItem → AbilitySet->GiveToAbilitySystem()
        └─ 무기 전용 AttributeSet/Ability 부여

[피격]
  └─ GE 발동
        ├─ PreGameplayEffectExecute  → 면역 체크, 값 스냅샷
        ├─ LyraDamageExecution
        │     ├─ Source CombatSet::BaseDamage Capture
        │     ├─ 거리/물리재질 감쇠, 팀 체크
        │     └─ Target HealthSet::Damage(Meta) += DamageDone
        └─ PostGameplayEffectExecute
              ├─ 피격 메시지 브로드캐스트 (GameplayMessageSubsystem)
              ├─ Health -= Damage, Damage = 0
              ├─ OnHealthChanged 델리게이트
              └─ OnOutOfHealth 델리게이트 (사망 시)

[LyraHealthComponent]
  └─ OnHealthChanged → HUD 갱신
  └─ OnOutOfHealth   → 사망 처리 GA 활성화
```
