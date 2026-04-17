# ModularGameplay 플러그인

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponent.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/PawnComponent.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkInitStateInterface.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponentManager.h`  
> Lyra 활용: `Character/LyraPawnExtensionComponent.h`, `Character/LyraHeroComponent.h`

---

## 한 줄 요약

ModularGameplay는 런타임에 Actor에 컴포넌트를 동적으로 주입하고, 여러 컴포넌트의 초기화 순서를 GameplayTag 기반 상태 머신으로 조율하는 UE5 공식 플러그인이다.

---

## 클래스 계층

```
UActorComponent
  └─ UGameFrameworkComponent          (ModularGameplay 플러그인 제공)
        └─ UPawnComponent
```

둘 다 얇은 래퍼다. 실질적인 기능은 `UGameFrameworkComponentManager`와 `IGameFrameworkInitStateInterface`에 있다.

---

## UGameFrameworkComponent

**파일**: `GameFrameworkComponent.h`  
**역할**: 게임 프레임워크 Actor(PlayerState, GameState 등)에 붙는 컴포넌트들의 공통 베이스.

`UActorComponent`에서 추가된 것:

| 메서드 | 설명 |
|--------|------|
| `GetGameInstance<T>()` | Owner Actor를 통해 GameInstance에 접근 |
| `GetGameInstanceChecked<T>()` | null 불허 버전 (check() 포함) |
| `HasAuthority()` | Owner의 Role이 `ROLE_Authority`인지 확인 |
| `GetWorldTimerManager()` | 월드 타이머 매니저 반환 |

같은 헤더에 `TComponentIterator<T>` / `TConstComponentIterator<T>` 유틸리티도 정의돼 있다.  
`IsRegistered()` 조건을 걸며 Actor의 등록된 컴포넌트를 순회한다.

### 왜 GetGameInstance가 여기 있나?

`GetGameInstance<T>()`는 특별한 접근 권한을 부여하는 게 아니다. 단순히 긴 접근 체인의 축약형이다.

```cpp
// 원래 코드
GetOwner()->GetWorld()->GetGameInstance<UMyGameInstance>();

// 헬퍼 내부 구현 (그대로임)
AActor* Owner = GetOwner();
return Owner ? Owner->GetGameInstance<T>() : nullptr;
```

**`UActorComponent`에 없는 이유**: `UActorComponent`는 물리/렌더/충돌 등 GameInstance와 전혀 무관한 컴포넌트까지 전부 포함하는 범용 베이스다. 거기에 게임 프레임워크 전용 헬퍼를 넣으면 책임 분리 위반이다.

`UGameFrameworkComponent`는 이름 자체가 "게임 프레임워크 Actor(PlayerState, GameState 등)에 붙는 컴포넌트"라는 의미를 선언하며, 그 맥락에서 자주 쓰이는 접근 패턴을 헬퍼로 제공한 것이다.

> **수명 관계**: GameInstance는 레벨 전환에도 살아있는 유일한 전역 객체다. 이 컴포넌트들이 붙는 PlayerState, GameState, Pawn은 모두 GameInstance보다 수명이 짧다. 즉, 이 헬퍼는 "수명이 짧은 컴포넌트에서 수명이 긴 전역 객체로 안전하게 올라가는" 관용구를 감싼 것이다.

---

## UPawnComponent

**파일**: `PawnComponent.h`  
**역할**: Pawn에 붙는 컴포넌트 전용 베이스. Pawn 소유 구조에 맞는 타입 안전 접근자 추가.

`UGameFrameworkComponent`에서 추가된 것 (모두 template 함수):

| 메서드 | 반환 | 설명 |
|--------|------|------|
| `GetPawn<T>()` | `T*` | Owner를 Pawn으로 캐스팅 |
| `GetPawnChecked<T>()` | `T*` | null 불허 버전 |
| `GetPlayerState<T>()` | `T*` | Pawn의 PlayerState 접근. 클라이언트에서 복제 전에는 null 가능 |
| `GetController<T>()` | `T*` | Pawn의 Controller 접근. 클라이언트에서는 보통 null |

모두 `TPointerIsConvertibleFromTo<T, BaseClass>::Value`를 `static_assert`로 강제해 컴파일 타임 타입 안전성을 보장한다.

> **왜 상속받는가?**  
> `UActorComponent::GetOwner()`는 `AActor*`를 반환한다. Pawn 컴포넌트에서 매번 `Cast<APawn>(GetOwner())`를 작성하는 반복을 없애기 위한 얇은 편의 레이어다.

---

## IGameFrameworkInitStateInterface

**파일**: `GameFrameworkInitStateInterface.h`  
**역할**: 컴포넌트가 자신의 초기화 진행 상태를 `UGameFrameworkComponentManager`에 등록하고, 다른 Feature의 상태 변경을 구독하는 인터페이스.

### 핵심 메서드

```
[등록/해제]
RegisterInitStateFeature()          ← OnRegister()에서 호출, Manager에 Feature 등록
UnregisterInitStateFeature()        ← EndPlay()에서 호출, 등록 해제

[상태 전이]
CanChangeInitState(Manager, Current, Desired) → bool   ← 전이 가능 여부 커스텀 로직
HandleChangeInitState(Manager, Current, Desired)        ← 전이 직전 실행할 로직
TryToChangeInitState(DesiredState) → bool              ← Can 체크 → Handle 실행 → Manager 통보
ContinueInitStateChain(ChainArray) → FGameplayTag      ← 순서대로 연속 전이 시도, 도달한 최종 상태 반환

[조회]
GetFeatureName() → FName           ← 이 Feature의 이름
GetInitState() → FGameplayTag      ← 현재 상태
HasReachedInitState(DesiredState)  ← 해당 상태 이상에 도달했는지

[구독]
OnActorInitStateChanged(Params)    ← 같은 Actor의 다른 Feature 상태 변경 시 콜백
BindOnActorInitStateChanged(FeatureName, RequiredState, bCallIfReached)
CheckDefaultInitialization()       ← override해서 기본 초기화 경로 진행 (ContinueInitStateChain 활용)
CheckDefaultInitializationForImplementers()  ← 같은 Actor의 모든 구현체에게 CheckDefault 호출
```

---

## UGameFrameworkComponentManager

**파일**: `GameFrameworkComponentManager.h`  
**상속**: `UGameInstanceSubsystem` → GameInstance 당 하나, 자동 생성/소멸

**두 가지 완전히 독립된 역할**을 한 클래스가 담당한다.

---

### 역할 1: 컴포넌트 동적 주입 시스템

GameFeature나 외부 시스템이 특정 Actor 클래스에 컴포넌트를 런타임으로 추가/제거할 수 있다.

```
[요청 등록]
AddComponentRequest(ActorClass, ComponentClass) → TSharedPtr<FComponentRequestHandle>

[Actor가 수신자로 등록]
AddReceiver(Actor) / RemoveReceiver(Actor)
  ─ Actor가 BeginPlay에서 직접 호출해 "나 이제 컴포넌트 받을 준비 됨" 선언
  ─ Lyra: ULyraPawnExtensionComponent::OnRegister() → GameFrameworkComponentManager::AddGameFrameworkComponentReceiver()

[요청 제거]
FComponentRequestHandle 소멸 → 자동으로 해당 컴포넌트 제거 (RAII)
```

요청은 레퍼런스 카운트된다. 같은 (ActorClass, ComponentClass) 요청이 여러 번 들어와도 컴포넌트는 하나만 생기고, 마지막 Handle이 소멸될 때 제거된다.

#### 확장 이벤트 시스템

```
AddExtensionHandler(ActorClass, Delegate)  ← 특정 Actor 클래스에 이벤트 핸들러 등록
SendExtensionEvent(Actor, EventName)       ← 이벤트 발송

// 내장 이벤트 이름 (FName)
NAME_ReceiverAdded      ← AddReceiver 직후
NAME_ReceiverRemoved    ← RemoveReceiver 시
NAME_ExtensionAdded     ← 핸들러 등록 시
NAME_ExtensionRemoved   ← 핸들러 제거 시
NAME_GameActorReady     ← 게임 정의: "Actor가 확장 받을 준비 완료" (게임에서 직접 발송)
```

---

### 역할 2: InitState 조율 시스템

같은 Actor 위에 있는 여러 Feature(컴포넌트)들이 서로의 초기화 진행 상태를 감지하며 순서 있게 초기화할 수 있다.

```
[전역 상태 순서 등록]
RegisterInitState(NewState, bAddBefore, ExistingState)
  ─ InitStateOrder 배열에 GameplayTag로 된 상태를 순서대로 삽입

[상태 변경]
ChangeFeatureInitState(Actor, FeatureName, Implementer, FeatureState)
  ─ StateChangeQueue에 넣어 재귀 콜백 방지
  ─ 완료 후 구독 중인 delegate 전부 호출

[상태 조회]
GetInitStateForFeature(Actor, FeatureName) → FGameplayTag
HasFeatureReachedInitState(Actor, FeatureName, RequiredState) → bool
HaveAllFeaturesReachedInitState(Actor, RequiredState) → bool   ← "모두 도달했냐" 체크
GetImplementerForFeature(Actor, FeatureName) → UObject*

[구독]
RegisterAndCallForActorInitState(Actor, FeatureName, RequiredState, Delegate)
RegisterAndCallForClassInitState(ActorClass, FeatureName, RequiredState, Delegate)
```

---

## Lyra에서의 활용

두 컴포넌트 모두 `UPawnComponent + IGameFrameworkInitStateInterface` 이중 상속.

```
ALyraCharacter
  ├─ ULyraPawnExtensionComponent   Feature 이름: "PawnExtension"
  └─ ULyraHeroComponent            Feature 이름: "Hero"
```

### 초기화 상태 4단계 (GameplayTag)

```
InitState_Spawned
  → InitState_DataAvailable    (PawnData 준비됨, Controller 보유)
  → InitState_DataInitialized  (같은 Actor의 모든 Feature가 DataAvailable 도달)
  → InitState_GameplayReady    (AbilitySystem 초기화 완료)
```

### ULyraPawnExtensionComponent의 역할

```
OnRegister()
  └─ RegisterInitStateFeature()           ← Manager에 "PawnExtension" Feature 등록
     AddGameFrameworkComponentReceiver()  ← 컴포넌트 주입 수신자로 등록

OnActorInitStateChanged(Params)
  └─ "Hero 포함 다른 Feature가 DataAvailable에 도달했나?"
     HaveAllFeaturesReachedInitState(DataAvailable) → true
       └─ TryToChangeInitState(DataInitialized)

HandleChangeInitState(...→ DataInitialized)
  └─ InitializeAbilitySystem()            ← ASC Avatar 설정 (핵심)

CheckDefaultInitialization()
  └─ ContinueInitStateChain([Spawned, DataAvailable, DataInitialized, GameplayReady])
```

### ULyraHeroComponent의 역할

```
OnRegister()
  └─ RegisterInitStateFeature()     ← Manager에 "Hero" Feature 등록

OnActorInitStateChanged(Params)
  └─ "PawnExtension이 DataInitialized에 도달했나?"
     → TryToChangeInitState(DataInitialized)

HandleChangeInitState(...→ DataInitialized)
  └─ InitializePlayerInput()        ← IMC 등록 + 입력 바인딩
     SendExtensionEvent(NAME_BindInputsNow)  ← 추가 입력 바인딩 구독자에게 통보
```

### 전체 초기화 흐름 요약

```
ALyraCharacter::BeginPlay()
  │
  ├─ PawnExtensionComponent::OnRegister() → RegisterInitStateFeature("PawnExtension")
  ├─ HeroComponent::OnRegister()          → RegisterInitStateFeature("Hero")
  │
  ├─ PawnExtensionComponent::BeginPlay()
  │     CheckDefaultInitialization()
  │       → ContinueInitStateChain → DataAvailable 도달
  │         → OnActorInitStateChanged 전파 → Hero가 감지
  │           → Hero도 DataAvailable 도달
  │             → PawnExtension: HaveAllFeaturesReached(DataAvailable) == true
  │               → DataInitialized 전이
  │                 → InitializeAbilitySystem()   ← ASC Avatar 설정
  │                   → GameplayReady 전이
  │
  └─ HeroComponent::BeginPlay()
        OnActorInitStateChanged: PawnExtension == DataInitialized
          → Hero: DataInitialized 전이
            → InitializePlayerInput()
              → SendExtensionEvent(NAME_BindInputsNow)
```

---

## Lyra 구현체 목록

`UGameFrameworkComponent` / `UPawnComponent`를 상속받은 Lyra의 모든 컴포넌트.

```
UGameFrameworkComponent
  ├─ ULyraHealthComponent                           (Character/)
  └─ UPawnComponent
        ├─ ULyraPawnExtensionComponent              (Character/) + IGameFrameworkInitStateInterface
        ├─ ULyraHeroComponent                       (Character/) + IGameFrameworkInitStateInterface
        ├─ ULyraEquipmentManagerComponent           (Equipment/)
        └─ ULyraPawnComponent_CharacterParts        (Cosmetics/)
```

---

### ULyraHealthComponent

**파일**: `Character/LyraHealthComponent.h`  
**베이스**: `UGameFrameworkComponent` (Pawn이 아닌 Actor에도 붙을 수 있어 PawnComponent 미사용)

체력 관련 로직을 Pawn에서 분리한 컴포넌트. `ULyraHealthSet`의 델리게이트를 구독해 외부에 체력 변화를 전달한다.

**핵심 역할**:
- `InitializeWithAbilitySystem(ASC)` — `ULyraHealthSet`을 꺼내 델리게이트 바인딩
- `GetHealth()` / `GetMaxHealth()` / `GetHealthNormalized()` — 체력 조회 API
- `StartDeath()` / `FinishDeath()` — 사망 시퀀스 2단계 관리
- `DamageSelfDestruct()` — 낙사 등 강제 사망 처리

**사망 상태** (`ELyraDeathState`, Replicated):
```
NotDead → DeathStarted → DeathFinished
```

**외부 노출 델리게이트**:
| 델리게이트 | 파라미터 | 설명 |
|---|---|---|
| `OnHealthChanged` | HealthComp, OldVal, NewVal, Instigator | 체력 변화 |
| `OnMaxHealthChanged` | 동일 | 최대 체력 변화 |
| `OnDeathStarted` | OwningActor | 사망 시작 |
| `OnDeathFinished` | OwningActor | 사망 완료 |

> `ULyraHealthSet`의 델리게이트(서버 전용, 6파라미터)를 받아 Blueprint에서 쓰기 좋은 형태로 재가공해서 노출하는 어댑터 역할이다.

---

### ULyraPawnExtensionComponent

**파일**: `Character/LyraPawnExtensionComponent.h`  
**베이스**: `UPawnComponent` + `IGameFrameworkInitStateInterface`  
**Feature 이름**: `"PawnExtension"`

모든 Pawn 컴포넌트들의 **초기화 순서 조율자**. 다른 Feature들이 `DataAvailable`에 모두 도달해야만 `DataInitialized`로 전이하며, 그 시점에 ASC Avatar 설정을 수행한다.

**핵심 역할**:
- `SetPawnData(PawnData)` — PawnData 설정, `DataAvailable` 전이 조건
- `InitializeAbilitySystem(ASC, OwnerActor)` — `InitAbilityActorInfo()` 호출, ASC Avatar 설정
- `UninitializeAbilitySystem()` — 리스폰/빙의 해제 시 Avatar 해제
- `HandleControllerChanged()` / `HandlePlayerStateReplicated()` — 상태 변화 시 `CheckDefaultInitialization()` 재호출
- `OnAbilitySystemInitialized_RegisterAndCall()` — ASC 초기화 완료 구독 (HeroComponent 등이 사용)

---

### ULyraHeroComponent

**파일**: `Character/LyraHeroComponent.h`  
**베이스**: `UPawnComponent` + `IGameFrameworkInitStateInterface`  
**Feature 이름**: `"Hero"`

**플레이어 입력과 카메라**를 담당하는 컴포넌트. PawnExtensionComponent가 `DataInitialized`에 도달해야 활성화된다.

**핵심 역할**:
- `InitializePlayerInput(InputComponent)` — IMC 등록 + Native/Ability 입력 바인딩
- `SetAbilityCameraMode()` / `ClearAbilityCameraMode()` — GA가 카메라 모드를 재정의할 때 사용
- `AddAdditionalInputConfig()` / `RemoveAdditionalInputConfig()` — 모드별 추가 입력 설정
- `IsReadyToBindInputs()` — 입력 바인딩 준비 완료 여부
- `NAME_BindInputsNow` 이벤트 발송 — 외부 시스템이 추가 바인딩을 걸 수 있게 알림

---

### ULyraEquipmentManagerComponent

**파일**: `Equipment/LyraEquipmentManagerComponent.h`  
**베이스**: `UPawnComponent`

Pawn이 장착한 장비 목록을 관리한다. `FLyraEquipmentList`(FFastArraySerializer)로 장비 목록을 복제한다.

**핵심 역할**:
- `EquipItem(EquipmentDefinition)` → `ULyraEquipmentInstance*` — 장비 장착, AbilitySet 부여 (Authority only)
- `UnequipItem(Instance)` — 장비 해제, AbilitySet 제거 (Authority only)
- `GetFirstInstanceOfType<T>()` — 특정 타입 장비 인스턴스 조회
- `GetEquipmentInstancesOfType()` — 특정 타입 전체 목록 조회

**복제 구조**:
```
FLyraEquipmentList (FFastArraySerializer)
  └─ TArray<FLyraAppliedEquipmentEntry>
        ├─ EquipmentDefinition  (복제됨)
        ├─ Instance             (복제됨)
        └─ GrantedHandles       (NotReplicated — 서버 전용, AbilitySet 제거용)
```

`ReplicateSubobjects()`를 오버라이드해 `ULyraEquipmentInstance` 서브오브젝트도 함께 복제한다.

---

### ULyraPawnComponent_CharacterParts

**파일**: `Cosmetics/LyraPawnComponent_CharacterParts.h`  
**베이스**: `UPawnComponent`

Pawn에 붙는 **코스메틱 파츠(헬멧, 의상 등) 관리** 컴포넌트. 게임플레이 로직과 무관한 외형 전담.

**핵심 역할**:
- `AddCharacterPart(Part)` → `FLyraCharacterPartHandle` — 파츠 추가, 클라이언트에 ChildActor 스폰 (Authority only)
- `RemoveCharacterPart(Handle)` / `RemoveAllCharacterParts()` — 파츠 제거
- `GetCombinedTags(Prefix)` — 장착된 모든 파츠의 GameplayTag 합집합 반환 (애니메이션 선택 등에 활용)
- `BodyMeshes` (`FLyraAnimBodyStyleSelectionSet`) — 파츠 태그 기반으로 골격 메시를 선택하는 규칙

**복제 구조**:
```
FLyraCharacterPartList (FFastArraySerializer, Transient)
  └─ TArray<FLyraAppliedCharacterPartEntry>
        ├─ Part (복제됨)
        ├─ PartHandle (NotReplicated — 서버 전용 핸들 인덱스)
        └─ SpawnedComponent (NotReplicated — 클라이언트 전용 ChildActorComponent)
```

> `EquipmentManagerComponent`와 구조가 유사하다 (FFastArraySerializer + 서버/클라이언트 전용 필드 분리). 차이는 장비는 AbilitySet을 부여하지만 파츠는 외형(ChildActor)만 스폰한다.

---

## 설계 의도

| 문제 | 해결 |
|------|------|
| GameFeature 플러그인이 코어 Actor를 몰라도 컴포넌트를 붙이고 싶다 | `AddComponentRequest` — Actor 클래스 이름만으로 요청 |
| 여러 컴포넌트가 서로를 직접 참조하지 않고 초기화 순서를 맞추고 싶다 | InitState 시스템 — GameplayTag 상태 + 구독 패턴 |
| 컴포넌트 추가/제거를 명시적 관리 없이 안전하게 하고 싶다 | `FComponentRequestHandle` RAII — Handle 소멸 시 자동 제거 |
| Pawn 컴포넌트에서 매번 `Cast<APawn>(GetOwner())` 반복을 없애고 싶다 | `UPawnComponent::GetPawn<T>()` 헬퍼 |
