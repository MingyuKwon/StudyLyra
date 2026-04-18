# GameFeatures 플러그인

> 출처:  
> `Engine/Plugins/Experimental/GameFeatures/`  
> `Source/LyraGame/GameModes/LyraExperienceDefinition.h`  
> `Source/LyraGame/GameModes/LyraExperienceManagerComponent.h/.cpp`  
> `Source/LyraGame/GameFeatures/GameFeatureAction_AddAbilities.h`

---

## ModularGameplay와의 관계

두 플러그인은 **별개**지만 함께 사용하도록 설계됐다.

```
GameFeatures 플러그인          — "언제/왜 플러그인을 켜고 끄는가" (트리거)
  └─ UGameFeaturesSubsystem   ← 플러그인 활성화/비활성화 관리
  └─ UGameFeatureAction       ← 활성화 시 실행할 작업 정의

ModularGameplay 플러그인       — "어떻게 컴포넌트를 주입하는가" (메커니즘)
  └─ UGameFrameworkComponentManager
       └─ AddComponentRequest() / AddReceiver()
```

`UGameFeatureAction_AddComponents`가 연결고리다.  
GameFeatures가 트리거를 당기면 ModularGameplay가 실제로 컴포넌트를 인스턴스에 꽂는다.

---

## 핵심 클래스

### UGameFeaturesSubsystem

`UEngineSubsystem` 서브클래스 — 엔진당 하나, 자동 생성.

GameFeature 플러그인의 **상태 머신**을 관리한다.

```
플러그인 상태 전환:
  Uninitialized
    → Installed    (플러그인 설치됨, 아직 코드 미로드)
    → Registered   (플러그인 등록, 메타데이터 로드)
    → Loaded       (에셋 로드 완료)
    → Active       (기능 활성화 — GameFeatureAction 실행)
```

핵심 API:
```cpp
// 플러그인 로드 + 활성화 (비동기)
UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(PluginURL, Callback);

// 플러그인 이름 → URL 조회
UGameFeaturesSubsystem::Get().GetPluginURLByName(PluginName, /*out*/ PluginURL);

// 비활성화
UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(PluginURL);
```

---

### UGameFeatureAction

GameFeature 플러그인이 활성화/비활성화될 때 실행할 작업을 정의하는 **추상 베이스 클래스**.

```cpp
class UGameFeatureAction : public UObject
{
    virtual void OnGameFeatureRegistering()   {}  // Registered 진입 시
    virtual void OnGameFeatureLoading()       {}  // Loaded 진입 시
    virtual void OnGameFeatureActivating(...) {}  // Active 진입 시  ← 주로 여기서 작업
    virtual void OnGameFeatureDeactivating(...){}  // Active 탈출 시
    virtual void OnGameFeatureUnregistering() {}  // Unregistered 진입 시
};
```

**Lyra의 GameFeatureAction 구현체**:

| 클래스 | 하는 일 |
|--------|---------|
| `UGameFeatureAction_AddComponents` | Actor에 컴포넌트 주입 (ModularGameplay 연동) |
| `UGameFeatureAction_AddAbilities` | Actor에 GA/AttributeSet/AbilitySet 부여 |
| `UGameFeatureAction_AddInputBinding` | 입력 바인딩 추가 |
| `UGameFeatureAction_AddInputContextMapping` | InputMappingContext 추가 |
| `UGameFeatureAction_AddWidget` | HUD 위젯 추가 |

---

### ULyraExperienceDefinition (DataAsset)

Lyra에서 GameFeatures를 트리거하는 핵심 데이터 에셋.

```cpp
// LyraExperienceDefinition.h
class ULyraExperienceDefinition : public UPrimaryDataAsset
{
    // 이 Experience가 필요로 하는 GameFeature 플러그인 이름 목록
    TArray<FString> GameFeaturesToEnable;

    // 기본 폰 데이터
    TObjectPtr<const ULyraPawnData> DefaultPawnData;

    // 이 Experience가 직접 실행할 Action 목록
    TArray<TObjectPtr<UGameFeatureAction>> Actions;

    // 재사용 가능한 Action 묶음 (여러 Experience가 공유 가능)
    TArray<TObjectPtr<ULyraExperienceActionSet>> ActionSets;
};
```

에디터에서 게임 모드를 정의할 때 "어떤 GameFeature 플러그인이 필요한가" + "어떤 Action을 실행할 것인가"를 이 에셋에 설정한다.

---

## Lyra에서 실제로 일어나는 흐름

### 플러그인 활성화 흐름

```
게임 모드 결정 (서버)
  → AGameMode가 ULyraExperienceDefinition 선택
  → ULyraExperienceManagerComponent::SetCurrentExperience()
       → StartExperienceLoad()
            → AssetManager로 에셋 비동기 로드
            → OnExperienceLoadComplete() 콜백

OnExperienceLoadComplete()
  → Experience.GameFeaturesToEnable 목록 순회
  → UGameFeaturesSubsystem::Get().GetPluginURLByName(PluginName, URL)
  → UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(URL, Callback)
       → 플러그인 상태: Installed → Registered → Loaded → Active
       → Active 진입 시 UGameFeatureAction::OnGameFeatureActivating() 실행
            → UGameFeatureAction_AddComponents::OnGameFeatureActivating()
                 → UGameFrameworkComponentManager::AddComponentRequest(ActorClass, ComponentClass)
            → UGameFeatureAction_AddAbilities::OnGameFeatureActivating()
                 → AddExtensionHandler() 등록 — Actor가 준비되면 AbilitySet 부여

모든 플러그인 로드 완료
  → OnExperienceFullLoadCompleted()
       → Experience.Actions 실행 (Action 직접 호출)
       → OnExperienceLoaded 델리게이트 Broadcast
            → 다른 시스템들이 "Experience 준비됐다"는 신호 수신
```

### 상태 전환 다이어그램

```
ELyraExperienceLoadState:

  Unloaded
    → Loading          (에셋 비동기 로드 중)
    → LoadingGameFeatures  (GameFeature 플러그인 활성화 중)
    → ExecutingActions (Action 직접 실행 중)
    → Loaded           ← 여기서 OnExperienceLoaded Broadcast
```

---

## 왜 Experience 시스템이 필요한가

게임 모드마다 필요한 기능 세트가 다르다.

```
B급 배틀로얄 모드:
  - 장비 시스템 O
  - 부활 시스템 X
  - 수축하는 존 시스템 O

팀 데스매치 모드:
  - 장비 시스템 O
  - 부활 시스템 O
  - 수축하는 존 시스템 X
```

기존 방식이면 각 게임 모드마다 AGameMode 서브클래스를 만들고, 조건부 코드를 넣어야 한다.  
Experience 방식은 **DataAsset으로 기능 조합을 선언**한다.

```
Experience_BattleRoyale:
  GameFeaturesToEnable: ["ShooterCore", "BattleRoyaleFeature"]
  Actions: [AddEquipmentAction, AddZoneAction]

Experience_TeamDeathmatch:
  GameFeaturesToEnable: ["ShooterCore", "TDMFeature"]
  Actions: [AddEquipmentAction, AddRespawnAction]
```

코드 변경 없이 에디터에서 조합만 바꾸면 완전히 다른 게임 모드가 된다.

---

## UGameFeatureAction 사용 예시

### 패턴 1 — AddComponentRequest (컴포넌트 주입)

가장 단순한 형태. Actor에 컴포넌트를 붙이고, 비활성화 시 자동으로 떼어낸다.

```cpp
UCLASS()
class UMyGameFeatureAction_AddComponents : public UGameFeatureAction
{
    GENERATED_BODY()

    // 활성화 시 요청 핸들을 보관
    TArray<TSharedPtr<FComponentRequestHandle>> ActiveRequests;

public:
    virtual void OnGameFeatureActivating(FGameFeatureActivatingContext& Context) override
    {
        UGameFrameworkComponentManager* Manager = 
            UGameInstance::GetSubsystem<UGameFrameworkComponentManager>(GEngine->GetCurrentPlayWorld()->GetGameInstance());

        // "ALyraCharacter 인스턴스에 UMyComponent를 붙여라" 요청
        ActiveRequests.Add(
            Manager->AddComponentRequest(ALyraCharacter::StaticClass(), UMyComponent::StaticClass())
        );
    }

    virtual void OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context) override
    {
        // Handle 소멸 → AddComponentRequest 자동 취소 → 컴포넌트 자동 제거
        ActiveRequests.Empty();
    }
};
```

---

### 패턴 2 — AddExtensionHandler (Actor 준비 후 작업)

컴포넌트 추가가 아니라 **"Actor가 준비됐을 때 어떤 작업을 하겠다"**는 콜백을 등록하는 패턴.  
`UGameFeatureAction_AddAbilities`가 이 방식을 사용한다.

```cpp
void UGameFeatureAction_AddAbilities::AddToWorld(const FWorldContext& WorldContext, ...)
{
    UGameFrameworkComponentManager* ComponentMan = ...;

    for (const FGameFeatureAbilitiesEntry& Entry : AbilitiesList)
    {
        // "ALyraPlayerState Actor가 특정 이벤트를 받으면 HandleActorExtension 호출해라"
        TSharedPtr<FComponentRequestHandle> Handle = ComponentMan->AddExtensionHandler(
            Entry.ActorClass,                                      // 대상 Actor 클래스
            FExtensionHandlerDelegate::CreateUObject(this, &ThisClass::HandleActorExtension, EntryIndex, ChangeContext)
        );
        ActiveData.ComponentRequests.Add(Handle);
    }
}

void UGameFeatureAction_AddAbilities::HandleActorExtension(AActor* Actor, FName EventName, ...)
{
    if (EventName == NAME_ExtensionAdded || EventName == NAME_LyraAbilityReady)
    {
        AddActorAbilities(Actor, Entry, ActiveData);  // GA/AttributeSet/AbilitySet 부여
    }
    else if (EventName == NAME_ExtensionRemoved || EventName == NAME_ReceiverRemoved)
    {
        RemoveActorAbilities(Actor, ActiveData);      // GA/AttributeSet 제거
    }
}
```

`AddComponentRequest`와의 차이:

| | `AddComponentRequest` | `AddExtensionHandler` |
|--|----------------------|----------------------|
| 하는 일 | 컴포넌트 인스턴스 자동 생성/제거 | 이벤트 발생 시 콜백 호출 |
| 사용 시점 | 컴포넌트를 동적으로 붙여야 할 때 | 컴포넌트가 이미 있고 추가 작업(GA 부여 등)이 필요할 때 |

---

### 패턴 3 — WorldActionBase (멀티 월드 지원)

PIE(에디터에서 플레이)에서는 서버/클라이언트가 별도 World로 존재한다.  
`UGameFeatureAction_WorldActionBase`를 상속하면 **현재 존재하는 모든 월드 + 이후 시작되는 월드** 모두에 자동으로 적용된다.

```cpp
// WorldActionBase.cpp
void UGameFeatureAction_WorldActionBase::OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    // 이후 시작되는 GameInstance용 델리게이트 등록
    GameInstanceStartHandles.FindOrAdd(Context) = 
        FWorldDelegates::OnStartGameInstance.AddUObject(this, &ThisClass::HandleGameInstanceStart, ...);

    // 현재 살아있는 모든 WorldContext에 즉시 적용
    for (const FWorldContext& WorldContext : GEngine->GetWorldContexts())
    {
        if (Context.ShouldApplyToWorldContext(WorldContext))
            AddToWorld(WorldContext, Context);  // 서브클래스가 구현
    }
}
```

구현 방법:
```cpp
UCLASS()
class UMyGameFeatureAction : public UGameFeatureAction_WorldActionBase
{
    // AddToWorld만 구현하면 됨 — 월드 반복 처리는 부모가 담당
    virtual void AddToWorld(const FWorldContext& WorldContext, const FGameFeatureStateChangeContext& ChangeContext) override
    {
        UWorld* World = WorldContext.World();
        if (!World || !World->IsGameWorld()) return;

        // 월드별 처리 로직
        UGameFrameworkComponentManager* Manager = ...;
        Manager->AddComponentRequest(...);
    }
};
```

`Lyra의 GameFeatureAction_AddAbilities`, `AddInputBinding`, `AddWidget` 등이 모두 이 패턴을 쓴다.

---

### FPerContextData 패턴 — 컨텍스트별 상태 분리

PIE에서 서버/클라이언트 World가 따로 존재하기 때문에, 같은 Action 인스턴스가 여러 컨텍스트에서 실행된다.  
Lyra는 `TMap<FGameFeatureStateChangeContext, FPerContextData>`로 컨텍스트마다 상태를 독립적으로 관리한다.

```cpp
// AddAbilities.h
struct FPerContextData
{
    TMap<AActor*, FActorExtensions> ActiveExtensions;     // Actor별 부여된 핸들
    TArray<TSharedPtr<FComponentRequestHandle>> ComponentRequests;  // RAII 핸들
};

TMap<FGameFeatureStateChangeContext, FPerContextData> ContextData;
```

활성화/비활성화 시:
```cpp
void OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    FPerContextData& ActiveData = ContextData.FindOrAdd(Context);  // 컨텍스트별 독립 데이터
    Super::OnGameFeatureActivating(Context);  // → AddToWorld() 호출
}

void OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context)
{
    Super::OnGameFeatureDeactivating(Context);
    FPerContextData* ActiveData = ContextData.Find(Context);
    Reset(*ActiveData);  // 이 컨텍스트(월드)에서만 제거
}
```

---

## 요약

- **UGameFeaturesSubsystem**: 플러그인 상태 머신 관리 (Installed → Active)
- **UGameFeatureAction**: 활성화/비활성화 시 실행할 작업의 추상 인터페이스
- **UGameFeatureAction_WorldActionBase**: 멀티 월드(PIE) 지원 베이스 — `AddToWorld()`만 구현
- **ULyraExperienceDefinition**: 어떤 플러그인이 필요한지 DataAsset으로 선언
- **ULyraExperienceManagerComponent**: Experience 로드 → 플러그인 활성화 → Action 실행 조율
- GameFeatures는 **트리거**, ModularGameplay는 **메커니즘** — 함께 써야 완성
