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

### Lyra 확장
- `ALyraWorldSettings::DefaultGameplayExperience` — 레벨별 기본 Experience 에셋
- `ALyraGameMode::HandleMatchAssignmentIfNotExpectingOne()` — URL > DeveloperSettings > CommandLine > WorldSettings > 하드코딩 폴백 순으로 ExperienceId 결정
- `ALyraGameState`가 `ULyraExperienceManagerComponent` 보유 → Experience 로드 + GameFeature 활성화
