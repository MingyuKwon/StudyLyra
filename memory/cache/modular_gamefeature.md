# ModularGameplay / GameFeature / Experience

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

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
