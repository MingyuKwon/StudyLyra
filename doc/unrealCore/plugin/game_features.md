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

## 요약

- **UGameFeaturesSubsystem**: 플러그인 상태 머신 관리 (Installed → Active)
- **UGameFeatureAction**: 활성화/비활성화 시 실행할 작업의 추상 인터페이스
- **ULyraExperienceDefinition**: 어떤 플러그인이 필요한지 DataAsset으로 선언
- **ULyraExperienceManagerComponent**: Experience 로드 → 플러그인 활성화 → Action 실행 조율
- GameFeatures는 **트리거**, ModularGameplay는 **메커니즘** — 함께 써야 완성
