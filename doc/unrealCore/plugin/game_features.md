# GameFeatures 플러그인

> 출처:  
> `Engine/Plugins/Experimental/GameFeatures/`  
> `Source/LyraGame/GameFeatures/` (전체)  
> `Source/LyraGame/GameModes/LyraExperienceManagerComponent.h/.cpp`

---

## 왜 "Feature"인가 — 네이밍 의도

언리얼 플러그인은 원래 **엔진 기능 확장** 단위다 (GAS, CommonUI, Chaos 등).  
GameFeature 플러그인은 그 구조를 **게임 콘텐츠 패키지** 배포 단위로 재활용한다.

```
일반 플러그인:  엔진 기능 추가  (GAS, Chaos, CommonUI...)
GameFeature:   게임 콘텐츠 묶음 (ShooterCore, TopDownArena...)
```

"Feature"는 기술적 단위(플러그인)가 아니라 **게임 기획 단위(기능)**를 나타낸다.  
`GameFeaturesToEnable` = "켤 플러그인 목록"이 아니라 "이 Experience에서 켤 게임 기능 목록".

ShooterCore 플러그인 안에는:
- `.uplugin` — 플러그인 메타
- `Content/` — 총기 에셋, 애니메이션, 사운드
- `Source/` — 사격 관련 GA, GE 코드
- `GameFeatureData` — 활성화 시 실행할 Action 목록

이 전체가 "슈터 기능 팩" 하나다.

---

## 왜 Action만 켜고 끄는 게 아닌가

"Action만 동적으로 켰다 껐다 하면 되지 않냐"는 질문이 자연스럽다.  
핵심 차이는 **에셋과 코드의 메모리 로드 단위**다.

| | Action만 제어 | 플러그인 단위 제어 |
|---|---|---|
| C++ 코드 | 빌드 타임에 항상 포함 | 런타임에 로드/언로드 가능 |
| 에셋 (Mesh, Anim, Sound) | 이미 메모리에 있어야 함 | 필요할 때만 로드 |
| 독립 패키징 | 불가 | DLC/모드로 추가 가능 |

Epic이 플러그인 구조를 택한 이유는 **독립 빌드, 의존성 선언, 에셋 격리** 인프라가 이미 갖춰져 있어서다.  
새로 만들 필요 없이 기존 플러그인 시스템을 콘텐츠 팩 개념으로 재활용한 것.

---

## ModularGameplay와의 관계

```
GameFeatures 플러그인          — "언제/왜 플러그인을 켜고 끄는가" (트리거)
  └─ UGameFeaturesSubsystem   ← 플러그인 활성화/비활성화 관리
  └─ UGameFeatureAction       ← 활성화 시 실행할 작업 정의

ModularGameplay 플러그인       — "어떻게 컴포넌트를 주입하는가" (메커니즘)
  └─ UGameFrameworkComponentManager
       └─ AddComponentRequest() / AddExtensionHandler()
```

GameFeatures가 트리거를 당기면 ModularGameplay가 실제로 컴포넌트를 인스턴스에 꽂는다.

---

## 언제 플러그인이 켜지고 꺼지는가

### 켜지는 시점

`LyraExperienceManagerComponent::OnExperienceLoadComplete()` 에서 호출된다.
Experience 에셋 비동기 로드가 끝난 직후다.

```cpp
// LyraExperienceManagerComponent.cpp
void ULyraExperienceManagerComponent::OnExperienceLoadComplete()
{
    // Experience + ActionSet에서 플러그인 이름 수집 → URL로 변환
    GameFeaturePluginURLs.Reset();
    auto CollectGameFeaturePluginURLs = [This=this](const UPrimaryDataAsset* Context, const TArray<FString>& FeaturePluginList)
    {
        for (const FString& PluginName : FeaturePluginList)
        {
            FString PluginURL;
            if (UGameFeaturesSubsystem::Get().GetPluginURLByName(PluginName, /*out*/ PluginURL))
            {
                This->GameFeaturePluginURLs.AddUnique(PluginURL);  // 중복 제거
            }
        }
    };

    CollectGameFeaturePluginURLs(CurrentExperience, CurrentExperience->GameFeaturesToEnable);
    for (const TObjectPtr<ULyraExperienceActionSet>& ActionSet : CurrentExperience->ActionSets)
    {
        CollectGameFeaturePluginURLs(ActionSet, ActionSet->GameFeaturesToEnable);  // ActionSet도 포함
    }

    // 수집된 URL 전부 비동기 활성화
    NumGameFeaturePluginsLoading = GameFeaturePluginURLs.Num();
    if (NumGameFeaturePluginsLoading > 0)
    {
        LoadState = ELyraExperienceLoadState::LoadingGameFeatures;
        for (const FString& PluginURL : GameFeaturePluginURLs)
        {
            ULyraExperienceManager::NotifyOfPluginActivation(PluginURL);  // PIE 참조 카운트
            UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(
                PluginURL,
                FGameFeaturePluginLoadComplete::CreateUObject(this, &ThisClass::OnGameFeaturePluginLoadComplete)
            );
        }
    }
    else
    {
        OnExperienceFullLoadCompleted();  // 플러그인 없으면 바로 다음 단계
    }
}
```

### 꺼지는 시점

`LyraExperienceManagerComponent::EndPlay()` 에서 호출된다.
맵이 언로드되거나 게임이 종료될 때다.

```cpp
// LyraExperienceManagerComponent.cpp
void ULyraExperienceManagerComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    Super::EndPlay(EndPlayReason);

    // 이 Experience가 켰던 플러그인만 끔
    for (const FString& PluginURL : GameFeaturePluginURLs)
    {
        // PIE에서 여러 World가 같은 플러그인을 공유할 수 있음 — 참조 카운트가 0이 될 때만 실제 비활성화
        if (ULyraExperienceManager::RequestToDeactivatePlugin(PluginURL))
        {
            UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(PluginURL);
        }
    }

    // Experience->Actions도 비활성화
    // Action->OnGameFeatureDeactivating() → Action->OnGameFeatureUnregistering()
}
```

### 상태 전환 요약

```
플러그인 상태:
  Uninitialized
    → Installed    (설치됨, 코드 미로드)
    → Registered   (메타데이터 로드)
    → Loaded       (에셋 로드 완료)
    → Active       ← 여기서 UGameFeatureAction::OnGameFeatureActivating() 실행

비활성화:
  Active → Loaded → Registered → Installed
           ← OnGameFeatureDeactivating() / OnGameFeatureUnregistering() 역순 실행
```

---

## 어떻게 플러그인을 켜는가 — UGameFeaturesSubsystem API

```cpp
// 이름 → URL 변환
FString PluginURL;
UGameFeaturesSubsystem::Get().GetPluginURLByName("ShooterCore", /*out*/ PluginURL);

// 비동기 로드 + 활성화
UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(
    PluginURL,
    FGameFeaturePluginLoadComplete::CreateLambda([](const UE::GameFeatures::FResult& Result)
    {
        // 완료 콜백
    })
);

// 비활성화
UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(PluginURL);
```

직접 호출할 일은 거의 없다. Lyra에서는 `LyraExperienceManagerComponent`가 전부 처리한다.

---

## UGameFeatureAction — 액션 베이스 클래스

GameFeature 플러그인이 활성화/비활성화될 때 실행할 작업의 추상 인터페이스.

```cpp
class UGameFeatureAction : public UObject
{
    virtual void OnGameFeatureRegistering()    {}  // Registered 진입 시
    virtual void OnGameFeatureLoading()        {}  // Loaded 진입 시
    virtual void OnGameFeatureActivating(...)  {}  // Active 진입 시 ← 주요 작업
    virtual void OnGameFeatureDeactivating(...){}  // Active 탈출 시
    virtual void OnGameFeatureUnregistering()  {}  // Unregistered 진입 시
};
```

### UGameFeatureAction_WorldActionBase — PIE 멀티 월드 지원

Lyra의 모든 Action이 상속하는 중간 베이스 클래스.
PIE에서 서버/클라이언트 World가 여러 개 존재하는 문제를 해결한다.

```cpp
// GameFeatureAction_WorldActionBase.cpp
void UGameFeatureAction_WorldActionBase::OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    // 이후 시작될 GameInstance를 위해 델리게이트 등록
    GameInstanceStartHandles.FindOrAdd(Context) = FWorldDelegates::OnStartGameInstance.AddUObject(
        this, &UGameFeatureAction_WorldActionBase::HandleGameInstanceStart, FGameFeatureStateChangeContext(Context));

    // 이미 살아있는 모든 WorldContext에 즉시 적용
    for (const FWorldContext& WorldContext : GEngine->GetWorldContexts())
    {
        if (Context.ShouldApplyToWorldContext(WorldContext))
        {
            AddToWorld(WorldContext, Context);  // 서브클래스가 구현
        }
    }
}

void UGameFeatureAction_WorldActionBase::OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context)
{
    // OnStartGameInstance 델리게이트 해제
    FWorldDelegates::OnStartGameInstance.Remove(GameInstanceStartHandles[Context]);
}
```

서브클래스는 `AddToWorld()` 하나만 구현하면 된다. 월드 순회 처리는 부모가 담당.

---

## Lyra GameFeatureAction 구현체 7종

### 1. UGameFeatureAction_AddAbilities
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_AddAbilities.h/.cpp`

Actor에 GA / AttributeSet / AbilitySet을 동적으로 부여/회수한다.

**설정 구조**:
```cpp
UPROPERTY(EditAnywhere, Category="Abilities")
TArray<FGameFeatureAbilitiesEntry> AbilitiesList;

struct FGameFeatureAbilitiesEntry
{
    TSoftClassPtr<AActor> ActorClass;          // 어떤 Actor에 부여할지
    TArray<FLyraAbilityGrant>        GrantedAbilities;    // 개별 GA 목록
    TArray<FLyraAttributeSetGrant>   GrantedAttributes;   // AttributeSet 목록
    TArray<TSoftObjectPtr<const ULyraAbilitySet>> GrantedAbilitySets; // AbilitySet 묶음
};
```

**활성화 흐름**:
```cpp
// AddToWorld() — WorldActionBase가 호출
void UGameFeatureAction_AddAbilities::AddToWorld(const FWorldContext& WorldContext, ...)
{
    UGameFrameworkComponentManager* ComponentMan = ...;

    for (const FGameFeatureAbilitiesEntry& Entry : AbilitiesList)
    {
        // "이 ActorClass 인스턴스가 준비되면 HandleActorExtension을 불러라" 등록
        TSharedPtr<FComponentRequestHandle> Handle = ComponentMan->AddExtensionHandler(
            Entry.ActorClass,
            FExtensionHandlerDelegate::CreateUObject(this, &ThisClass::HandleActorExtension, EntryIndex, ChangeContext)
        );
        ActiveData.ComponentRequests.Add(Handle);  // Handle 소멸 시 자동 해제
    }
}

// Actor가 준비되면 콜백
void UGameFeatureAction_AddAbilities::HandleActorExtension(AActor* Actor, FName EventName, ...)
{
    if (EventName == NAME_ExtensionAdded || EventName == NAME_LyraAbilityReady)
    {
        AddActorAbilities(Actor, Entry, ActiveData);
    }
    else if (EventName == NAME_ExtensionRemoved || EventName == NAME_ReceiverRemoved)
    {
        RemoveActorAbilities(Actor, ActiveData);
    }
}

// 실제 부여 — 서버에서만 실행 (!Actor->HasAuthority() 이면 early out)
void UGameFeatureAction_AddAbilities::AddActorAbilities(AActor* Actor, ...)
{
    UAbilitySystemComponent* ASC = FindOrAddComponentForActor<UAbilitySystemComponent>(Actor, ...);

    // 1. 개별 GA 부여
    for (const FLyraAbilityGrant& Ability : AbilitiesEntry.GrantedAbilities)
    {
        FGameplayAbilitySpec NewAbilitySpec(Ability.AbilityType.LoadSynchronous());
        FGameplayAbilitySpecHandle Handle = ASC->GiveAbility(NewAbilitySpec);
        AddedExtensions.Abilities.Add(Handle);
    }

    // 2. AttributeSet 생성 및 등록
    for (const FLyraAttributeSetGrant& Attributes : AbilitiesEntry.GrantedAttributes)
    {
        UAttributeSet* NewSet = NewObject<UAttributeSet>(ASC->GetOwner(), SetType);
        if (InitData) NewSet->InitFromMetaDataTable(InitData);
        ASC->AddAttributeSetSubobject(NewSet);
    }

    // 3. AbilitySet 일괄 부여 (GA + GE + AttributeSet 묶음)
    for (const TSoftObjectPtr<const ULyraAbilitySet>& SetPtr : AbilitiesEntry.GrantedAbilitySets)
    {
        Set->GiveToAbilitySystem(LyraASC, &AddedExtensions.AbilitySetHandles.AddDefaulted_GetRef());
    }
}

// 회수 — SetRemoveAbilityOnEnd로 실행 중인 GA가 끝날 때까지 대기
void UGameFeatureAction_AddAbilities::RemoveActorAbilities(AActor* Actor, ...)
{
    for (FGameplayAbilitySpecHandle Handle : ActorExtensions->Abilities)
        ASC->SetRemoveAbilityOnEnd(Handle);         // 즉시 제거가 아닌 종료 후 제거

    for (UAttributeSet* Set : ActorExtensions->Attributes)
        ASC->RemoveSpawnedAttribute(Set);

    for (FLyraAbilitySet_GrantedHandles& SetHandle : ActorExtensions->AbilitySetHandles)
        SetHandle.TakeFromAbilitySystem(LyraASC);
}
```

---

### 2. UGameFeatureAction_AddInputBinding
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_AddInputBinding.h/.cpp`

Pawn에 `ULyraInputConfig` (InputAction ↔ GameplayTag 매핑)를 추가/제거한다.

```cpp
UPROPERTY(EditAnywhere, Category="Input")
TArray<TSoftObjectPtr<const ULyraInputConfig>> InputConfigs;
```

```cpp
void AddToWorld(...)
{
    // APawn 인스턴스가 준비되면 HandlePawnExtension 호출
    ComponentMan->AddExtensionHandler(APawn::StaticClass(), HandlePawnExtension);
}

void AddInputMappingForPlayer(APawn* Pawn, ...)
{
    // LyraHeroComponent를 통해 InputConfig 등록
    if (ULyraHeroComponent* HeroComponent = Pawn->FindComponentByClass<ULyraHeroComponent>())
    {
        HeroComponent->AddAdditionalInputConfig(InputConfig);
    }
}
```

---

### 3. UGameFeatureAction_AddInputContextMapping
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_AddInputContextMapping.h/.cpp`

Enhanced Input의 `UInputMappingContext`를 LocalPlayer에 추가/제거한다.

`OnGameFeatureRegistering()` 시점에도 동작한다 (Activated 이전 단계).

```cpp
void OnGameFeatureRegistering() override
{
    // 이미 실행 중인 GameInstance에 즉시 등록
    RegisterInputContextMappingsForGameInstance(GameInstance);
    // 이후 시작될 GameInstance를 위해 델리게이트도 등록
    FWorldDelegates::OnStartGameInstance.AddUObject(this, &ThisClass::HandleGameInstanceStart);
}

void AddInputMappingForPlayer(ULocalPlayer* LocalPlayer, ...)
{
    UEnhancedInputLocalPlayerSubsystem* Subsystem = LocalPlayer->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
    for (const FInputMappingContextAndPriority& Mapping : InputMappings)
    {
        Subsystem->AddMappingContext(Mapping.InputMapping.Get(), Mapping.Priority);
    }
}
```

---

### 4. UGameFeatureAction_AddWidgets
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_AddWidget.h/.cpp`

HUD에 레이아웃 위젯과 슬롯 위젯을 추가/제거한다.

```cpp
UPROPERTY(EditAnywhere, Category="UI")
TArray<FLyraHUDLayoutRequest> Layout;   // CommonUI 레이어에 풀스크린 레이아웃 추가

UPROPERTY(EditAnywhere, Category="UI")
TArray<FLyraHUDElementEntry> Widgets;   // 특정 슬롯에 위젯 추가
```

```cpp
void AddToWorld(...)
{
    // ALyraHUD 인스턴스가 준비되면 AddWidgets 호출
    ComponentMan->AddExtensionHandler(ALyraHUD::StaticClass(), HandleActorExtension);
}

void AddWidgets(AActor* Actor, ...)
{
    ALyraHUD* HUD = CastChecked<ALyraHUD>(Actor);
    ULocalPlayer* LocalPlayer = HUD->GetOwningPlayerController()->Player;

    // 레이아웃 위젯: CommonUI 레이어 스택에 푸시
    for (const FLyraHUDLayoutRequest& Entry : Layout)
    {
        UCommonUIExtensions::PushContentToLayer_ForPlayer(LocalPlayer, Entry.LayerID, Entry.LayoutClass.Get());
    }

    // 슬롯 위젯: UIExtensionSubsystem에 등록
    UUIExtensionSubsystem* ExtSys = HUD->GetWorld()->GetSubsystem<UUIExtensionSubsystem>();
    for (const FLyraHUDElementEntry& Entry : Widgets)
    {
        ExtSys->RegisterExtensionAsWidgetForContext(Entry.SlotID, LocalPlayer, Entry.WidgetClass.Get(), -1);
    }
}

void RemoveWidgets(AActor* Actor, ...)
{
    // 레이아웃: DeactivateWidget()
    // 슬롯: Handle.Unregister()
}
```

---

### 5. UGameFeatureAction_AddGameplayCuePath
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_AddGameplayCuePath.h/.cpp`

GameplayCue 알림을 찾을 디렉터리 경로를 등록한다.
`OnGameFeatureActivating()`을 **오버라이드하지 않는다** — `LyraGameFeaturePolicy`가 `OnGameFeatureRegistering()` 시점에 처리한다.

```cpp
// 기본 경로
UGameFeatureAction_AddGameplayCuePath::UGameFeatureAction_AddGameplayCuePath()
{
    DirectoryPathsToAdd.Add(FDirectoryPath{ TEXT("/GameplayCues") });
}

// LyraGameFeaturePolicy.cpp — OnGameFeatureRegistering에서 처리
for (const UGameFeatureAction* Action : GameFeatureData->GetActions())
{
    if (const UGameFeatureAction_AddGameplayCuePath* CuePath = Cast<...>(Action))
    {
        for (const FDirectoryPath& Dir : CuePath->GetDirectoryPathsToAdd())
        {
            GCM->AddGameplayCueNotifyPath(Dir.Path);
        }
        GCM->InitializeRuntimeObjectLibrary();  // 즉시 재빌드
    }
}
```

---

### 6. UGameFeatureAction_SplitscreenConfig
**파일**: `Source/LyraGame/GameFeatures/GameFeatureAction_SplitscreenConfig.h/.cpp`

분할 화면을 강제로 비활성화한다. **투표 시스템**으로 여러 ActionSet이 충돌 없이 관리된다.

```cpp
UPROPERTY(EditAnywhere, Category="SplitscreenConfig")
bool bDisableSplitscreen;

// 전역 투표 카운트 (static)
static TMap<FObjectKey, int32> GlobalDisableVotes;  // Viewport → 비활성화 요청 수

void AddToWorld(const FWorldContext& WorldContext, ...)
{
    if (bDisableSplitscreen)
    {
        UGameViewportClient* VC = GameInstance->GetGameViewportClient();
        FObjectKey ViewportKey(VC);

        LocalDisableVotes.Add(ViewportKey);    // 이 컨텍스트의 투표 기록
        int32& VoteCount = GlobalDisableVotes.FindOrAdd(ViewportKey);
        VoteCount++;

        if (VoteCount == 1)  // 첫 번째 요청일 때만 실제로 비활성화
        {
            VC->SetForceDisableSplitscreen(true);
        }
    }
}

void OnGameFeatureDeactivating(...)
{
    // 투표 감소 — 0이 되면 분할 화면 복원
    VoteCount--;
    if (VoteCount == 0)
        VC->SetForceDisableSplitscreen(false);
}
```

---

### 7. UGameFeatureAction_WorldActionBase (추상 기본 클래스)

위의 2~6번이 모두 상속하는 베이스. `AddToWorld()` 구현만 요구한다.
상세 내용은 위 "PIE 멀티 월드 지원" 섹션 참고.

---

## FPerContextData 패턴 — PIE 안전성

PIE에서 서버/클라이언트가 별도 World이므로, 같은 Action 인스턴스가 여러 컨텍스트에서 실행된다.
Lyra의 모든 Action은 `TMap<FGameFeatureStateChangeContext, FPerContextData>`로 컨텍스트별 상태를 분리한다.

```cpp
// AddAbilities를 예시로
struct FPerContextData
{
    TMap<AActor*, FActorExtensions>          ActiveExtensions;   // Actor별 부여 핸들
    TArray<TSharedPtr<FComponentRequestHandle>> ComponentRequests; // RAII 핸들 (소멸 시 자동 해제)
};
TMap<FGameFeatureStateChangeContext, FPerContextData> ContextData;

void OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    FPerContextData& ActiveData = ContextData.FindOrAdd(Context);  // 컨텍스트별 독립 데이터
    Super::OnGameFeatureActivating(Context);  // → AddToWorld() 호출
}

void OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context)
{
    Super::OnGameFeatureDeactivating(Context);
    FPerContextData* ActiveData = ContextData.Find(Context);
    Reset(*ActiveData);  // 이 컨텍스트(World)에서만 제거
    ContextData.Remove(Context);
}
```

---

## StartExperienceLoad — BundleAssetList에 ActionSet을 따로 추가하는 이유

```cpp
BundleAssetList.Add(CurrentExperience->GetPrimaryAssetId());
for (const TObjectPtr<ULyraExperienceActionSet>& ActionSet : CurrentExperience->ActionSets)
{
    BundleAssetList.Add(ActionSet->GetPrimaryAssetId());
}
AssetManager.ChangeBundleStateForPrimaryAssets(BundleAssetList, BundlesToLoad, ...);
```

`ActionSets`는 `TObjectPtr` — 하드 레퍼런스다. `CurrentExperience`가 로드되면 ActionSet 오브젝트 자체도 이미 메모리에 있다.  
그럼에도 따로 추가하는 이유는 `ChangeBundleStateForPrimaryAssets`가 **번들 로드**를 하기 때문이다.

**번들(Bundle)** = Primary Asset 내부에서 태그로 묶인 **소프트 레퍼런스 그룹**

```
ULyraExperienceActionSet (오브젝트 자체) → 이미 로드됨 (하드 레퍼런스)
  └─ [Client 번들] TSoftClassPtr<UGameplayAbility>  ← 아직 안 로드됨
  └─ [Client 번들] TSoftObjectPtr<UInputAction>     ← 아직 안 로드됨
  └─ [Server 번들] TSoftObjectPtr<UDataTable>       ← 아직 안 로드됨
```

ActionSet을 `BundleAssetList`에 추가하는 것은:  
"이 ActionSet 안에 선언된 Client/Server 번들의 소프트 레퍼런스 에셋들도 지금 로드해라"는 의미다.

**오브젝트 로드 ≠ 번들 로드.** 오브젝트는 이미 있어도, 그 안의 소프트 레퍼런스들은 번들 요청이 있어야 따라서 로드된다.

---

## 전체 흐름 다이어그램

```
[Experience 선택]
    ↓
LyraExperienceManagerComponent::SetCurrentExperience()
    ↓
StartExperienceLoad()          — 에셋 비동기 로드
    ↓
OnExperienceLoadComplete()     — GameFeature 플러그인 활성화 시작
    ↓
  UGameFeaturesSubsystem::LoadAndActivateGameFeaturePlugin("ShooterCore")
    ↓
  플러그인 상태: Installed → Registered → Loaded → Active
    ↓
  UGameFeatureAction::OnGameFeatureActivating()  ← 각 Action 실행
    ├─ AddAbilities → AddExtensionHandler(ALyraPlayerState) → AbilitySet 부여 대기
    ├─ AddInputBinding → AddExtensionHandler(APawn) → InputConfig 등록 대기
    ├─ AddWidgets → AddExtensionHandler(ALyraHUD) → 위젯 추가 대기
    └─ SplitscreenConfig → 즉시 SetForceDisableSplitscreen(true)
    ↓
OnExperienceFullLoadCompleted() — Experience->Actions 직접 실행
    ↓
OnExperienceLoaded Broadcast   — 플레이어 스폰 시작

[맵 언로드 / 게임 종료]
    ↓
LyraExperienceManagerComponent::EndPlay()
    ↓
  UGameFeaturesSubsystem::DeactivateGameFeaturePlugin()
    ↓
  UGameFeatureAction::OnGameFeatureDeactivating()
    ├─ AddAbilities → RemoveActorAbilities → SetRemoveAbilityOnEnd
    ├─ AddInputBinding → HeroComponent->RemoveAdditionalInputConfig
    ├─ AddWidgets → DeactivateWidget / Handle.Unregister
    └─ SplitscreenConfig → 투표 감소, 필요 시 SetForceDisableSplitscreen(false)
```

---

## 요약

| Action | 대상 | 주요 API | 특이사항 |
|--------|------|----------|----------|
| AddAbilities | ALyraPlayerState | `ASC->GiveAbility`, `GiveToAbilitySystem` | 서버에서만 실행, GA는 종료 후 제거 |
| AddInputBinding | APawn | `HeroComponent->AddAdditionalInputConfig` | LyraHeroComponent 필요 |
| AddInputContextMapping | LocalPlayer | `EnhancedInputSubsystem->AddMappingContext` | Registering 단계부터 동작 |
| AddWidgets | ALyraHUD | `PushContentToLayer_ForPlayer`, `RegisterExtensionAsWidgetForContext` | 클라이언트 전용 |
| AddGameplayCuePath | GCM | `AddGameplayCueNotifyPath` | LyraGameFeaturePolicy가 처리 |
| SplitscreenConfig | GameViewportClient | `SetForceDisableSplitscreen` | 전역 투표 카운트 방식 |
| WorldActionBase | (추상) | `AddToWorld()` | 모든 Action의 PIE 안전 베이스 |
