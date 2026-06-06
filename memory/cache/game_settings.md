# GameSettings 플러그인 캐시

출처:
- `Plugins/GameSettings/Source/Private/GameSetting.cpp`
- `Plugins/GameSettings/Source/Public/GameSetting.h`
- `Plugins/GameSettings/Source/Public/GameSettingFilterState.h`
- `Plugins/GameSettings/Source/Public/EditCondition/WhenCondition.h`
- `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSourceDynamic.h`
- `Source/LyraGame/Settings/LyraGameSettingRegistry.h`
- `Source/LyraGame/Settings/LyraGameSettingRegistry_Video.cpp`
- `Plugins/GameSettings/Source/Public/GameSettingRegistryChangeTracker.h`
- `Plugins/GameSettings/Source/Private/Registry/GameSettingRegistryChangeTracker.cpp`
- `Plugins/GameSettings/Source/Public/Widgets/GameSettingScreen.h`
- `Plugins/GameSettings/Source/Private/Widgets/GameSettingScreen.cpp`
- `Source/LyraGame/UI/LyraSettingScreen.h/.cpp`

---

## EditCondition 평가 시점

### 핵심 구조

```
EditableStateCache  ← 평가 결과 캐시 (UI가 이걸 읽음)
ComputeEditableState()  ← 모든 EditCondition.GatherEditState() 순서대로 호출 → 캐시 갱신
RefreshEditableState()  ← ComputeEditableState()를 재실행하는 진입점
```

UI 위젯은 `GatherEditState()`를 직접 호출하지 않고 `EditableStateCache`를 읽는다.

### 평가 트리거 3가지

**① 초기화 완료 시** (`GameSetting.cpp:102`)
```cpp
void UGameSetting::OnInitialized()
{
    EditableStateCache = ComputeEditableState();  // 최초 1회
}
```

**② 조건 자체가 외부 상태 변화로 바뀔 때** (`GameSetting.cpp:204`)
```cpp
// AddEditCondition 내부에서 자동 연결됨
InEditCondition->OnEditConditionChangedEvent
    .AddUObject(this, &ThisClass::RefreshEditableState);
```
FWhenCondition 람다 안에서 `BroadcastEditConditionChanged()` 호출 → `RefreshEditableState()` → 재평가

**③ 의존 설정이 바뀔 때** (`GameSetting.cpp:207–271`)
```cpp
void UGameSetting::AddEditDependency(UGameSetting* DependencySetting)
{
    // 의존 설정의 값 변경 or EditCondition 변경 이벤트에 연결
    DependencySetting->OnSettingChangedEvent
        .AddUObject(this, &ThisClass::HandleEditDependencyChanged);
    DependencySetting->OnSettingEditConditionChangedEvent
        .AddUObject(this, &ThisClass::HandleEditDependencyChanged);
}
// HandleEditDependencyChanged → RefreshEditableState() → ComputeEditableState()
```

### 시점 요약

| 시점 | 트리거 |
|------|--------|
| 초기화 | Registry가 설정 빌드 완료 후 `OnInitialized()` 호출 |
| 조건 내부 변화 | `BroadcastEditConditionChanged()` 호출 → `OnEditConditionChangedEvent` 발동 |
| 의존 설정 변경 | `AddEditDependency`로 연결된 설정 값/상태 변경 시 |

---

## Initialize 시 LocalPlayer를 넘기는 이유

**설정값 접근 경로가 LocalPlayer를 시작점으로 하는 함수 체인이기 때문이다.**

### DataSource 시스템

```cpp
// LyraGameSettingRegistry.h 매크로
#define GET_LOCAL_SETTINGS_FUNCTION_PATH(FunctionOrPropertyName)
    MakeShared<FGameSettingDataSourceDynamic>(TArray<FString>({
        GET_FUNCTION_NAME_STRING_CHECKED(ULyraLocalPlayer, GetLocalSettings),
        GET_FUNCTION_NAME_STRING_CHECKED(ULyraSettingsLocal, FunctionOrPropertyName)
    }))

#define GET_SHARED_SETTINGS_FUNCTION_PATH(FunctionOrPropertyName)
    // LocalPlayer->GetSharedSettings()->... 체인
```

런타임 호출 흐름:
```
FGameSettingDataSourceDynamic::GetValueAsString(ULocalPlayer* InLocalPlayer)
  → LocalPlayer->GetLocalSettings()->GetFullscreenMode()   (리플렉션 체인)
```

`UGameSetting`이 `TObjectPtr<ULocalPlayer> LocalPlayer`를 멤버로 보유하고,
DataSource가 이 LocalPlayer를 시작점으로 실제 설정값을 읽고 쓴다.
LocalPlayer 없이는 "누구의 설정인지" 알 수 없다.

### 분할화면 지원

```cpp
// Registry를 LocalPlayer를 Outer로 생성 → 플레이어마다 독립 인스턴스
Registry = NewObject<ULyraGameSettingRegistry>(InLocalPlayer, TEXT("LyraGameSettingRegistry"));
Registry->Initialize(InLocalPlayer);
```

P1과 P2는 각자의 Registry를 갖고, 각 Setting은 자신의 LocalPlayer를 통해 자신의 설정에만 접근한다.

### EditCondition에도 전달

```cpp
// SettingChanged 내부에서 LocalPlayer 캐스팅 후 설정 접근
const ULyraLocalPlayer* LyraLocalPlayer = CastChecked<ULyraLocalPlayer>(LocalPlayer);
LyraLocalPlayer->GetLocalSettings()->ApplyScalabilitySettings();
```

---

## ListEntry Model-View 바인딩

출처: `Plugins/GameSettings/Source/Private/Widgets/GameSettingListEntry.cpp`

### SetSetting() — 연결 진입점

ListView가 항목을 렌더링할 때 호출. 이벤트 2개를 구독하고 초기 상태를 반영한다.

```cpp
Setting->OnSettingChangedEvent.AddUObject(this, &ThisClass::HandleSettingChanged);
Setting->OnSettingEditConditionChangedEvent.AddUObject(this, &ThisClass::HandleEditConditionChanged);
HandleEditConditionChanged(Setting);  // 즉시 초기 상태 반영
```

### UI → Model

- Discrete: 버튼 클릭 → `SetDiscreteOptionByIndex()` → `NotifySettingChanged` → `OnSettingChangedEvent`
- Scalar: 슬라이더 드래그 → `SetValueNormalized()` + `bSuspendChangeUpdates=true`로 역방향 루프 차단

### Model → UI

`OnSettingChangedEvent` → `HandleSettingChanged` → `OnSettingChanged` → `Refresh()`
- Discrete: Rotator 선택 인덱스 갱신
- Scalar: 슬라이더 값 + 텍스트 갱신

### EditCondition → 위젯 상태

`OnSettingEditConditionChangedEvent` → `HandleEditConditionChanged` → `RefreshEditableState()`
→ 버튼/슬라이더 `SetIsEnabled()` 제어
Discrete는 `Refresh()`도 추가 호출 (선택지 목록 자체가 바뀔 수 있어서)

### 풀링 반환 (NativeOnEntryReleased)

이벤트 모두 RemoveAll 후 Setting 포인터를 nullptr로 클리어. 미해제 시 재사용된 위젯이 이전 Setting 이벤트에 반응하는 버그 발생.

---

## EditCondition 관련 클래스

### `FGameSettingEditCondition` (base)

```cpp
virtual void Initialize(const ULocalPlayer* InLocalPlayer) { }
virtual void SettingApplied(const ULocalPlayer* LP, UGameSetting* Setting) const { }
virtual void SettingChanged(const ULocalPlayer* LP, UGameSetting* Setting, ...) const { }
virtual void GatherEditState(const ULocalPlayer* LP, FGameSettingEditableState& InOutEditState) const { }
FOnEditConditionChanged OnEditConditionChangedEvent;
```

여러 조건이 있으면 모두 순서대로 `GatherEditState()` 호출. 한 조건이 `Hide()`해도 이후 조건도 계속 실행된다.

### `FGameSettingEditableState` — 평가 결과

```cpp
bool IsVisible() const;    // false → 목록에서 안 보임
bool IsEnabled() const;    // false → 회색, 비활성
bool IsResetable() const;  // false → 기본값 버튼에서 제외

void Hide(const FString& DevReason);
void Disable(const FText& Reason);     // 유저에게 이유 표시
void Kill(const FString& DevReason);   // Hide + HideFromAnalytics + UnableToReset
void DisableOption(const FString& Option);  // Discrete 선택지 중 특정 항목만 비활성
```

### 구체 조건 타입

- `FWhenCondition` — 인라인 람다, 가장 유연
- `FWhenPlatformHasTrait` — CommonUI 플랫폼 태그 기반 (KillIfMissing/DisableIfMissing/KillIfPresent/DisableIfPresent)
- `FWhenPlayingAsPrimaryPlayer` — 분할화면 2P 이상이면 비활성

---

## `FGameSettingFilterState` — 목록 필터

Registry/Panel이 표시 항목을 결정할 때 사용.

```cpp
FGameSettingFilterState Filter;
Filter.bIncludeDisabled = true;
Filter.bIncludeHidden = false;
Filter.SetSearchText(TEXT("감도"));  // DevName/DisplayName/DescriptionRichText에서 검색
Panel->SetFilterState(Filter);
```

---

## `EGameSettingChangeReason`

```cpp
enum class EGameSettingChangeReason : uint8
{
    Change,            // 사용자 직접 변경
    DependencyChanged, // 의존 설정 변경으로 인한 재평가
    ResetToDefault,    // "기본값으로" 버튼
    RestoreToInitial,  // 취소 (StoreInitial 시점으로)
};
```

---

## `ULyraSettingKeyboardInput::GetAllMappedActionsFromKey` — OutActionNames의 정체

**출처**: `Source/LyraGame/Settings/CustomSettings/LyraSettingKeyboardInput.cpp:224`, `Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.cpp:77`

```cpp
void ULyraSettingKeyboardInput::GetAllMappedActionsFromKey(int32 InKeyBindSlot, FKey Key, TArray<FName>& OutActionNames) const
{
    if (const UEnhancedPlayerMappableKeyProfile* Profile = FindMappableKeyProfile())
    {
        Profile->GetMappingNamesForKey(Key, OutActionNames);  // ← 핵심
    }
}
```

### OutActionNames에 들어오는 값

`UInputAction` 오브젝트가 아니라 **`UPlayerMappableKeySettings::Name`** — `UInputAction` 에셋에 붙은 서브오브젝트에서 에디터로 지정하는 `FName`.

**출처**: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/PlayerMappableKeySettings.h:47`

```cpp
// UPlayerMappableKeySettings
UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Settings")
FName Name;  // ← "IA_Move_Forward" 같은 값. 에디터에서 수동 지정.
```

`FEnhancedActionKeyMapping::SettingBehavior`로 출처 제어:
- `InheritSettingsFromAction` (기본) — InputAction 에셋의 Name 사용
- `OverrideSettings` — IMC 내 매핑마다 따로 지정
- `IgnoreSettings` — 맵핑 불가 처리

### 하나의 InputAction이 여러 키에 바인딩될 때 MappingName은?

**같은 MappingName을 공유한다 — 의도된 설계.**

`PlayerMappedKeys: TMap<FName, FKeyMappingRow>` 구조:

```
MappingName "IA_Move_Forward"
    └─ FKeyMappingRow { TSet<FPlayerKeyMapping> }
         ├─ FPlayerKeyMapping { Slot=First,  CurrentKey=W }
         └─ FPlayerKeyMapping { Slot=Second, CurrentKey=Up Arrow }
```

**출처**: `EnhancedInputUserSettings.h:28` (주석: `| <Mapping Name> | Slot 1 | Slot 2 | ... |`)

키 여러 개는 **Slot으로 구분**. `GetMappingNamesForKey`는 MappingName 단위로 중복 없이 반환하므로 "W → IA_Move_Forward" 하나만 나온다.

### 왜 UInputAction* 가 아닌 FName인가

이 함수의 목적이 **키 충돌 경고 UI 텍스트 출력** 하나뿐이기 때문:

```cpp
// LyraSettingsListEntrySetting_KeyboardInput.cpp:87
for (FName ActionName : ActionsForKey)
    ActionNames += ActionName.ToString() += ", ";
// → "W is already bound to IA_Move_Forward, are you sure..."
```

- 문자열 출력이 전부 → `UInputAction*`의 ValueType/Modifier/Trigger 불필요
- Enhanced Input User Settings 저장/로드가 `FName`을 키로 사용 → 에셋 포인터 없이도 동작
- `FName`은 해시 기반 비교로 빠름

---

## FGameSettingRegistryChangeTracker — dirty 추적

**출처**: `GameSettingRegistryChangeTracker.h/.cpp`, `GameSettingScreen.h/.cpp`, `LyraSettingScreen.h/.cpp`

### 핵심 구조

```
UGameSettingScreen
  └─ FGameSettingRegistryChangeTracker (값 멤버)
       ├─ bSettingsChanged                  ← "하나라도 바뀌었나" 플래그
       └─ DirtySettings: TMap<FObjectKey, TWeakObjectPtr<UGameSetting>>
```

### 이벤트 연결

```cpp
// WatchRegistry — 화면 활성화 시(NativeOnActivated) 호출
InRegistry->OnSettingChangedEvent.AddRaw(this, &ChangeTracker::HandleSettingChanged);
// HandleSettingChanged: bSettingsChanged = true, DirtySettings에 추가
```

### Apply 흐름 (`GameSettingScreen.cpp:58`)

```
UGameSettingScreen::ApplyChanges()
  → ChangeTracker.ApplyChanges()
       → 각 dirty: SettingValue->Apply() + StoreInitial()
  → ClearDirtyState() → OnSettingsDirtyStateChanged(false)
  → Registry->SaveChanges()  // 디스크 저장
```

### Cancel 흐름 (RestoreToInitial)

```cpp
TGuardValue<bool> LocalGuard(bRestoringSettings, true);  // 재진입 차단
for (DirtySettings) → SettingValue->RestoreToInitial();  // InitialValue로 복원
ClearDirtyState();
```

`bRestoringSettings` 가드: Restore 중 OnSettingChangedEvent 재발동 → DirtySettings 재추가 무한루프 방지.

### StoreInitial / RestoreToInitial (DiscreteDynamic 구현, `GameSettingValueDiscreteDynamic.cpp:111`)

```cpp
void StoreInitial()    { InitialValue = GetValueAsString(); }
void RestoreToInitial(){ SetValueFromString(InitialValue, EGameSettingChangeReason::RestoreToInitial); }
```

StoreInitial 호출 시점 2가지:
1. `OnInitialized()` — 화면 최초 초기화 시
2. `ChangeTracker::ApplyChanges()` — Apply 완료 후 (다음 Cancel 기준을 현재 값으로 갱신)

### Lyra의 OnSettingsDirtyStateChanged (`LyraSettingScreen.cpp:56`)

dirty=true → Apply·Cancel 버튼 AddActionBinding  
dirty=false → RemoveActionBinding

### Lyra 뒤로가기 — 팝업 없이 즉시 Apply (`LyraSettingScreen.cpp:34`)

```cpp
void HandleBackAction()
{
    if (AttemptToPopNavigation()) return;
    ApplyChanges();       // 확인 팝업 없이 바로 적용
    DeactivateWidget();
}
```

팝업 원하면 `HandleBackAction()` 오버라이드 후 `HaveSettingsBeenChanged()`로 체크 → CommonUI 다이얼로그 호출.

---

## `ChangeBinding` 충돌 처리 흐름 및 기존 바인딩 제거

**출처**: `Source/LyraGame/Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.cpp:77`, `Source/LyraGame/Settings/CustomSettings/LyraSettingKeyboardInput.cpp:199`

### 위젯 레이어 흐름 (Widget `ChangeBinding`, line 77)

```
Widget::ChangeBinding(slot, key)
  ├─ GetAllMappedActionsFromKey → 해당 키에 이미 바인딩된 ActionName 목록 조회
  ├─ [충돌 있음] → KeyAlreadyBoundWarning 다이얼로그 표시
  │     └─ 유저 확인 → HandlePrimaryDuplicateKeySelected
  │           └─ KeyboardInputSetting->ChangeBinding(0, OriginalKeyToBind)
  └─ [충돌 없음] → KeyboardInputSetting->ChangeBinding(InKeyBindSlot, InKey)
```

### Model `ChangeBinding` (LyraSettingKeyboardInput.cpp:199)

```cpp
FMapPlayerKeyArgs Args;
Args.MappingName = ActionMappingName;
Args.Slot = (EPlayerMappableKeySlot)(static_cast<uint8>(InKeyBindSlot));
Args.NewKey = NewKey;
Settings->MapPlayerKey(Args, FailureReason);  // EnhancedInputUserSettings API
```

### 핵심 주의: 기존 바인딩을 자동으로 제거하지 않는다

`MapPlayerKey`는 충돌 해제 기능이 없다. 경고 확인 후에도 기존 액션의 키를 그대로 둔 채 새 액션에 동일 키를 추가로 매핑한다 → 두 액션이 같은 키를 공유하는 상태가 됨.

### 기존 키를 제거하고 새로 바인딩하는 방법

Profile의 모든 매핑 행을 직접 순회하며 충돌 키를 `EKeys::Invalid`로 먼저 교체해야 한다.

```cpp
// 기존 키 제거 헬퍼 (ULyraSettingKeyboardInput에 추가)
void ClearKeyFromAllMappings(FKey KeyToRemove)
{
    UEnhancedInputUserSettings* Settings = GetUserSettings();
    UEnhancedPlayerMappableKeyProfile* Profile = FindMappableKeyProfile();

    for (auto& [MappingName, Row] : Profile->GetPlayerMappedKeys())
    {
        for (const FPlayerKeyMapping& Mapping : Row.Mappings)
        {
            if (Mapping.GetCurrentKey() == KeyToRemove)
            {
                FMapPlayerKeyArgs Args;
                Args.MappingName = MappingName;
                Args.Slot = Mapping.GetSlot();
                Args.NewKey = EKeys::Invalid;  // 기존 바인딩 제거
                FGameplayTagContainer Fail;
                Settings->MapPlayerKey(Args, Fail);
            }
        }
    }
}

// HandlePrimaryDuplicateKeySelected 수정 버전
KeyboardInputSetting->ClearKeyFromAllMappings(OriginalKeyToBind);  // 1. 기존 제거
KeyboardInputSetting->ChangeBinding(0, OriginalKeyToBind);          // 2. 새로 매핑
```

| 단계 | 현재 Lyra | 기존 키 제거 원할 때 |
|------|----------|-------------------|
| 충돌 감지 | `GetAllMappedActionsFromKey` | 동일 |
| 경고 확인 후 | 충돌 그대로 두고 새 매핑만 추가 | 충돌 키를 `EKeys::Invalid`로 먼저 교체 |
| 새 매핑 | `MapPlayerKey(NewKey)` | 동일 |
