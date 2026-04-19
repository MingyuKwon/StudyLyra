# Lyra Experience 시스템 — 전체 흐름

출처:
- `Source/LyraGame/GameModes/LyraExperienceDefinition.h`
- `Source/LyraGame/GameModes/LyraExperienceManagerComponent.h/.cpp`
- `Source/LyraGame/GameModes/LyraGameMode.cpp`
- `Source/LyraGame/GameModes/LyraExperienceActionSet.h`
- `Source/LyraGame/GameModes/LyraExperienceManager.h`

---

## Experience vs GameFeature — 왜 둘이 따로 있는가

```
Experience (Lyra 개념)
  └─ "이 게임 모드에 어떤 GameFeature 플러그인이 필요하고, 어떤 Action을 실행할지" 선언하는 DataAsset

GameFeature Plugin (엔진 개념)
  └─ 런타임에 켜고 끌 수 있는 플러그인 컨테이너. Lyra와 무관
```

**비유:** Experience = 레시피, GameFeature = 재료

같은 ShooterCore 플러그인을 팀데스매치 Experience도 쓰고 컨트롤 Experience도 쓴다.
Experience : GameFeature = N : M 관계라 분리되어 있다.

```
B_ShooterGame_Elimination (Experience)
  GameFeaturesToEnable: ["ShooterCore", "ShooterMaps"]  ← 필요한 재료
  DefaultPawnData: B_Hero_ShooterMannequin
  Actions: [AddHUD, AddInputBinding, ...]               ← 이 Experience만의 추가 조리법

B_ShooterGame_Control (Experience)
  GameFeaturesToEnable: ["ShooterCore", "ShooterMaps"]  ← 동일한 재료 재활용
  DefaultPawnData: B_Hero_ShooterMannequin
  Actions: [AddHUD, AddControlPointScoring, ...]        ← 점령 전용 추가 액션
```

---

## 핵심 데이터 클래스

### ULyraExperienceDefinition (PrimaryDataAsset)

```cpp
// LyraExperienceDefinition.h
UCLASS(BlueprintType, Const)
class ULyraExperienceDefinition : public UPrimaryDataAsset
{
public:
    // 활성화할 GameFeature 플러그인 이름 목록
    UPROPERTY(EditDefaultsOnly, Category = Gameplay)
    TArray<FString> GameFeaturesToEnable;

    // 이 Experience의 기본 폰
    UPROPERTY(EditDefaultsOnly, Category = Gameplay)
    TObjectPtr<const ULyraPawnData> DefaultPawnData;

    // Experience가 직접 실행할 GameFeatureAction 목록
    UPROPERTY(EditDefaultsOnly, Instanced, Category = "Actions")
    TArray<TObjectPtr<UGameFeatureAction>> Actions;

    // 여러 Experience가 공유할 수 있는 Action 묶음
    UPROPERTY(EditDefaultsOnly, Category = Gameplay)
    TArray<TObjectPtr<ULyraExperienceActionSet>> ActionSets;
};
```

### ULyraExperienceActionSet (PrimaryDataAsset)

Experience 간에 공유 가능한 Action + Plugin 묶음. 중복 선언 없이 재사용한다.

```cpp
class ULyraExperienceActionSet : public UPrimaryDataAsset
{
public:
    TArray<TObjectPtr<UGameFeatureAction>> Actions;
    TArray<FString> GameFeaturesToEnable;  // ActionSet도 자체 플러그인 의존성을 가질 수 있음
};
```

---

## 전체 흐름

```
[서버] 맵 로드 완료
    │
    ▼
ALyraGameMode::InitGame()
    └─ 다음 틱에 HandleMatchAssignmentIfNotExpectingOne() 예약

ALyraGameMode::HandleMatchAssignmentIfNotExpectingOne()
    └─ ExperienceId 결정 (우선순위 순)
         1. URL Option  (?Experience=B_ShooterGame_Elimination)
         2. PIE Developer Settings (에디터 전용 오버라이드)
         3. 커맨드라인 (-Experience=...)
         4. ALyraWorldSettings::DefaultGameplayExperience
         5. B_LyraDefaultExperience (하드코딩 최종 폴백)
    └─ OnMatchAssignmentGiven(ExperienceId)
         └─ ExperienceComponent->SetCurrentExperience(ExperienceId)

ULyraExperienceManagerComponent::SetCurrentExperience()
    └─ AssetManager로 ExperienceId → ULyraExperienceDefinition CDO 로드
    └─ CurrentExperience = Experience          ← UPROPERTY(ReplicatedUsing=OnRep_CurrentExperience)
    └─ StartExperienceLoad()                   ← 클라이언트는 OnRep_CurrentExperience()로 진입

ULyraExperienceManagerComponent::StartExperienceLoad()
    └─ LoadState = Loading
    └─ AssetManager.ChangeBundleStateForPrimaryAssets()
         - Experience + ActionSet 에셋 비동기 로드
         - Client/Server 번들 분리 로드 (NM_DedicatedServer면 클라 번들 스킵)
    └─ 완료 콜백 → OnExperienceLoadComplete()

ULyraExperienceManagerComponent::OnExperienceLoadComplete()
    └─ LoadState = LoadingGameFeatures
    └─ Experience + ActionSet의 GameFeaturesToEnable 수집 → 중복 제거
    └─ 각 플러그인에 대해:
         ULyraExperienceManager::NotifyOfPluginActivation(URL)  ← PIE 참조 카운트 관리
         UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(URL, Callback)
              → 플러그인 상태: Installed → Registered → Loaded → Active
              → Active 시 UGameFeatureAction::OnGameFeatureActivating() 실행
    └─ 모든 플러그인 완료 → OnExperienceFullLoadCompleted()

ULyraExperienceManagerComponent::OnExperienceFullLoadCompleted()
    └─ LoadState = ExecutingActions
    └─ Experience->Actions 직접 실행:
         Action->OnGameFeatureRegistering()
         Action->OnGameFeatureLoading()
         Action->OnGameFeatureActivating(Context)  ← WorldContext 지정으로 PIE 안전
    └─ ActionSet->Actions도 동일하게 실행
    └─ LoadState = Loaded
    └─ OnExperienceLoaded_HighPriority.Broadcast()
       OnExperienceLoaded.Broadcast()
       OnExperienceLoaded_LowPriority.Broadcast()

[이후] ALyraGameMode::OnExperienceLoaded()
    └─ 이미 접속 중인 PlayerController에 RestartPlayer() 호출
       (Experience 로드 전에 접속한 플레이어를 이제서야 스폰)
```

---

## 스테이트 머신

```cpp
enum class ELyraExperienceLoadState
{
    Unloaded,
    Loading,                // 에셋 비동기 로드 중
    LoadingGameFeatures,    // UGameFeaturesSubsystem::LoadAndActivateGameFeaturePlugin() 중
    LoadingChaosTestingDelay, // CVar 테스트 지연 (lyra.chaos.ExperienceDelayLoad.*)
    ExecutingActions,       // Experience->Actions 직접 실행 중
    Loaded,                 // 완전히 준비됨 — 여기서 델리게이트 브로드캐스트
    Deactivating            // EndPlay 시 액션 비활성화 중
};
```

---

## Experience와 GameFeature Action의 관계

GameFeature 플러그인 자체의 `.uplugin`에도 Actions가 있고,
Experience의 `Actions` 배열에도 Actions가 있다. **둘 다 실행된다.**

```
GameFeature 플러그인 활성화 (LoadAndActivateGameFeaturePlugin)
  └─ 플러그인의 UGameFeatureData 에셋에 정의된 Actions 실행  ← 엔진이 자동 실행

OnExperienceFullLoadCompleted()
  └─ Experience->Actions 실행                                ← Lyra가 직접 실행
  └─ ActionSet->Actions 실행
```

**차이:**
| | GameFeature Plugin Actions | Experience Actions |
|--|--------------------------|-------------------|
| 정의 위치 | `.uplugin` → `UGameFeatureData` | `ULyraExperienceDefinition.Actions` |
| 실행 주체 | `UGameFeaturesSubsystem` (엔진) | `ULyraExperienceManagerComponent` (Lyra) |
| 범위 | 해당 플러그인이 Active인 동안 항상 | 해당 Experience가 로드된 동안만 |
| 용도 | 플러그인 전역 설정 | Experience별 커스터마이징 |

---

## 복제 구조

```cpp
// ExperienceManagerComponent.h
UPROPERTY(ReplicatedUsing=OnRep_CurrentExperience)
TObjectPtr<const ULyraExperienceDefinition> CurrentExperience;

void OnRep_CurrentExperience()
{
    StartExperienceLoad();  // 클라이언트도 동일한 로드 파이프라인 진입
}
```

- **서버**: `SetCurrentExperience()` → `StartExperienceLoad()`
- **클라이언트**: `CurrentExperience`가 복제되면 `OnRep_CurrentExperience()` → `StartExperienceLoad()`
- 에셋 로드와 GameFeature 활성화는 서버/클라이언트가 **각자 독립적으로** 수행한다.

---

## 로딩 화면 연동

```cpp
// ILoadingProcessInterface 구현
bool ULyraExperienceManagerComponent::ShouldShowLoadingScreen(FString& OutReason) const
{
    if (LoadState != ELyraExperienceLoadState::Loaded)
    {
        OutReason = TEXT("Experience still loading");
        return true;  // Loaded 상태가 될 때까지 로딩 화면 유지
    }
    return false;
}
```

---

## PIE 멀티 월드 — ULyraExperienceManager

PIE에서 서버/클라이언트가 별도 World로 존재하면, 같은 플러그인을 여러 번 활성화 요청한다.
`ULyraExperienceManager`(EngineSubsystem)가 참조 카운트로 중복 비활성화를 방지한다.

```cpp
// 에디터 빌드에서만 동작 (#if WITH_EDITOR)
class ULyraExperienceManager : public UEngineSubsystem
{
    // 플러그인 URL → 활성화 요청 횟수
    TMap<FString, int32> GameFeaturePluginRequestCountMap;

public:
    // 활성화 시 카운트 증가
    static void NotifyOfPluginActivation(const FString PluginURL);

    // 비활성화 시 카운트 감소 — 0이 되어야 실제로 DeactivateGameFeaturePlugin() 호출
    static bool RequestToDeactivatePlugin(const FString PluginURL);
};
```

릴리스 빌드에서는 두 함수 모두 no-op / 항상 true 반환.

---

## 플레이어 스폰과 Experience의 관계

GameMode는 Experience 로드 전에 접속한 플레이어를 바로 스폰하지 않는다.

```cpp
// LyraGameMode.cpp
void ALyraGameMode::HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)
{
    // Experience 로드 완료 전에는 스폰 보류
    if (IsExperienceLoaded())
    {
        Super::HandleStartingNewPlayer_Implementation(NewPlayer);
    }
    // 로드 완료 후 OnExperienceLoaded()에서 RestartPlayer() 일괄 호출
}
```

PawnData도 Experience에서 온다:
```cpp
UClass* ALyraGameMode::GetDefaultPawnClassForController_Implementation(AController* InController)
{
    if (const ULyraPawnData* PawnData = GetPawnDataForController(InController))
        return PawnData->PawnClass;  // Experience->DefaultPawnData에서 가져옴
    return Super::...;
}
```

---

## OnExperienceLoaded 우선순위 델리게이트

시스템마다 Experience 준비 이후 초기화 순서가 다를 수 있어 3단계로 분리됐다.

```cpp
// 등록 방법 — 이미 로드됐으면 즉시 호출, 아니면 완료 시 호출
ExperienceComponent->CallOrRegister_OnExperienceLoaded_HighPriority(Delegate); // 서브시스템 초기화
ExperienceComponent->CallOrRegister_OnExperienceLoaded(Delegate);              // 일반 시스템
ExperienceComponent->CallOrRegister_OnExperienceLoaded_LowPriority(Delegate);  // 후처리

// 내부 브로드캐스트 순서 (OnExperienceFullLoadCompleted)
OnExperienceLoaded_HighPriority.Broadcast(CurrentExperience);
OnExperienceLoaded.Broadcast(CurrentExperience);
OnExperienceLoaded_LowPriority.Broadcast(CurrentExperience);
```

---

## Experience 해제 (EndPlay)

```cpp
void ULyraExperienceManagerComponent::EndPlay(...)
{
    // GameFeature 플러그인 비활성화
    for (const FString& PluginURL : GameFeaturePluginURLs)
    {
        if (ULyraExperienceManager::RequestToDeactivatePlugin(PluginURL))  // PIE 카운트 확인
            UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(PluginURL);
    }

    // Experience->Actions 비활성화
    // Action->OnGameFeatureDeactivating(Context)
    // Action->OnGameFeatureUnregistering()
}
```

> **주석 (Epic TODO)**: 현재 플러그인 비활성화가 완전하지 않다. Experience 전환 시 diff해서 필요한 것만 내리는 최적화가 미구현이다.
