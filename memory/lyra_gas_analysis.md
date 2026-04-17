---
name: Lyra GAS Analysis Cache
description: 소스 직접 열람으로 확인한 Lyra GAS 구현 분석 캐시. 다음 세션에서 재분석 없이 바로 참조 가능.
type: project
originSessionId: 3c3925dd-9448-4e40-a5b8-a6b2a3604de6
---
# Lyra GAS 분석 캐시

> 이 파일은 소스를 직접 읽어서 확인한 사실만 담는다. 추측 없음.
> 파일 경로는 모두 `Source/LyraGame/` 기준 상대경로.

---

## 1. ASC 소유 구조

- **Owner**: `ALyraPlayerState` — `IAbilitySystemInterface` 구현, `ULyraAbilitySystemComponent` 를 `CreateDefaultSubobject`로 보유
- **Avatar**: `ALyraCharacter` — Owner와 별개. `ULyraPawnExtensionComponent::InitializeAbilitySystem()`에서 `InitAbilityActorInfo(Owner, Avatar)` 호출
- **복제 모드**: `EGameplayEffectReplicationMode::Mixed`
- **업데이트 주기**: `SetNetUpdateFrequency(100.0f)`

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

## 4. GE → Attribute 수정 메커니즘

### 4개 ModifierOp (EGameplayModOp)
- `Additive`: += Magnitude
- `Multiplicitive` (오탈자 주의): *= Magnitude
- `Division`: /= Magnitude
- `Override`: = Magnitude (Aggregator 있어도 마지막 Override 값으로 덮어씀)

### Instant GE → BaseValue 영구 변경
흐름: `InternalExecuteMod → ApplyModToAttribute → SetAttributeBaseValue`
`StaticExecModOnBaseValue(BaseValue, ModOp, Magnitude)` 로 직접 연산

### Duration/Infinite GE → Aggregator에 Modifier 등록 (임시)
흐름: Aggregator에 Modifier 추가 → `BroadcastOnDirty` → `Evaluate()` → `SetCurrentValue(NewValue)`
계산식: `((BaseValue + Additive) * Multiplicitive / Division)` + Override 처리

### BaseValue 변경 → CurrentValue 동기화 콜체인
- **Aggregator 없을 때**: `SetBaseValue → InternalUpdateNumericalAttribute → SetNumericAttribute_Internal → SetNumericValueChecked → DataPtr->SetCurrentValue(NewBaseValue)`
- **Aggregator 있을 때**: `SetBaseValue → Aggregator->SetBaseValue → BroadcastOnDirty → OnDirty델리게이트 → ASC::OnAttributeAggregatorDirty → Aggregator->Evaluate → InternalUpdateNumericalAttribute → ... → SetCurrentValue(재계산값)`

Aggregator는 이 Attribute에 처음 Duration/Infinite GE 적용 시 생성됨.

### AttributeBased GE Modifier
`FAttributeBasedFloat` 구조: BackingAttribute, Coefficient, PreAdd, PostAdd
수식: `Coefficient * (PreAdd + BackingAttributeValue) + PostAdd`
Duration/Infinite GE면 BackingAttribute Aggregator dirty 시 자동 재계산.
`EAttributeBasedFloatCalculationType`: AttributeMagnitude(CurrentValue) / AttributeBaseValue / AttributeBonusMagnitude

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

## 6. 데미지 실행 흐름 (LyraDamageExecution)

```
[공격자 ASC: CombatSet::BaseDamage]
  └─ FDamageStatics: GetBaseDamageAttribute() Capture (Source, bSnapshot=true)

Execute_Implementation():
  AttemptCalculateCapturedAttributeMagnitude → BaseDamage 읽기
  CanCauseDamage(EffectCauser, HitActor) → DamageInteractionAllowedMultiplier (팀킬 방지)
  AbilitySource->GetDistanceAttenuation() → DistanceAttenuation
  AbilitySource->GetPhysicalMaterialAttenuation() → PhysicalMaterialAttenuation
  DamageDone = BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier
  AddOutputModifier(GetDamageAttribute(), Additive, DamageDone)
  → [피격자 ASC: HealthSet::Damage(Meta)]
```
`#if WITH_SERVER_CODE` 가드로 서버 전용.
힐(`LyraHealExecution`)은 동일 패턴, `BaseHeal → Healing(Meta)`.

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

## 11. 현재 문서 구조

```
gas/
  README.md                    (인덱스)
  01_overview.md               (빈 스켈레톤)
  02_ability_system_component.md
  03_gameplay_ability.md
  04_gameplay_effect.md
  attribute/
    README.md                  (인덱스)
    01_attribute_types.md      (FGameplayAttribute vs FGameplayAttributeData)
    02_base_current_value.md   (BaseValue/CurrentValue + GE 종류 + 동기화 콜체인)
    03_accessors_and_clamp.md  (ATTRIBUTE_ACCESSORS + Clamp)
    04_meta_attribute.md       (Meta Attribute 패턴 + 데미지 흐름)
    05_derived_attribute.md    (파생 Attribute 3가지)
    06_lyra_usage.md           (Lyra 전체 사용 방식 - 등록/콜백/구독 패턴)
  06_gameplay_tag.md
  07_gameplay_cue.md
  08_ability_task.md
  09_execution_calculation.md
  10_network_prediction.md

doc/
  README.md
  01_project_structure.md
  02_gas_architecture.md
  03_pawn_initialization.md
  04_input_ability.md
  05_equipment_weapon.md
  06_game_phase.md
  07_game_feature_ability.md
```

`gas/02~04`, `gas/06~10` 은 스켈레톤(헤더만 있음). 내용 있는 것: `gas/attribute/` 전체.
`doc/` 전체는 내용 있음.

---

## 12. 언리얼 입력 파이프라인 & ProcessAbilityInput 호출 경로

**출처 (Lyra)**: `Player/LyraPlayerController.cpp:376-384`, `AbilitySystem/LyraAbilitySystemComponent.cpp:216`  
**출처 (엔진 UE 5.7)**: `Engine/Source/Runtime/Engine/Private/PlayerController.cpp`, `Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
**상세 문서**: `unrealCore/input_pipeline.md`

### 전체 호출 체인

```
APlayerController::PlayerTick()                    ← PC.cpp:2309, 매 틱 무조건 (로컬 PC만)
    └─ TickPlayerInput()                           ← PC.cpp:5320
        ├─ PlayerInput->Tick()                     ← 제스처 인식 등
        └─ ProcessPlayerInput()                    ← PC.cpp:2768
            ├─ BuildInputStack()                   ← InputComponent 우선순위 스택 구성
            └─ PlayerInput->ProcessInputStack()    ← PlayerInput.cpp:1239
                ├─ PreProcessInput()               ← virtual 훅
                ├─ EvaluateKeyMapState()           ← Accumulator → EventCounts flush
                ├─ EvaluateInputDelegates()        ← 바인딩 델리게이트 실행
                ├─ PostProcessInput()              ← virtual 훅 ★ Lyra가 오버라이드
                │       └─ LyraASC->ProcessAbilityInput()
                └─ FinishProcessingPlayerInput()
```

### Accumulator 패턴 (두 단계 분리)

- **1단계 — 비동기 수집**: OS 키 이벤트 → `UPlayerInput::InputKey()` → `EventAccumulator`에 누적 (PlayerInput.cpp:278)
- **2단계 — 매 틱 flush**: `EvaluateKeyMapState()`가 `EventAccumulator` → `EventCounts`로 이동 후 Accumulator 초기화 (PlayerInput.cpp:1281)
- 입력이 없는 틱에도 flush 함수는 실행된다 (빈 Accumulator를 처리).

### bDown 홀드 상태 유지 원리

```cpp
// PlayerInput.cpp — ProcessNonAxesKeys 내부
if (KeyState->EventCounts[IE_Pressed].Num() > 0)
    KeyState->bDown = true;
else
    KeyState->bDown = KeyState->bDownPrevious;  // 이전 프레임 상태 복사
```
이 덕분에 `WhileInputActive` 정책이 키 홀드를 매 틱 감지할 수 있다.

### BuildInputStack 우선순위 (낮음 → 높음)
1. Pawn->InputComponent
2. Pawn에 붙은 다른 UInputComponent
3. LevelScriptActor->InputComponent
4. PlayerController->InputComponent
5. PushInputComponent()로 수동 추가된 것 (최우선)

### PostProcessInput이 매 틱 불리는 이유
`ProcessInputStack()`이 매 틱 `ProcessPlayerInput()`에서 무조건 호출되기 때문.
입력 이벤트 유무와 무관하다.

---

## 13. Lyra 입력 시스템 전체 구조

**출처**: `Input/LyraInputConfig.h`, `Input/LyraInputComponent.h/.cpp`, `Character/LyraHeroComponent.cpp`, `AbilitySystem/LyraAbilitySystemComponent.cpp:186-318`  
**상세 문서**: `doc/LyraImpl/input/`

### 핵심 클래스

- `ULyraInputConfig` — DataAsset. `NativeInputActions[]`(이동/시점)와 `AbilityInputActions[]`(GA용) 두 목록을 가짐. InputAction ↔ GameplayTag 매핑.
- `ULyraInputComponent` — `UEnhancedInputComponent` 서브클래스. `BindNativeAction()`, `BindAbilityActions()` 헬퍼 추가.
- `ULyraHeroComponent` — `InitState_DataInitialized` 도달 시 `InitializePlayerInput()` 호출. IMC 등록 + 바인딩 설정.

### 입력 경로 두 가지

**Ability 경로** (GA 활성화):
1. 키 누름 → Enhanced Input → `Input_AbilityInputTagPressed(Tag)` → `ASC::AbilityInputTagPressed()`
2. `AbilityInputTagPressed`: ActivatableAbilities 순회, `HasTagExact(InputTag)`로 Spec 찾아 `InputPressedSpecHandles` + `InputHeldSpecHandles`에 추가
3. 매 틱 `PostProcessInput()` → `ProcessAbilityInput()`: Held(WhileInputActive) + Pressed(OnInputTriggered) 처리 → `TryActivateAbility()`
4. 키 뗌 → `AbilityInputTagReleased()` → `InputReleasedSpecHandles`에 추가, `InputHeldSpecHandles`에서 제거
5. Pressed/Released는 ProcessAbilityInput 끝에 초기화. Held는 키 뗄 때까지 유지.

**Native 경로** (이동/시점):
- Enhanced Input 이벤트 즉시 콜백 호출. `Input_Move()`, `Input_LookMouse()`, `Input_LookStick()`, `Input_Crouch()`, `Input_AutoRun()`
- 마우스: 델타 그대로 전달. 스틱: `* Rate * DeltaSeconds`로 프레임 독립적 처리.

### AbilityInputBlocked
`TAG_Gameplay_AbilityInputBlocked` 태그가 ASC에 있으면 `ProcessAbilityInput` 진입 시 전체 무시 + `ClearAbilityInput()`.

### 복제
`AbilitySpecInputPressed/Released`에서 `bReplicateInputDirectly` 미사용. `InvokeReplicatedEvent`로 처리 → `WaitInputPress/Release` AbilityTask와 호환.

---

## 14. ModularGameplay 플러그인 — UGameFrameworkComponent / UPawnComponent / InitState 시스템

**출처**:  
`Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponent.h`  
`Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/PawnComponent.h`  
`Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkInitStateInterface.h`  
`Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponentManager.h`  
**상세 문서**: `doc/unrealCore/modular_gameplay.md`

### 클래스 계층

```
UActorComponent
  └─ UGameFrameworkComponent
        └─ UPawnComponent
```

### UGameFrameworkComponent 추가 API
- `GetGameInstance<T>()` — Owner 통해 GameInstance 접근
- `HasAuthority()` — Owner Role == ROLE_Authority 확인
- `GetWorldTimerManager()` — 타이머 매니저
- 같은 헤더에 `TComponentIterator<T>` / `TConstComponentIterator<T>` 이터레이터 유틸리티 정의

### UPawnComponent 추가 API (모두 template, static_assert 타입 안전)
- `GetPawn<T>()` / `GetPawnChecked<T>()` — Owner를 Pawn으로 접근
- `GetPlayerState<T>()` — Pawn의 PlayerState (클라이언트 복제 전 null 가능)
- `GetController<T>()` — Pawn의 Controller (클라이언트에서 보통 null)

### UGameFrameworkComponentManager (UGameInstanceSubsystem)
**역할 1: 컴포넌트 동적 주입**
- `AddReceiver(Actor)` — Actor를 수신자로 등록 (BeginPlay/OnRegister에서 호출)
- `AddComponentRequest(ActorClass, ComponentClass)` → `FComponentRequestHandle` (RAII, 소멸 시 컴포넌트 제거)
- `SendExtensionEvent(Actor, EventName)` — 확장 이벤트 발송
- 내장 이벤트: `NAME_ReceiverAdded`, `NAME_ReceiverRemoved`, `NAME_GameActorReady`

**역할 2: InitState 조율**
- `RegisterInitState(NewState, bAddBefore, ExistingState)` — 전역 상태 순서 등록 (GameplayTag 배열)
- `ChangeFeatureInitState(Actor, FeatureName, Implementer, FeatureState)` — 상태 변경 + 구독자 통보 (StateChangeQueue로 재귀 방지)
- `HaveAllFeaturesReachedInitState(Actor, RequiredState)` — 모든 Feature 도달 여부 체크

### IGameFrameworkInitStateInterface 핵심 메서드
- `RegisterInitStateFeature()` / `UnregisterInitStateFeature()` — OnRegister/EndPlay에서 호출
- `CanChangeInitState(Manager, Current, Desired)` — 전이 가능 여부 커스텀 체크
- `HandleChangeInitState(Manager, Current, Desired)` — 전이 직전 실행 로직
- `TryToChangeInitState(DesiredState)` — Can 확인 → Handle → Manager 통보
- `ContinueInitStateChain(ChainArray)` — 지정 순서로 연속 전이, 도달한 최종 상태 반환
- `OnActorInitStateChanged(Params)` — 같은 Actor 다른 Feature 상태 변경 감지
- `CheckDefaultInitialization()` — override해서 ContinueInitStateChain 호출

### Lyra 활용 패턴
- `ULyraPawnExtensionComponent` + `ULyraHeroComponent` 모두 `UPawnComponent + IGameFrameworkInitStateInterface` 이중 상속
- Pawn 위 두 Feature가 Manager를 중재자로 삼아 직접 참조 없이 초기화 순서 조율
- InitState 4단계: `Spawned → DataAvailable → DataInitialized → GameplayReady`
- `DataInitialized` 전이 시: PawnExtension → `InitializeAbilitySystem()`, Hero → `InitializePlayerInput()`
