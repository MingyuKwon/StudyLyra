# 언리얼 코어 시스템

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

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
