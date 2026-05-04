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

**출처**: `Source/LyraGame/AbilitySystem/Executions/LyraDamageExecution.cpp`

```
[공격자 ASC: CombatSet::BaseDamage]
  └─ FDamageStatics: GetBaseDamageAttribute() Capture (Source, bSnapshot=true)

Execute_Implementation():
  TypedContext = FLyraGameplayEffectContext::ExtractEffectContext(Spec.GetContext())
  HitActorResult = TypedContext->GetHitResult()   ← TargetData에서 흘러온 FHitResult
  HitActor       = CurHitResult.HitObjectHandle.FetchActor()
  ImpactLocation = CurHitResult.ImpactPoint
  (HitResult 없으면 TargetASC->GetAvatarActor() 위치로 폴백)

  CanCauseDamage(EffectCauser, HitActor) → DamageInteractionAllowedMultiplier (팀킬 방지)
  Distance = Dist(TypedContext->GetOrigin(), ImpactLocation)
  AbilitySource->GetDistanceAttenuation(Distance) → DistanceAttenuation
  TypedContext->GetPhysicalMaterial()              ← HitResult 내부 PhysicalMaterial
  AbilitySource->GetPhysicalMaterialAttenuation(PhysMat) → PhysicalMaterialAttenuation
  DamageDone = BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation * DamageInteractionAllowedMultiplier
  AddOutputModifier(GetDamageAttribute(), Additive, DamageDone)
  → [피격자 ASC: HealthSet::Damage(Meta)]
```
`#if WITH_SERVER_CODE` 가드로 서버 전용.
힐(`LyraHealExecution`)은 동일 패턴, `BaseHeal → Healing(Meta)`.

**TargetData 연결**: HitResult(피격 위치·재질)가 TargetData → Context → ExecCalc 순서로 흘러야 거리 감쇠와 재질 감쇠가 동작한다. TargetData 없이 GE를 직접 적용하면 두 감쇠 모두 폴백값(거리 WORLD_MAX, 재질 없음)으로 처리된다.

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

---

## 배치 Actor vs 동적 스폰 Actor 초기화 경로

> 출처: `Engine/Source/Runtime/Engine/Private/World.cpp`, `Level.cpp`, `Actor.cpp`

### 배치 Actor (레벨에 놓인 것)
- `PostLoad()` → `RegisterAllComponents()` → `RouteActorInitialize()`
- `RouteActorInitialize` (Level.cpp:3817): 3단계 Phase로 레벨 내 전체 Actor를 일괄 처리
  - Phase 1: 전체 Actor `PreInitializeComponents()`
  - Phase 2: 전체 Actor `InitializeComponents()` + `PostInitializeComponents()`
  - Phase 3: 전체 Actor `DispatchBeginPlay()`
- Construction Script 실행 여부: `!(RequiresCookedData || bWasDuplicatedForPIE || bHasRerunConstructionScripts)`
  - 쿠킹 빌드: 실행 안 함 (직렬화에 포함됨)
  - PIE: 실행 안 함 (에디터 레벨 복제본)
  - 에디터 빌드 게임: 실행함

### 동적 스폰 Actor
- `SpawnActor()` → `PostSpawnInitialize()` → `PostActorCreated()` → `OnConstruction()` → `PostInitializeComponents()`
- Construction Script: 항상 실행
- `World->HasBegunPlay()` 이면 `PostInitializeComponents` 직후 `BeginPlay` 즉시 호출

### 공통 합류점
- `PostInitializeComponents()` — 배치/스폰 모두 여기서 동일한 상태 보장
- `PostActorCreated()`는 SpawnActor 경로에만 존재 → 배치 Actor 초기화 코드를 여기에 넣으면 안 됨

---

## 언리얼 복제 시스템 파이프라인

> 출처: `NetDriver.cpp`, `DataChannel.cpp`, `DataReplication.cpp`, `RepLayout.cpp`, `ActorReplication.cpp`

### 서버 매 틱 흐름
```
UNetDriver::TickFlush()
  → ServerReplicateActors()
    1. BuildConsiderList() — 후보 Actor 목록 (NextUpdateTime, RemoteRole, IsActorInitialized 필터)
    2. [각 Connection] IsNetRelevantFor() — 이 클라이언트에 관련 있는가
    3. GetNetPriority() 정렬 — 대역폭 부족 시 우선순위
    4. ActorChannel::ReplicateActor()
         bNetInitial=true: SerializeNewActor() (클라이언트에서 Actor 스폰)
         FObjectReplicator::ReplicateProperties()
           CompareProperties() — 현재값 vs Shadow Buffer 비교
           변경된 프로퍼티만 직렬화 → 전송
```

### Shadow Buffer
- `FRepLayout`이 "지난번에 보낸 값"의 복사본을 유지
- 현재값과 비교해 변경된 것만 직렬화 → 대역폭 절약
- `GShareShadowState`: 같은 프레임에 커넥션 100개라도 CompareProperties는 1번만

### Actor 복제 등록 시점
- `DispatchBeginPlay()` → `StartReplicatingActor()` → `BeginPlay()`
- `RouteEndPlay()` → `StopReplicatingActor()`

### Relevancy 플래그 (ActorReplication.cpp:382)
- `bAlwaysRelevant=true`: 모든 클라이언트에 항상
- `bOnlyRelevantToOwner=true`: Owner만
- 기본값: `NetCullDistanceSquared` 거리 컬링

### NetUpdateFrequency
- `SetNetUpdateFrequency(100.0f)` — ConsiderList 진입 최대 빈도 (초당)
- 높다고 매 틱 복제되는 게 아님 — 대역폭/우선순위에 따라 실제 전송은 스킵 가능

### RPC 내부 흐름
> 출처: `ScriptCore.cpp`, `Actor.cpp`, `NetDriver.cpp`

- **프로퍼티 복제와 차이**: 복제=값 자동 전파, RPC=함수 호출 직접 전달
- **진입점**: `UObject::ProcessEvent()` → `GetFunctionCallspace()` → Remote면 `CallRemoteFunction()` → `NetDriver::ProcessRemoteFunction()`
- **GetFunctionCallspace 로직** (Actor.cpp):
  - Server RPC + 클라이언트 호출 → Remote (서버로 전송)
  - Server RPC + 서버 호출 → Local (이미 서버)
  - Client RPC + 서버 호출 → Remote (Owner 클라이언트로 전송)
  - Multicast + 서버 호출 → Local|Remote (서버 실행 + 모든 클라에 전송)
- **직렬화**: `FRepLayout::SendPropertiesForRPC()` — 파라미터를 비트스트림으로 직렬화
- **Unreliable + 대역폭 포화** → 조용히 드랍 (NetDriver.cpp:2929)
- **Reliable 버퍼 오버플로우** → 연결 자체 끊음 (NetDriver.cpp:3152)
- **Unreliable Multicast** → 즉시 전송 안 하고 틱 끝에 일괄 처리 (QueueBunch)
- **bReplicates=false인 Actor의 RPC** → RemoteRole=ROLE_None → Absorbed (무시)

---

## 12. ModularGameplay 설계 의도 — 왜 필요한가

> 출처: `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponentManager.h`

### 핵심 설계 의도
- **"Actor를 건드리지 않고 외부에서 기능 주입"**
- GameFeature 플러그인이 켜질 때 `AddComponentRequest()` → 컴포넌트 자동 생성
- 플러그인 비활성화 시 `FComponentRequestHandle` 소멸(RAII) → 컴포넌트 자동 제거
- Actor는 `AddReceiver(this)` 선언만 하면 됨 — 뭐가 붙는지 모름

### 기존 방식 vs ModularGameplay
```
기존: ALyraCharacter 생성자에서 CreateDefaultSubobject — 컴파일 타임 결정
새것: UGameFeatureAction_AddComponents::OnGameFeatureActivating() → AddComponentRequest() — 런타임 결정
```

### GameFeature 연동 패턴
```cpp
// 활성화 시
Manager->AddComponentRequest(ALyraCharacter::StaticClass(), ULyraEquipmentManagerComponent::StaticClass());
// → 현재 살아있는 ALyraCharacter에 즉시 생성 + 이후 스폰된 것에도 자동 적용

// 비활성화 시
ActiveRequests.Empty();  // Handle 소멸 → 자동 제거
```

### Actor opt-in 필요한 이유

- ReceiverClass == AActor 강제 차단 (ensure로 막음) — 성능 문제
- Actor 개발자가 명시적 지원 선언 필요: `BeginPlay()`에서 `AddGameFrameworkComponentReceiver(this)`

---

## 13. GameFeatures 플러그인 — UGameFeaturesSubsystem

> 출처: `Source/LyraGame/GameModes/LyraExperienceManagerComponent.cpp`, `LyraExperienceDefinition.h`

### ModularGameplay와의 관계
- **GameFeatures** = 트리거 ("언제/왜 플러그인 켜고 끄는가") — `UGameFeaturesSubsystem`
- **ModularGameplay** = 메커니즘 ("어떻게 컴포넌트 주입하는가") — `UGameFrameworkComponentManager`
- `UGameFeatureAction_AddComponents`가 연결고리: GameFeatures 활성화 시 ModularGameplay API 호출

### 플러그인 상태 머신
```
Uninitialized → Installed → Registered → Loaded → Active
```
`Active` 진입 시 `UGameFeatureAction::OnGameFeatureActivating()` 실행

### 핵심 API
```cpp
UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(PluginURL, Callback);
UGameFeaturesSubsystem::Get().GetPluginURLByName(PluginName, PluginURL);
```

### Lyra Experience 흐름 (LyraExperienceManagerComponent.cpp:269)
```
SetCurrentExperience() → StartExperienceLoad() → 에셋 비동기 로드
  → OnExperienceLoadComplete()
       → Experience.GameFeaturesToEnable 목록 순회
       → LoadAndActivateGameFeaturePlugin() (비동기)
  → OnExperienceFullLoadCompleted()
       → Experience.Actions 직접 실행
       → OnExperienceLoaded Broadcast
```

### ULyraExperienceDefinition (DataAsset)
```cpp
TArray<FString> GameFeaturesToEnable;          // 활성화할 플러그인 이름
TArray<UGameFeatureAction*> Actions;           // 직접 실행할 Action
TArray<ULyraExperienceActionSet*> ActionSets;  // 재사용 가능한 Action 묶음
TObjectPtr<ULyraPawnData> DefaultPawnData;
```

### UGameFeatureAction 구현 패턴 (AddAbilities.cpp 기반)

- **AddComponentRequest 패턴**: 활성화 시 Handle 저장, 비활성화 시 Empty() → RAII 자동 제거
- **AddExtensionHandler 패턴**: Actor 이벤트(NAME_ExtensionAdded, NAME_LyraAbilityReady) 시 GA/AttributeSet 부여
- **WorldActionBase 패턴**: OnGameFeatureActivating에서 현재 월드 전체 + 이후 월드 모두 AddToWorld() 호출
- **FPerContextData 패턴**: `TMap<FGameFeatureStateChangeContext, FPerContextData>` — PIE 서버/클라 독립 상태 관리
- AddAbilities 흐름: `OnGameFeatureActivating → AddToWorld → AddExtensionHandler 등록 → HandleActorExtension → AddActorAbilities(ASC에 GiveAbility)`

---

## 14. World 프레임워크 — UWorld · AWorldSettings · GameMode · GameState

> 출처: `LyraWorldSettings.h`, `LyraGameMode.cpp`, `LyraGameState.h`

### 구조
```
UWorld (UObject, 컨테이너)
  ├─ AWorldSettings  — 레벨 설정값 Actor (중력, KillZ, 기본 GameMode 클래스)
  ├─ AGameModeBase   — 게임 규칙 (서버 전용, 클라에 없음)
  └─ AGameStateBase  — 현재 게임 상태 (서버→클라 복제)
```

### 핵심 구분
- GameMode는 서버 전용 (규칙은 클라가 알 필요 없음 → 치트 방지)
- GameState는 복제됨 (점수, 남은 시간 등 클라도 알아야 함)
- WorldSettings가 DefaultGameMode 클래스를 결정 → 서버 맵 로드 시 인스턴스화

### AWorldSettings 추가 사항 (WorldSettings.cpp:353, 378)
- **이름 오해**: "Settings"지만 실제로는 레벨당 하나인 대표 Actor — 설정값 보관 + 레벨 범위 로직 실행
- **복제 프로퍼티**: `PauserPlayerState`, `TimeDilation`, `CinematicTimeDilation`, `WorldGravityZ`, `bHighPriorityLoading` (모두 transient, 런타임 상태)
- **NotifyBeginPlay()**: 월드 전체 Actor의 BeginPlay를 일괄 트리거. GameStateBase::HandleBeginPlay()가 서버에서 호출 → bReplicatedHasBegunPlay 복제 → 클라이언트 OnRep에서 동일하게 호출
- **왜 WorldSettings에**: UWorld는 서브클래싱 불가 → AWorldSettings가 레벨 범위 커스터마이징 진입점. GameStateBase(언제) vs WorldSettings(어떻게) 관심사 분리

### Lyra 확장
- `ALyraWorldSettings::DefaultGameplayExperience` — 레벨별 기본 Experience 에셋
- `ALyraGameMode::HandleMatchAssignmentIfNotExpectingOne()` — URL > DeveloperSettings > CommandLine > WorldSettings > 하드코딩 폴백 순으로 ExperienceId 결정
- `ALyraGameState`가 `ULyraExperienceManagerComponent` 보유 → Experience 로드 + GameFeature 활성화

---

## 20. CommonUser 플러그인

출처: `Plugins/CommonUser/Source/CommonUser/Public/`
상세 문서: `doc/unrealCore/plugin/common_user/`

### 구조
- `UCommonUserSubsystem` — 로그인/권한/초기화 스테이트 머신 (GameInstanceSubsystem)
- `UCommonUserInfo` — 유저 1명의 상태 오브젝트. `LocalUserInfos` TMap에 보관
- `UCommonSessionSubsystem` — 세션 호스팅/검색/참여 (GameInstanceSubsystem)
- `UAsyncAction_CommonUserInitialize` — BP용 비동기 래퍼

### 핵심 열거형
- `ECommonUserInitializationState`: Unknown → DoingInitialLogin → LoggedInLocalOnly → DoingNetworkLogin → LoggedInOnline
- `ECommonUserOnlineContext`: Game / Default / Service / Platform — 콘솔에서 플랫폼·서비스 레이어 분리
- `ECommonUserPrivilege`: CanPlay / CanPlayOnline / CanCommunicateViaTextOnline 등
- `ECommonUserAvailability`: NowAvailable / CurrentlyUnavailable / AlwaysUnavailable

### 초기화 함수 체인
```
TryToInitializeUser(Params)
  → ProcessLoginRequest()
      → AutoLogin() / ShowLoginUI() / QueryUserPrivilege()
  → HandleLoginForUserInitialize()
  → OnUserInitializeComplete 브로드캐스트
```

### 세션 흐름
- `HostSession()` → `CreateOnlineSessionInternal()` → `ServerTravel()`
- `QuickPlaySession()` → `FindSessions()` → 빈자리 있으면 `JoinSession()`, 없으면 `HostSession()`
- `JoinSession()` → `JoinSessionInternal()` → 비콘 예약 → `ClientTravel()`
- `bUseBeacons=true`(기본): `APartyBeaconHost/Client`로 입장 전 자리 예약

### OSSv1/v2 분기
- `CommonUser.Build.cs`의 `bUseOnlineSubsystemV1`으로 전환
- 코드 전체에 `#if COMMONUSER_OSSV1` 분기 — `using` alias로 공통 타입 추상화

### Lyra 연결
- `ULyraFrontendStateComponent` → `UCommonUserSubsystem` 직접 접근
- `W_LyraStartup` → `ListenForLoginKeyInput()` (Press Start 화면)
- `W_ExperienceSelectionScreen` → `QuickPlaySession()` / `HostSession()`
- `W_SessionBrowserScreen` → `FindSessions()` + `JoinSession()`

---

## 21. Lyra Experience 시스템 전체 흐름

출처: `Source/LyraGame/GameModes/` 전체
상세 문서: `doc/LyraImpl/experience.md`

### Experience vs GameFeature 관계
- Experience = Lyra DataAsset. "어떤 GameFeature 플러그인이 필요하고, 어떤 Action을 실행할지" 선언
- GameFeature = 엔진 플러그인 컨테이너. Experience와 M:N 관계 — 하나의 플러그인을 여러 Experience가 공유
- 비유: Experience = 레시피, GameFeature = 재료

### ExperienceId 결정 우선순위 (LyraGameMode.cpp:HandleMatchAssignmentIfNotExpectingOne)
1. URL Option (`?Experience=...`)
2. PIE DeveloperSettings (에디터 전용)
3. 커맨드라인 (`-Experience=...`)
4. `ALyraWorldSettings::DefaultGameplayExperience`
5. `B_LyraDefaultExperience` (하드코딩 폴백)

### 로드 파이프라인 (ELyraExperienceLoadState)
```
Unloaded → Loading(에셋 로드) → LoadingGameFeatures(플러그인 활성화) → ExecutingActions(Action 직접 실행) → Loaded
```
- 서버: `SetCurrentExperience()` → `StartExperienceLoad()`
- 클라이언트: `CurrentExperience` 복제 수신 → `OnRep_CurrentExperience()` → `StartExperienceLoad()`

### GameFeature Actions vs Experience Actions
- **플러그인 Actions**: `.uplugin` → `UGameFeatureData` — 엔진이 자동 실행, 플러그인 Active 동안 항상
- **Experience Actions**: `ULyraExperienceDefinition.Actions` — Lyra가 직접 실행, 해당 Experience 동안만

### GameFeatureAction 7종 (Source/LyraGame/GameFeatures/)
| Action | 대상 | 핵심 API |
|--------|------|----------|
| AddAbilities | ALyraPlayerState | ASC->GiveAbility, GiveToAbilitySystem — 서버에서만, GA는 SetRemoveAbilityOnEnd |
| AddInputBinding | APawn | HeroComponent->AddAdditionalInputConfig |
| AddInputContextMapping | LocalPlayer | EnhancedInputSubsystem->AddMappingContext — Registering 단계부터 동작 |
| AddWidgets | ALyraHUD | PushContentToLayer_ForPlayer, RegisterExtensionAsWidgetForContext |
| AddGameplayCuePath | GCM | AddGameplayCueNotifyPath — LyraGameFeaturePolicy가 Registering에서 처리 |
| SplitscreenConfig | GameViewportClient | SetForceDisableSplitscreen — 전역 투표 카운트(GlobalDisableVotes) |
| WorldActionBase | (추상) | AddToWorld() — 모든 Action의 PIE 안전 베이스 |

모든 Action은 `TMap<FGameFeatureStateChangeContext, FPerContextData>`로 PIE 멀티 월드 안전 처리.
ComponentRequests TSharedPtr Handle 소멸 시 AddExtensionHandler 자동 해제.

### OnExperienceLoaded 3단계 델리게이트
`CallOrRegister_OnExperienceLoaded_HighPriority` / `_OnExperienceLoaded` / `_LowPriority` — 우선순위별 초기화 순서 보장

### PIE 중복 방지
`ULyraExperienceManager`(EngineSubsystem): 에디터에서만 플러그인 활성화 참조 카운트 관리

---

## 14. Experience 로드 완료 후 폰 스폰 제어 (LyraGameMode.cpp)

출처: `Source/LyraGame/GameModes/LyraGameMode.cpp`

### 핵심 구조: 두 개의 가드

**가드 1 — HandleStartingNewPlayer (L391)**
```cpp
void ALyraGameMode::HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)
{
    if (IsExperienceLoaded())  // Experience 미완료 시 Super 호출 안 함 → 스폰 안 됨
        Super::HandleStartingNewPlayer_Implementation(NewPlayer);
}
```
- Experience 로드 전 접속한 플레이어는 스폰이 아예 막힘

**가드 2 — OnExperienceLoaded (L305)**
```cpp
void ALyraGameMode::OnExperienceLoaded(const ULyraExperienceDefinition* CurrentExperience)
{
    for (FConstPlayerControllerIterator Iterator = ...)
    {
        if (PC->GetPawn() == nullptr && PlayerCanRestart(PC))
            RestartPlayer(PC);  // 이미 접속해 있던 PC들을 사후에 스폰
    }
}
```
- Experience 완료 시점에 폰 없는 PC 전원 스폰

### 등록 시점 (InitGameState, L452)
```cpp
ExperienceComponent->CallOrRegister_OnExperienceLoaded(
    FDelegate::CreateUObject(this, &ThisClass::OnExperienceLoaded));
```
- `InitGameState()`에서 `ExperienceManagerComponent`의 OnExperienceLoaded 델리게이트에 등록

### GetDefaultPawnClassForController (L332)
```cpp
// Experience 미로드 시 nullptr 반환 → 스폰 실패 → FailedToRestartPlayer → 다음 프레임 재시도
if (!ExperienceComponent->IsExperienceLoaded()) return nullptr;
```

### 전체 흐름 요약
```
InitGame → (NextTick) HandleMatchAssignmentIfNotExpectingOne → ExperienceManagerComponent 로드 시작
InitGameState → OnExperienceLoaded 델리게이트 등록
플레이어 접속 → HandleStartingNewPlayer → IsExperienceLoaded() false → 스폰 대기
Experience 완료 → OnExperienceLoaded 브로드캐스트
  → ALyraGameMode::OnExperienceLoaded → 대기 중 PC 전원 RestartPlayer
  → 이후 접속자는 HandleStartingNewPlayer에서 즉시 통과
```

---

## 23. Lyra 카메라 시스템 — CameraMode / CameraModeStack

> 출처: `Camera/LyraCameraMode.h/cpp`, `Camera/LyraCameraComponent.h/cpp`, `Camera/LyraCameraMode_ThirdPerson.h`  
> 상세 문서: `doc/LyraImpl/camera/01_camera_mode.md`

### 클래스 역할
- `ULyraCameraMode` (UObject): "하나의 카메라 시점 행동". Outer = ULyraCameraComponent. `UpdateView`+`UpdateBlending` 매 프레임 실행
- `FLyraCameraModeView`: 모드 출력값 (Location, Rotation, ControlRotation, FOV). `Blend(Other, Weight)`로 보간
- `ULyraCameraModeStack` (UObject): 모드 블렌드 스택. `CameraModeInstances`(풀) + `CameraModeStack`(활성) 분리
- `ULyraCameraComponent` (UCameraComponent): 스택 소유. 매 프레임 `DetermineCameraModeDelegate.Execute()` → PushCameraMode
- `ULyraCameraMode_ThirdPerson`: 실제 구현체. TargetOffsetCurve(피치→오프셋), PreventPenetration, PredictiveAvoidance

### 핵심 설계
- **Outer 패턴**: 모드가 `CastChecked<ULyraCameraComponent>(GetOuter())`로 자신의 컴포넌트 접근
- **DetermineCameraModeDelegate**: 카메라가 "어떤 모드 쓸지" 스스로 결정 안 함. ULyraHeroComponent가 바인딩
- **BlendStack 방향**: 스택 바닥(인덱스 끝)부터 꼭대기로 올라가며 블렌딩. 최상단 BlendWeight=1.0 도달 시 하위 모드 제거
- **인스턴스 풀링**: 한 번 생성된 모드는 `CameraModeInstances`에 보관 후 재사용
- **CameraTypeTag**: GameplayTag로 현재 모드 상태 외부 조회 가능 (GAS 연동)

### GetPivotLocation 웅크림 보정 (cpp:99)
```cpp
float HeightAdjustment = (DefaultHalfHeight - ActualHalfHeight) + CDO->BaseEyeHeight;
return Character->GetActorLocation() + FVector::UpVector * HeightAdjustment;
```

---

## 25. ULyraAbilityTagRelationshipMapping 전체 흐름

> 출처: `AbilitySystem/LyraAbilityTagRelationshipMapping.h/cpp`, `LyraAbilitySystemComponent.cpp:356,379`, `Abilities/LyraGameplayAbility.cpp:316`, `Character/LyraPawnExtensionComponent.cpp:146`  
> 상세 문서: `doc/LyraImpl/gas/04_tag_systems.md`

### 구조
- DataAsset. 행마다: AbilityTag(키) + AbilityTagsToBlock + AbilityTagsToCancel + ActivationRequiredTags + ActivationBlockedTags
- `ULyraPawnData.TagRelationshipMapping` → `InitializeAbilitySystem()` → `ASC->SetTagRelationshipMapping()`

### 훅 A — CanActivateAbility 체크 (활성화 전)
`DoesAbilitySatisfyTagRequirements` (LyraGA 오버라이드)
→ `GetAdditionalActivationTagRequirements()` (LyraASC)
→ `Mapping.GetRequiredAndBlockedActivationTags(GA의 AbilityTags)`
→ GA 자체 Required/Blocked에 매핑 결과 합산 → ASC 보유 태그 대조

### 훅 B — PreActivate / EndAbility (Block/Cancel 실행)
엔진 `PreActivate()` → `ApplyAbilityBlockAndCancelTags(bEnable=true, bCancel=true)` (LyraASC 오버라이드)
→ `Mapping.GetAbilityTagsToBlockAndCancel(GA의 AbilityTags)` → BlockTags/CancelTags 확장
→ `Super()` → `BlockAbilitiesWithTags(+1)` + `CancelAbilities()`

엔진 `EndAbility()` → `ApplyAbilityBlockAndCancelTags(bEnable=false, bCancel=false)`
→ 동일 매핑 재조회 → `UnBlockAbilitiesWithTags(-1)` 카운터 감소, 취소는 없음

---

## 24. GameplayMessageSubsystem — pub/sub 메시지 버스

> 출처: `Plugins/GameplayMessageRouter/Source/GameplayMessageRuntime/`  
> 상세 문서: `doc/unrealCore/plugin/gameplay_message/README.md`

### 핵심 구조
- `UGameplayMessageSubsystem` (UGameInstanceSubsystem): 게임 인스턴스 수명. `TMap<FGameplayTag, FChannelListenerList> ListenerMap`
- `FGameplayMessageListenerHandle`: (WeakPtr<Subsystem>, Channel, ID) — 등록 해제용 불투명 핸들
- `EGameplayMessageMatch`: ExactMatch(기본) / PartialMatch(하위 태그 전체 수신)

### BroadcastMessage 흐름
- 브로드캐스트 태그에서 부모 방향으로 올라가며 순회 (`A.B.C` → `A.B` → `A`)
- 초기 태그: ExactMatch + PartialMatch 모두 호출. 상위 태그: PartialMatch만 호출
- 이터레이션 중 Unregister 안전: 리스너 배열 복사 후 순회

### RegisterListener 오버로드 3가지
1. 람다: `RegisterListener<T>(Channel, TFunction)`
2. 멤버 함수 + WeakPtr 자동 보호: `RegisterListener<T>(Channel, this, &Class::Func)`
3. 고급: `RegisterListener(Channel, FGameplayMessageListenerParams<T>)`

### 타입 안전
- 수신 측 등록 타입 저장 → 브로드캐스트 시 `StructType->IsChildOf(ListenerStructType)` 검증
- 타입 불일치 → 에러 로그 후 콜백 스킵

### Lyra 활용
- `LyraHealthSet::PostGameplayEffectExecute` → `BroadcastMessage(TAG_Lyra_Damage_Message, FLyraVerbMessage)`
- AttributeSet은 수신자를 모름. HUD·킬피드 등이 각자 RegisterListener로 구독

---

## 22. TargetData — 타겟팅 결과 패킷 & ASC 저장 구조

> 출처: `Engine/Plugins/Runtime/GameplayAbilities/.../GameplayAbilityTargetTypes.h`, `AbilitySystemComponent_Abilities.cpp`  
> Lyra: `AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`, `AbilitySystem/LyraAbilitySystemComponent.cpp:520`  
> 상세 문서: `doc/gas/ability_task/02_target_data.md`

### FGameplayAbilityTargetData
- `USTRUCT` + 가상 함수 → UObject 없이 폴리모픽
- `GetActors()`, `GetHitResult()`, `GetEndPoint()`, `GetOrigin()` 가상 함수로 타겟 정보 추출
- `ApplyGameplayEffectSpec()` — TargetData 안의 모든 타겟에 GE 일괄 적용
- `FGameplayAbilityTargetDataHandle`으로 감싸서 사용 (`TArray<TSharedPtr<...>, TInlineAllocator<1>>`)

### ASC가 AbilityTargetDataMap에 캐싱하는 이유
- 클라→서버 RPC 타이밍이 GA 실행 흐름과 비동기: RPC 도착 시 GA가 이미 다른 단계
- `AbilityTargetDataMap` 키: `(FGameplayAbilitySpecHandle, FPredictionKey)` 쌍
- 값: `FAbilityReplicatedDataCache` — TargetData, ApplicationTag, bTargetConfirmed, bTargetCancelled, TargetSetDelegate, PredictionKey

### WaitTargetData 두 경로
- RPC 먼저 도착 → `CallReplicatedTargetDataDelegatesIfSet()` 즉시 발동
- RPC 미도착 → `AbilityTargetDataSetDelegate`에 바인딩 대기, 나중에 `ServerSetReplicatedTargetData_Implementation`에서 Broadcast

### LyraAbilitySystemComponent::GetAbilityTargetData (cpp:520)
```cpp
AbilityTargetDataMap.Find(FGameplayAbilitySpecHandleAndPredictionKey(Handle, PredKey))
  → ReplicatedData->TargetData 반환
```

### FLyraGameplayAbilityTargetData_SingleTargetHit
- `FGameplayAbilityTargetData_SingleHit` 서브클래스
- `int32 CartridgeID` 추가 — 산탄총 펠릿처럼 한 발사에서 나온 여러 히트를 묶기 위한 ID

---

## 19. InitAbilityActorInfo / InitFromActor 내부 동작

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:140`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayAbilityTypes.cpp:23`

### InitAbilityActorInfo (AbilitySystemComponent_Abilities.cpp:140)

```cpp
void UAbilitySystemComponent::InitAbilityActorInfo(AActor* InOwnerActor, AActor* InAvatarActor)
{
    AbilityActorInfo->InitFromActor(InOwnerActor, InAvatarActor, this);  // 핵심
    SetOwnerActor(InOwnerActor);
    SetAvatarActor_Direct(InAvatarActor);

    // AvatarActor가 처음 설정된 경우 지연된 GameplayCue 실행
    if ((WasAbilityActorNull || PrevAvatarActor == nullptr) && InAvatarActor != nullptr)
        HandleDeferredGameplayCues(&ActiveGameplayEffects);

    // Avatar 변경 시 모든 GA에 OnAvatarSet 호출
    if (AvatarChanged)
        for (FGameplayAbilitySpec& Spec : ActivatableAbilities.Items)
            Spec.Ability->OnAvatarSet(AbilityActorInfo.Get(), Spec);
}
```

### InitFromActor (GameplayAbilityTypes.cpp:23) — 핵심

네트워크 커넥션을 초기화하는 것이 아니라 **PlayerController 포인터를 AbilityActorInfo에 캐싱**하는 함수.

```cpp
void FGameplayAbilityActorInfo::InitFromActor(AActor* InOwnerActor, AActor* InAvatarActor, ...)
{
    OwnerActor = InOwnerActor;
    AvatarActor = InAvatarActor;

    // OwnerActor에서 시작해 Owner 체인을 타고 올라가며 PlayerController 탐색
    AActor* TestActor = InOwnerActor;
    while (TestActor)
    {
        if (APlayerController* CastPC = Cast<APlayerController>(TestActor))
        {
            PlayerController = CastPC;
            break;
        }
        if (APawn* Pawn = Cast<APawn>(TestActor))
        {
            PlayerController = Cast<APlayerController>(Pawn->GetController());  // ← 핵심
            break;
        }
        TestActor = TestActor->GetOwner();
    }

    // PlayerController를 처음 찾은 경우 ASC에 알림
    if (OldPC == nullptr && PlayerController.IsValid())
        InAbilitySystemComponent->OnPlayerControllerSet();

    // AvatarActor에서 SkeletalMeshComponent, MovementComponent 캐시
    SkeletalMeshComponent = AvatarActorPtr->FindComponentByClass<USkeletalMeshComponent>();
    MovementComponent = AvatarActorPtr->FindComponentByClass<UMovementComponent>();
}
```

### 왜 Controller 설정 이후에 InitAbilityActorInfo를 호출해야 하는가

`PossessedBy()` 이전에 호출하면 `Pawn->GetController()`가 `nullptr` 반환
→ `AbilityActorInfo.PlayerController`가 `nullptr`로 캐시됨
→ 이후 `IsLocallyControlled()` 오작동:

```cpp
bool FGameplayAbilityActorInfo::IsLocallyControlled() const
{
    if (const APlayerController* PC = PlayerController.Get())  // nullptr이면 false 반환
        return PC->IsLocalController();
    ...
}
```

→ 클라이언트 예측 여부, GA 실행 주체 결정 등 GAS 전체 흐름 오작동  
→ `TryActivateAbilitiesOnSpawn()` 시점에도 잘못된 판단으로 OnSpawn GA 오발동 가능

재호출하면 그 시점의 `GetController()`가 유효하므로 캐시 갱신됨 — `OnRep_PlayerState`, `AcknowledgePossession`에서 재호출하는 이유.

### PlayerController 탐색 경로 — 서버와 클라이언트가 다름

**ASC가 Pawn에 있는 경우**  
`InitAbilityActorInfo(Pawn, Pawn)` → `InOwnerActor = Pawn`  
→ `Cast<APawn>(TestActor)` 성공 → `Pawn->GetController()` 로 탐색  
→ `PossessedBy()` 이후에야 `GetController()`가 유효하므로 그 시점에 초기화

**ASC가 PlayerState에 있는 경우**  
`InitAbilityActorInfo(PlayerState, Character)` → `InOwnerActor = PlayerState`  
→ PlayerState는 Pawn도 PlayerController도 아님 → `TestActor = TestActor->GetOwner()` 실행  
→ PlayerState의 `Owner`는 PlayerController (엔진이 PlayerState 생성 시 Controller가 소유)  
→ 한 단계 올라가면 바로 PlayerController 발견

클라이언트 접속 시 생성 순서:
```
1. 클라이언트 접속 요청
2. 서버: GameMode::Login() → 서버 측 PlayerController 생성 (Authority)
3. 서버 신호 → 클라이언트: 로컬 PlayerController 생성 (AutonomousProxy)
4. (한참 뒤) 서버: PlayerState 생성 → 전체 클라이언트에 복제
5. 서버: Pawn 생성 → 복제
```

PlayerController는 PlayerState보다 훨씬 먼저 생긴다.  
`OnRep_PlayerState()` 발동 시점 = PlayerState 복제 완료, 이때 PlayerController는 이미 존재.  
→ `OnRep_PlayerState`를 기다리는 이유는 PlayerState 때문이고, 이 시점에 두 조건 모두 자동 충족.

---

## 18. 언리얼 UI 파이프라인 — Slate / UMG

> 출처:  
> `C:/UE_5.7/Engine/Source/Runtime/Launch/Private/LaunchEngineLoop.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/SlateCore/Private/Widgets/SWidget.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/UMG/Private/UserWidget.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/UMG/Private/Components/Widget.cpp`  
> 전체 문서: `doc/unrealCore/ui_pipeline.md`

### 계층 구조

```
UMG (UWidget/UUserWidget, UObject 기반)
    → TakeWidget() → SWidget (Slate, TSharedRef 기반)
        → OnPaint() → FSlateWindowElementList (드로우 명령)
            → Renderer->DrawWindows() → RHI/GPU
```

### 엔진 루프 연결점

```cpp
// LaunchEngineLoop.cpp:5890, 5960
FEngineLoop::Tick()
    FSlateApplication::Get().Tick(ESlateTickType::PlatformAndInput)  // 입력
    FSlateApplication::Get().Tick(ESlateTickType::TimeAndWidgets)    // 렌더
```

### TickAndDrawWidgets 내 두 Pass

```
PrivateDrawWindows()
    ① DrawPrepass()   — SWidget::SlatePrepass() → CacheDesiredSize() → ComputeDesiredSize()
                        바텀업으로 DesiredSize 계산
    ② DrawWindowAndChildren() — SWidget::Paint() → Tick(조건부) → OnPaint()
                                드로우 명령을 FSlateWindowElementList에 추가
    Renderer->DrawWindows() → GPU 제출
```

### TakeWidget 브릿지 (핵심)

```cpp
// Widget.cpp:999
UWidget::TakeWidget_Private()
    if (!MyWidget.IsValid())
        PublicWidget = RebuildWidget()  // SWidget 생성 (처음만)
        MyWidget = PublicWidget         // 약한 참조 캐시
    if (UUserWidget)
        SafeGCWidget = SNew(SObjectWidget, this)[PublicWidget]  // GC 방지 래퍼
```

- `SObjectWidget`: UUserWidget을 GC 루트에 묶어 Slate 트리에 살아있는 동안 수거 방지

### 슬레이트 절전

- 사용자 입력 없고 `RegisterActiveTimer()` 없으면 `DrawWindows()` 스킵
- 애니메이션 재생 중인 위젯은 `RegisterActiveTimer()` 필수

### SWidget::Tick 호출 조건

`Paint()` 내부에서 `EWidgetUpdateFlags::NeedsTick` 플래그 있는 위젯만 호출.  
UUserWidget에서 Tick 이벤트 사용 시 자동 세팅됨.

---

## 20. UGameplayTagsManager — 구조, 초기화 시점, 동적 태그

> 출처:  
> `C:/UE_5.7/Engine/Source/Runtime/GameplayTags/Classes/GameplayTagsManager.h`  
> `C:/UE_5.7/Engine/Source/Runtime/GameplayTags/Private/GameplayTagsManager.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/GameplayTags/Private/GameplayTagsModule.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/GameplayTags/Public/NativeGameplayTags.h`

### 싱글톤 패턴

```cpp
// GameplayTagsManager.h:337
inline static UGameplayTagsManager& Get()
{
    if (SingletonManager == nullptr)
        InitializeManager();
    return *SingletonManager;
}
static UGameplayTagsManager* SingletonManager;  // GC 면제(AddToRoot)된 UObject
```

### 초기화 시점

```
모듈 로드 (엔진 초기화 초반)
  → FGameplayTagsModule::StartupModule()
      → UGameplayTagsManager::Get()  // 첫 호출 → InitializeManager()
          → NewObject<UGameplayTagsManager>() + AddToRoot()
          → LoadGameplayTagTables()   // ini, DataTable 로드
          → ConstructGameplayTagTree() // 태그 트리 빌드
          → OnPostEngineInit에 DoneAddingNativeTags() 바인딩

엔진 초기화 완료 (PostEngineInit)
  → DoneAddingNativeTags()  // 이후 태그 추가 잠금 (bDoneAddingNativeTags = true)
```

### 동적 태그 추가/제거

| 방법 | 가능 시점 | 비고 |
|---|---|---|
| `AddNativeGameplayTag()` (레거시) | PostEngineInit 이전까지만 | `ensure(!bDoneAddingNativeTags)` 로 잠김 |
| `FNativeGameplayTag` (권장) | 모듈 생존 기간 동안 자유롭게 | 생성자에서 자동 등록, 소멸자에서 자동 해제 |
| INI / DataTable | 에디터에서만 | 런타임 고정 |

`FNativeGameplayTag`는 `UE_DEFINE_GAMEPLAY_TAG` 매크로로 cpp에 static 변수로 선언.  
모듈 로드 시 생성자 → Manager에 등록, 모듈 언로드 시 소멸자 → 자동 해제.  
Lyra GameFeature 플러그인들이 자신의 태그를 플러그인 수명과 함께 관리하는 메커니즘.

---

## 21. LooseGameplayTag vs GE 태그 — 복제 차이

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AbilitySystemComponent.h:650`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent.cpp:1773`

### AddLooseGameplayTag 기본값 = 복제 안 함

```cpp
// AbilitySystemComponent.h:650
inline void AddLooseGameplayTag(
    const FGameplayTag& GameplayTag,
    int32 Count = 1,
    EGameplayTagReplicationState TagRepState = EGameplayTagReplicationState::None  // ← 기본값
)
// 주석: "It is up to the calling GameCode to make sure these tags are added on clients/server where necessary"
```

`TagRepState = None`이면 로컬 `GameplayTagCountContainer`에만 추가되고 `ReplicatedLooseTags`에 들어가지 않는다.

### GE는 복제가 내장된 이유

| Replication Mode | GE 태그 복제 경로 |
|---|---|
| Full / Mixed | `ActiveGameplayEffects` 자체 복제 → 클라이언트가 GE 받아 태그 직접 적용 |
| Minimal | GE는 복제 안 됨 → 태그만 `MinimalReplicationTags`에 담아 복제 (`COND_SkipOwner`) |

GE 시스템은 Replication Mode를 보고 어떤 복제 채널을 쓸지 자동 결정. 태그 부여와 복제가 묶음으로 처리됨.

### LooseGameplayTag를 복제하려면

```cpp
// ReplicatedLooseTags 채널로 복제 (COND_None)
ASC->AddLooseGameplayTag(Tag, 1, EGameplayTagReplicationState::AllClients);

// Minimal 모드 전용 헬퍼 (MinimalReplicationTags 채널)
ASC->AddMinimalReplicationGameplayTag(Tag);
```

---

## 22. GE를 통해서만 Attribute를 수정해야 하는 이유 — PredictionKey와 롤백

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayPrediction.h:64-208`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayEffect.h:1410`

### 예측(Prediction) — 클라이언트 선행 실행

서버 응답 대기 없이 클라이언트가 먼저 결과를 적용하고, 이후 서버와 맞추는 방식.

```
클라이언트: GA 발동 → GE로 Attribute 즉시 변경 + 서버에 RPC
서버: 수신 → 유효하면 동일 GE 적용, 아니면 거부
클라이언트: 확인 수신 → 일치하면 유지, 거부면 롤백
```

### FPredictionKey — 예측 추적 단위

클라이언트가 예측 행동마다 발급하는 고유 ID.
GE 적용 시 함께 담긴다.

```cpp
FActiveGameplayEffect {
    FGameplayEffectSpec Spec;
    FPredictionKey PredictionKey;  // GameplayEffect.h:1410
}
```

- 서버 복제본이 도착할 때 PredictionKey 대조
- **일치**: 예측 확인 → 클라이언트 GE 유지
- **거부**: `NewRejectedDelegate` 발동 → 해당 키의 GE 전부 롤백

### 직접 수정이 예측 불가능한 이유

```cpp
AttributeSet->Stamina = AttributeSet->Stamina - 10;  // PredictionKey 없음
// → 거부 시 롤백 대상을 식별할 수 없음
```

GE를 거쳐야 변경이 PredictionKey에 묶여 추적·롤백 가능.
직접 수정은 메모리 덮어쓰기라 엔진이 추적할 방법이 없다.

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

---

## 32. Ongoing Tag Requirements — GE 억제(Inhibit) 메커니즘

> 소스 경로 (UE 5.7):
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayEffectComponents/TargetTagRequirementsGameplayEffectComponent.cpp`
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent.cpp` (line 283~333)
> - `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayEffect.cpp` (line 4491~4508, 4664~, 3561~)

### 핵심 플래그: `FActiveGameplayEffect::bIsInhibited`

```
bIsInhibited = false  →  GE 활성 (Modifier + Tag 적용 중)
bIsInhibited = true   →  GE 억제 (Modifier + Tag 제거. FActiveGameplayEffect는 컨테이너에 잔류)
```

### UE 5.3+ 구조 변경

UE 5.3부터 `OngoingTagRequirements`는 `UTargetTagRequirementsGameplayEffectComponent`가 처리.
`FActiveGameplayEffect::CheckOngoingTagRequirements`는 현재 빈 함수.

**GE 추가 시** (`OnActiveGameplayEffectAdded`):
- `OngoingTagRequirements`의 모든 태그에 `RegisterGameplayTagEvent` 구독
- 초기 활성 여부 = `OngoingTagRequirements.RequirementsMet(TagContainer)`

**태그 변경 시** (`OnTagChanged`):
- `RemovalTagRequirements` 충족 → `RemoveActiveGameplayEffect` (영구 제거)
- `OngoingTagRequirements` 불충족 → `SetActiveGameplayEffectInhibit(..., true)` (억제)
- `OngoingTagRequirements` 재충족 → `SetActiveGameplayEffectInhibit(..., false)` (재활성)

**GE 제거 시** (`OnGameplayEffectRemoved`): 모든 태그 이벤트 구독 해제.

### `SetActiveGameplayEffectInhibit` 동작

```cpp
if (ActiveGE->bIsInhibited != bInhibit)  // 상태 변화 시에만 처리
{
    if (bInhibit)
        RemoveActiveGameplayEffectGrantedTagsAndModifiers(...)  // Modifier 제거 + Tag 해제 + GameplayCue Remove
    else
        AddActiveGameplayEffectGrantedTagsAndModifiers(...)     // Modifier 재등록 + Tag 재적용 + GameplayCue Add

    EventSet.OnInhibitionChanged.Broadcast(Handle, bIsInhibited);
}
```

### `bIsInhibited` 영향 범위

| 코드 | 동작 |
|---|---|
| `InternalExecutePeriodicGameplayEffect` | 억제 중이면 틱 실행 안 함 |
| `UpdateAllAggregatorModMagnitudes` | 억제 중이면 Modifier 재계산 건너뜀 |
| `InternalOnActiveGameplayEffectRemoved` | 억제 중인 GE 제거 시 Tag/Modifier 정리 불필요 |
| `GetActiveEffectCount(bEnforceOnGoingCheck=true)` | 억제 중인 GE를 카운트에서 제외 |

### 초기화 트릭 (GameplayEffect.cpp:4501)

```cpp
Effect.bIsInhibited = true;  // 강제로 억제 상태로 시작
Owner->SetActiveGameplayEffectInhibit(Handle, !bActive, bInvokeGameplayCueEvents);
// bActive=true → !bActive=false → 억제 해제(켜기) 경로 실행
// → 모든 초기 추가가 동일한 코드 경로를 타도록 보장
```

---

## 33. UGameplayEffect 함수 구조 및 CDO 호출 패턴

> 소스: `Engine/.../GameplayAbilities/Public/GameplayEffect.h:2096`, `Private/GameplayEffect.cpp:937~991`

### 함수 분류

| 종류 | 예시 |
|---|---|
| UObject 라이프사이클 | `PostLoad`, `PostCDOCompiled`, `PreSave` |
| GAS 프레임워크 훅 | `CanApply`, `OnAddedToActiveContainer`, `OnExecuted`, `OnApplied` |
| 읽기 전용 Accessor | `GetGrantedTags`, `GetAssetTags`, `FindComponent<T>` |
| Deprecated 변환 헬퍼 (private) | `ConvertTagRequirementsComponent` 등 (UE 5.3 마이그레이션용) |

### GAS 프레임워크 훅은 GEComponents 위임만 함

```cpp
bool UGameplayEffect::CanApply(...) const
{
    for (const UGameplayEffectComponent* GEComponent : GEComponents)
        if (!GEComponent->CanGameplayEffectApply(...)) return false;
    return true;
}
// OnAddedToActiveContainer, OnExecuted, OnApplied 모두 동일한 패턴
```

### CDO 직접 호출 구조

`FGameplayEffectSpec::Def`가 항상 CDO를 가리킴. 프레임워크가 CDO 메서드를 직접 호출:

```
Spec.Def->CanApply(...)
Spec.Def->OnAddedToActiveContainer(...)
Spec.Def->OnExecuted(...)   // GameplayEffect.cpp:3308
Spec.Def->OnApplied(...)
```

"GE에 로직을 넣지 말라" = `UGameplayEffect` 서브클래싱해서 훅을 오버라이드하지 말라는 의미.
실제 로직은 `GEComponents` 안의 `UGameplayEffectComponent` 서브클래스에 넣는다.

---

## N. GetLifetimeReplicatedProps 내부 동작 — 매크로 전개

소스: `Engine/Source/Runtime/Engine/Public/Net/UnrealNetwork.h`, `CoreUObject/Public/UObject/CoreNet.h`

### 호출 시점

인스턴스당 매번 호출되지 않는다. `FRepLayout::InitFromObjectClass(UClass*)` 에서 **클래스당 1회**만 호출된다.
결과로 빌드된 `Cmds[]`는 동일 클래스의 모든 인스턴스가 공유한다.

### DOREPLIFETIME 전개 (UnrealNetwork.h:259)

```cpp
DOREPLIFETIME(AMyActor, Health)
  →  GetReplicatedProperty(StaticClass(), c::StaticClass(), GET_MEMBER_NAME_CHECKED(c,v))
       // CPF_Net 플래그 검사 — UPROPERTY(Replicated) 없으면 Fatal
  →  RegisterReplicatedLifetimeProperty(FProperty*, OutLifetimeProps, FDoRepLifetimeParams())
       // OutLifetimeProps.AddUnique( FLifetimeProperty{RepIndex, COND_None, REPNOTIFY_OnChanged} )
```

### FLifetimeProperty 구조 (CoreNet.h:299)

```cpp
class FLifetimeProperty {
    uint16 RepIndex;                               // UHT가 Replicated 프로퍼티마다 자동 부여
    ELifetimeCondition Condition;                  // COND_None, COND_OwnerOnly 등
    ELifetimeRepNotifyCondition RepNotifyCondition; // OnChanged / Always
    bool bIsPushBased;
};
```

`RepIndex`는 UHT가 컴파일 시점에 매기는 고유 번호. 패킷에 필드명 대신 이 번호가 들어간다.

### DOREPLIFETIME_CONDITION 전개 (UnrealNetwork.h:277)

`FDoRepLifetimeParams.Condition = cond` 설정 후 `DOREPLIFETIME_WITH_PARAMS` 호출하는 것과 동일.
RepLayout이 틱마다 해당 Connection이 조건을 만족하는지 확인 후 패킷 포함 여부 결정.

### FDoRepLifetimeParams 전체 옵션 (UnrealNetwork.h:134)

```cpp
struct FDoRepLifetimeParams {
    ELifetimeCondition Condition        = COND_None;
    ELifetimeRepNotifyCondition RepNotifyCondition = REPNOTIFY_OnChanged;
    bool bIsPushBased                  = false;
};
```

---

## 34. UGameplayTask 핵심 내부 구조

> 소스: `C:/Program Files/Epic Games/UE_5.7/Engine/Source/Runtime/GameplayTasks/`  
> 상세 문서: `doc/gas/ability_task/00_gameplay_task.md`

### 상태 머신 (EGameplayTaskState)
`Uninitialized → AwaitingActivation → Active ↔ Paused → Finished`

### ReadyForActivation() 분기 (GameplayTask.cpp:56)
- `RequiresPriorityOrResourceManagement() == false` → `PerformActivation()` 즉시 호출
- 우선순위/리소스 필요 → `TasksComponent->AddTaskReadyForActivation()` 큐 등록
- TasksComponent 없음 → `EndTask()` 즉시 종료

### PerformActivation() 흐름 (GameplayTask.cpp:275)
`TaskState = Active` → `Activate()` 호출 → `IsFinished() == false`이면 `TasksComponent->OnGameplayTaskActivated()`

### 종료 경로 두 가지
- `EndTask()` → `OnDestroy(false)` : 태스크 스스로 종료
- `TaskOwnerEnded()` → `bOwnerFinished = true` + `OnDestroy(true)` : 소유자(GA) 종료로 인한 정리

### OnDestroy() (GameplayTask.cpp:206)
`TaskState = Finished` → `TasksComponent->OnGameplayTaskDeactivated()` → `MarkAsGarbage()`  
오버라이드 시 `Super::OnDestroy()`를 **마지막**에 호출해야 함 (`MarkAsGarbage` 간섭 방지)

### bSimulatedTask vs bIsSimulating (GameplayTask.h:344~348)
- `bSimulatedTask`: 설정값. `true`이면 `IsSupportedForNetworking() = true` → 복제 허용
- `bIsSimulating`: 런타임 상태. `InitSimulatedTask()` 내부에서 `true`로 세팅됨

### Activate() 베이스 구현
VLOG 출력만 하고 아무것도 하지 않는다. 개발자가 오버라이드해서 실제 로직 구현.

---

## 19. EAbilityGenericReplicatedEvent — GA 인스턴스 신호 채널

**출처**:  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/GameplayAbilityTargetTypes.h:662`  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:3880`  
`Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

### 정의

활성화된 GA 인스턴스에 묶인 신호 슬롯. 이름의 "Replicated"는 클라↔서버 RPC로 동기화되기 때문.

```cpp
namespace EAbilityGenericReplicatedEvent
{
    enum Type : int
    {
        GenericConfirm,           // WaitConfirm
        GenericCancel,            // WaitCancel
        InputPressed,             // WaitInputPress
        InputReleased,            // WaitInputRelease
        GenericSignalFromClient,  // 범용 클라→서버
        GenericSignalFromServer,  // 범용 서버→클라
        GameCustom1 ~ GameCustom6 // 게임 전용 확장
    };
}
```

### 저장소

ASC의 `AbilityTargetDataMap`:
- key: `FGameplayAbilitySpecHandle + FPredictionKey` (GA 인스턴스 단위 분리)
- value: `FAbilityReplicatedDataCache` → `GenericEvents[MAX]` 슬롯 배열
  - 각 슬롯: `bTriggered`, `VectorPayload`, `Delegate(FSimpleMulticastDelegate)`

### InvokeReplicatedEvent (로컬 발동)

1. `GenericEvents[Type].bTriggered = true` 저장
2. Delegate가 바인딩 돼 있으면 즉시 Broadcast
3. 아무도 구독 안 하면 `bTriggered=true`만 저장 → 나중에 `CallReplicatedEventDelegateIfSet()`으로 사후 처리 가능 (타이밍 레이스 방지)

### RPC 동기화

- 클라→서버: `ServerSetReplicatedEvent()` → 서버에서 `InvokeReplicatedEvent()` 호출
- 서버→클라: `ClientSetReplicatedEvent()` → 클라에서 `InvokeReplicatedEvent()` 호출

### WaitInputPress 구독 방법

```cpp
// Activate()
DelegateHandle = ASC->AbilityReplicatedEventDelegate(
    EAbilityGenericReplicatedEvent::InputPressed,
    GetAbilitySpecHandle(), GetActivationPredictionKey()
).AddUObject(this, &ThisClass::OnPressCallback);

// 이미 발동됐을 경우 사후 처리
if (IsForRemoteClient())
    ASC->CallReplicatedEventDelegateIfSet(InputPressed, handle, predKey);
```

### 호출 체인 (ProcessAbilityInput → WaitInputPress)

```
AbilitySpec->IsActive() == true
  → AbilitySpecInputPressed()
      → InvokeReplicatedEvent(InputPressed, handle, predKey)
          → GenericEvents[InputPressed].Delegate.Broadcast()
              → WaitInputPress::OnPressCallback()
                  → OnPress.Broadcast(ElapsedTime)
                  → (IsPredictingClient) ServerSetReplicatedEvent()
                  → EndTask()
```

---

## 20. TargetData 실제 사용 — LyraGameplayAbility_RangedWeapon

**출처**:
`Source/LyraGame/AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`
`Source/LyraGame/Weapons/LyraGameplayAbility_RangedWeapon.cpp`
`Source/LyraGame/AbilitySystem/LyraGameplayEffectContext.h`

### TargetData 서브클래스

`FLyraGameplayAbilityTargetData_SingleTargetHit` : `FGameplayAbilityTargetData_SingleTargetHit` 상속
- 추가 필드: `int32 CartridgeID` — 같은 탄창(산탄총 등) 총알들을 묶는 ID
- `NetSerialize`: 부모 호출 후 `Ar << CartridgeID`
- `AddTargetDataToContext` 오버라이드: CartridgeID를 `FLyraGameplayEffectContext`에 주입

### EffectContext 연결

`FLyraGameplayEffectContext` : `FGameplayEffectContext` 상속
- 추가 필드: `int32 CartridgeID = -1`
- `AddTargetDataToContext()`에서 `ExtractEffectContext(Context)->CartridgeID = CartridgeID` 로 복사됨
- 이후 ExecCalc/GameplayCue/AttributeSet 콜백에서 `ExtractEffectContext()`로 꺼내 사용 가능

### 전체 흐름 (Task 없이 수동 처리 방식)

```
ActivateAbility()
  → AbilityTargetDataSetDelegate 구독 (OnTargetDataReadyCallback)
  → StartRangedWeaponTargeting()
      → PerformLocalTargeting() — 클라이언트 레이캐스트
      → FLyraGameplayAbilityTargetData_SingleTargetHit 생성 + HitResult/CartridgeID 채움
      → Handle.Add(NewTargetData)
      → OnTargetDataReadyCallback() 직접 호출

OnTargetDataReadyCallback()
  → (클라이언트) CallServerSetReplicatedTargetData() RPC — PredictionKey 포함
  → (서버) AbilityTargetDataSetDelegate.Broadcast() → 동일 콜백 재진입
  → CommitAbility() → OnRangedWeaponTargetDataReady() Blueprint이벤트 (GE Apply)
  → ConsumeClientReplicatedTargetData() — ASC 내부 캐시 정리

EndAbility()
  → Delegate.Remove(Handle)
  → ConsumeClientReplicatedTargetData()
```

**특이점**: `WaitTargetData` AbilityTask를 쓰지 않고, `AbilityTargetDataSetDelegate`를 GA가 직접 구독하는 수동 방식이다. TargetData 전송 타이밍을 GA가 직접 제어한다.


## 35. WaitNetSync — UAbilityTask_NetworkSyncPoint 구현

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/Abilities/Tasks/AbilityTask_NetworkSyncPoint.h`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_NetworkSyncPoint.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/Abilities/Tasks/AbilityTask_WaitInputPress.cpp`

### 핵심 요약

- GASDoc의 "WaitNetSync"는 `UAbilityTask_NetworkSyncPoint` 클래스이며, 정적 팩토리 `WaitNetSync()` 함수로 생성
- Lyra 소스에는 WaitNetSync 직접 사용 코드 없음 (GASDoc의 Sprint GA 예시는 별도 샘플 프로젝트)

### SyncType

```cpp
enum class EAbilityTaskNetSyncType : uint8
{
    BothWait,        // 클라-서버 둘 다 대기
    OnlyServerWait,  // 서버만 대기 (클라는 신호 보내고 즉시 계속) ← Scoped Prediction 용도
    OnlyClientWait   // 클라만 대기
};
```

### Activate() 핵심 로직

```cpp
FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient()); // 새 Key 발급

if (IsPredictingClient()) {
    if (SyncType != OnlyServerWait)   ReplicatedEventToListenFor = GenericSignalFromServer;
    if (SyncType != OnlyClientWait)   ASC->ServerSetReplicatedEvent(GenericSignalFromClient, ..., ASC->ScopedPredictionKey);
} else if (IsForRemoteClient()) {
    if (SyncType != OnlyClientWait)   ReplicatedEventToListenFor = GenericSignalFromClient;
    if (SyncType != OnlyServerWait)   ASC->ClientSetReplicatedEvent(GenericSignalFromServer, ...);
}
// 리스닝 대상 없으면 SyncFinished() 즉시 호출
```

OnlyServerWait 시: 클라는 RPC 보내고 SyncFinished() 즉시 → 서버는 GenericSignalFromClient 수신 후 재개

### 입력 태스크 내장 Sync Point (WaitInputPress.cpp)

```cpp
void UAbilityTask_WaitInputPress::OnPressCallback() {
    FScopedPredictionWindow ScopedPrediction(ASC, IsPredictingClient()); // ← 내장 Key 발급
    if (IsPredictingClient())
        ASC->ServerSetReplicatedEvent(InputPressed, ..., ASC->ScopedPredictionKey);
    // WaitNetSync와 동일한 패턴을 콜백 내부에서 직접 수행
}
```

### 적용 판단 기준

- 입력 태스크(WaitInputPress 등) 콜백 이후 → 내장 Sync Point 있음, 추가 불필요
- WaitDelay 콜백 이후 GE 적용 → `WaitNetSync(OnlyServerWait)` 삽입 필요
- 예측 GE 두 번 재생(redo 문제) → GE Apply 직전 `WaitNetSync(OnlyServerWait)` 삽입

## 36. PredictionKey 생명주기 & 롤백 메커니즘

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayPrediction.h`

### Key 두 종류

| 구분 | Activation Prediction Key | Scoped Prediction Key |
|---|---|---|
| 생성 | `InternalTryActivateAbility()` | 각 콜백 `FScopedPredictionWindow` |
| 유효 범위 | `ActivateAbility()` 콜스택 | 콜백 동기 실행 범위 |
| 취득 | `GetActivationPredictionKey()` | `ASC->ScopedPredictionKey` |

### Dependent Key 체인

`FScopedPredictionWindow(ASC, true)` 클라이언트 생성 시 `GenerateDependentPredictionKey()` 호출:
```cpp
KeyType Previous = Current;   // Key#1 기억
Base = Current;                // Base = Key#1
GenerateNewPredictionKey();    // Current = Key#2
FPredictionKeyDelegates::AddDependency(Key#2, Key#1);
// → "Key#1 Reject 시 Key#2도 Reject" 등록 (클라이언트 내부에만 존재)
```

### GA 거부 시 롤백

1. 서버 → `ClientActivateAbilityFailed(Key#1)` RPC
2. `BroadcastRejectedDelegate(Key#1)` → Key#1 GE 롤백
3. `AddDependency`가 등록한 `Reject(Key#2)` 연쇄 호출 → Key#2 GE 롤백
4. Key#3, #4... 전부 같은 방식으로 연쇄
5. `EndAbility()` → 모든 AbilityTask 정리

### 뒤늦은 Input RPC
GA 종료 후 `ServerSetReplicatedEvent` 도착 시 → 델리게이트 해제 상태 → Broadcast 무시, 사이드 이펙트 없음

**핵심**: 연쇄 롤백은 서버 통신 없이 클라이언트 `FPredictionKeyDelegates` 맵에서 순수하게 처리됨.

## 37. AbilitySystemGlobals — 역할, 접근, 서브클래싱

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AbilitySystemGlobals.h`
- `Source/LyraGame/AbilitySystem/LyraAbilitySystemGlobals.h/.cpp`

### 세 가지 역할

1. **프로젝트 전용 타입 주입** — 가장 중요한 역할
   - GAS 내부가 `FGameplayEffectContext`, `FGameplayAbilityActorInfo` 등을 `AllocXxx()` 가상함수로 new함
   - 서브클래스에서 오버라이드 → 프로젝트 전용 타입으로 교체

2. **공유 리소스 허브** — `GetGameplayCueManager()`, `GetGlobalCurveTable()`, `GetGameplayTagResponseTable()`, `TargetDataStructCache`, `EffectContextStructCache`

3. **전역 실패 태그** — `ActivateFailCooldownTag`, `ActivateFailCostTag`, `ActivateFailTagsBlockedTag` 등

### 접근

```cpp
UAbilitySystemGlobals& Globals = UAbilitySystemGlobals::Get();
// 내부: IGameplayAbilitiesModule::Get().GetAbilitySystemGlobals()
// 게임 전체 싱글톤
```

### Lyra 서브클래싱

`ULyraAbilitySystemGlobals : UAbilitySystemGlobals`
- `AllocGameplayEffectContext()` 하나만 오버라이드 → `new FLyraGameplayEffectContext()` 반환
- `FLyraGameplayEffectContext`는 CartridgeID 등 Lyra 전용 데이터 보유

### 등록 방법

- UE 5.4 이하: `DefaultGame.ini`의 `AbilitySystemGlobalsClassName`
- UE 5.5+: Project Settings → Gameplay Abilities Settings UI

### InitGlobalData()

- UE 5.2 이하: `TargetData` 사용 시 수동 호출 필수 (미호출 시 ScriptStructCache 오류)
- UE 5.3+: 자동 호출

## 38. GA Tags — Source / Owner / Target 구분 & 두 실행 경로

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:1786`
**상세 문서**: `doc/gas/gameplay_ability/06_tags.md`

### Source / Owner / Target 구분

```cpp
const FGameplayTagContainer* SourceTags = TriggerEventData ? &TriggerEventData->InstigatorTags : nullptr;
const FGameplayTagContainer* TargetTags = TriggerEventData ? &TriggerEventData->TargetTags : nullptr;
```

| 용어 | 실제 데이터 |
|---|---|
| Owner | `ASC->GetOwnedGameplayTags()` — GA 소유 캐릭터 자신의 태그 |
| Source | `FGameplayEventData::InstigatorTags` — 이벤트 발신자 태그 |
| Target | `FGameplayEventData::TargetTags` — 이벤트 대상 태그 |

### 두 실행 경로

**경로 1 — 직접 활성화** (`TryActivateAbilityByClass/Tag/Handle`):
- `InternalTryActivateAbility(..., nullptr, nullptr)` — TriggerEventData = nullptr
- Source/Target = nullptr → Required/Blocked 검사 생략
- 발동 주체가 자기 자신뿐인 경우 (점프, 대쉬, 기본 공격)

**경로 2 — 이벤트 트리거** (`SendGameplayEventToActor`):
- GA `Triggers[]` 배열에 GameplayTag + `TriggerSource = GameplayEvent` 등록 필요
- `SendGameplayEventToActor → HandleGameplayEvent → TriggerAbilityFromGameplayEvent → InternalTryActivateAbility(..., &TriggerEventData)`
- `FGameplayEventData`에 Instigator/Target/TargetData 포함
- Source/Target Required/Blocked Tags 검사 활성화
- 외부 컨텍스트(발신자+대상)가 있는 경우 (처형기, 콤보 연계, 무기 히트 반응)
