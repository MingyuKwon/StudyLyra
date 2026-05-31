# GameSettings 플러그인 캐시

출처:
- `Plugins/GameSettings/Source/Private/GameSetting.cpp`
- `Plugins/GameSettings/Source/Public/GameSetting.h`
- `Plugins/GameSettings/Source/Public/GameSettingFilterState.h`
- `Plugins/GameSettings/Source/Public/EditCondition/WhenCondition.h`
- `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSourceDynamic.h`
- `Source/LyraGame/Settings/LyraGameSettingRegistry.h`
- `Source/LyraGame/Settings/LyraGameSettingRegistry_Video.cpp`

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
