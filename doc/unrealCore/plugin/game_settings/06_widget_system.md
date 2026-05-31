# 06. 위젯 시스템 — Screen / Panel / ListEntry

> 출처: `Plugins/GameSettings/Source/Public/Widgets/GameSettingScreen.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/GameSettingPanel.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/GameSettingListEntry.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/GameSettingDetailView.h`

---

## 위젯 계층 구조

```
UGameSettingScreen                   ← 설정 화면 전체 (CommonActivatableWidget)
    └─ UGameSettingPanel (BindWidget) ← 설정 목록 + 상세
            ├─ UGameSettingListView   ← ListView (항목 위젯 풀링)
            │       └─ UGameSettingListEntryBase × N  ← 항목 위젯
            └─ UGameSettingDetailView ← 선택된 항목 설명
```

---

## `UGameSettingScreen` — 화면 최상위

`UCommonActivatableWidget`을 상속한다. 즉, CommonUI의 위젯 스택(Widget Stack)에 쌓이고 뒤로가기가 지원된다.

```cpp
class UGameSettingScreen : public UCommonActivatableWidget
{
protected:
    virtual UGameSettingRegistry* CreateRegistry() PURE_VIRTUAL(, return nullptr;);

    virtual void ApplyChanges();   // "적용" 버튼 → Registry->SaveChanges() + ClearDirtyState
    virtual void CancelChanges();  // "취소" 버튼 → ChangeTracker->RestoreToInitial()
    bool AttemptToPopNavigation(); // Panel의 네비게이션 스택 팝 (하위 페이지에서 뒤로)

    // BP 이벤트: "저장이 필요한 변경이 생겼는가/없어졌는가"
    UFUNCTION(BlueprintNativeEvent)
    void OnSettingsDirtyStateChanged(bool bSettingsDirty);

    bool HaveSettingsBeenChanged() const;

    FGameSettingRegistryChangeTracker ChangeTracker;

private:
    TObjectPtr<UGameSettingPanel> Settings_Panel;  // BindWidget
};
```

`CreateRegistry()`는 서브클래스에서 구현한다:

```cpp
UGameSettingRegistry* ULyraGameSettingScreen::CreateRegistry()
{
    auto* Registry = NewObject<ULyraGameSettingRegistry>();
    Registry->Initialize(GetOwningLocalPlayer());
    return Registry;
}
```

Registry는 `GetOrCreateRegistry()`로 지연 생성된다. 화면이 처음 활성화될 때 만들어진다.

### Screen ↔ Registry는 1:1

`UGameSettingScreen` 하나가 Registry 하나를 소유한다. `ULyraGameSettingRegistry`는 비디오·오디오·입력 설정을 전부 포함하므로, 설정 화면 전체가 하나의 Screen + 하나의 Registry로 동작한다.

```
ULyraSettingScreen (화면 1개)
    └─ ULyraGameSettingRegistry (Registry 1개)
            ├─ Collection "VideoSection"   ← 비디오 탭
            ├─ Collection "AudioSection"   ← 오디오 탭
            └─ Collection "InputSection"   ← 입력 탭
```

설정 화면을 여러 개 만들어야 한다면 Screen 서브클래스를 따로 만들고 `CreateRegistry()`에서 다른 Registry를 반환하면 된다. Lyra는 단일 Screen으로 모든 설정을 처리한다.

---

## `UGameSettingPanel` — 목록 + 네비게이션 스택

화면 안에서 "현재 어떤 설정 목록을 보고 있는가"를 관리한다.

```cpp
class UGameSettingPanel : public UCommonUserWidget
{
    void SetRegistry(UGameSettingRegistry* InRegistry);

    // 현재 표시 필터 (탭 전환, 검색어 등)
    void SetFilterState(const FGameSettingFilterState& InFilterState, bool bClearNavigationStack = true);

    // CollectionPage 클릭 시 하위 목록으로 이동 (스택에 쌓임)
    // AttemptToPopNavigation으로 뒤로 이동
    bool CanPopNavigationStack() const;
    void PopNavigationStack();

    UGameSetting* GetSelectedSetting() const;
    void SelectSetting(const FName& SettingDevName);  // DevName으로 포커스 이동

    void RefreshSettingsList();  // EditCondition 변경 후 목록 갱신

private:
    UGameSettingListView* ListView_Settings;        // BindWidget
    UGameSettingDetailView* Details_Settings;       // BindWidgetOptional

    FGameSettingFilterState FilterState;
    TArray<FGameSettingFilterState> FilterNavigationStack;  // 뒤로가기 스택
};
```

### 네비게이션 스택

`UGameSettingCollectionPage`를 클릭하면:

```
HandleSettingNavigation(CollectionPageSetting)
    └─ FilterNavigationStack.Push(현재 FilterState)
    └─ 새 FilterState = CollectionPage의 하위 설정들만 허용
    └─ RefreshSettingsList()
```

뒤로가기:

```
PopNavigationStack()
    └─ FilterState = FilterNavigationStack.Pop()
    └─ RefreshSettingsList()
```

`SetFilterState(bClearNavigationStack = true)`를 호출하면 스택이 초기화된다.  
탭 전환 시 이렇게 호출한다.

---

## `UGameSettingListEntryBase` — 항목 위젯 base

`IUserObjectListEntry`를 구현한다 → `UListView`의 아이템으로 직접 사용 가능.

```cpp
class UGameSettingListEntryBase : public UCommonUserWidget, public IUserObjectListEntry
{
    virtual void SetSetting(UGameSetting* InSetting);

protected:
    virtual void OnSettingChanged();              // Model 값 변경 시 UI 갱신
    virtual void HandleEditConditionChanged(...); // 비활성/숨김 상태 변경
    virtual void RefreshEditableState(...);       // 새 EditableState 반영

    TObjectPtr<UGameSetting> Setting;
};
```

`SetSetting()`이 호출되면:
1. 이전 Setting의 이벤트 구독 해제
2. 새 Setting의 `OnSettingChangedEvent` 구독 → 값 바뀌면 `OnSettingChanged()` 호출
3. 새 Setting의 `OnSettingEditConditionChangedEvent` 구독 → 상태 바뀌면 `RefreshEditableState()` 호출
4. 초기 표시 상태로 위젯 갱신

`NativeOnEntryReleased()`(ListView 풀로 반환 시) 에서 이벤트를 모두 해제한다.

---

## `UGameSettingListEntry_Setting` — 이름 표시

```cpp
class UGameSettingListEntry_Setting : public UGameSettingListEntryBase
{
    TObjectPtr<UCommonTextBlock> Text_SettingName;  // BindWidget
};
```

`SetSetting()` 시 `Text_SettingName`에 `Setting->GetDisplayName()`을 표시한다.

### 파생 위젯들

| 클래스 | 추가 위젯 | 동작 |
|--------|-----------|------|
| `*_Discrete` | `UGameSettingRotator` + 좌/우 버튼 | 좌/우 클릭 → `SetDiscreteOptionByIndex()` |
| `*_Scalar` | `UAnalogSlider` + `UCommonTextBlock` | 슬라이더 변경 → `SetValueNormalized()` |
| `*_Action` | `UCommonButtonBase` | 클릭 → `UGameSettingAction::ExecuteAction()` |
| `*_Navigation` | `UCommonButtonBase` | 클릭 → `UGameSettingCollectionPage::ExecuteNavigation()` |

모두 Abstract 클래스다. Blueprint에서 실제 위젯 레이아웃을 구성하고 `BindWidget`으로 연결한다.

---

## Model-View 바인딩 흐름

```
[설정 화면 열기]
Screen->NativeOnActivated()
    └─ Registry->Initialize()
            └─ 모든 Setting 초기화 + StoreInitial()
    └─ Panel->SetRegistry(Registry)
            └─ ListView_Settings->SetListItems(VisibleSettings)
                    └─ 각 항목에 ListEntry 위젯 할당
                    └─ ListEntry->SetSetting(Setting)

[사용자가 값 변경]
ListEntry_Discrete: 좌/우 버튼 클릭
    └─ Setting->SetDiscreteOptionByIndex(NewIndex)
            └─ NotifySettingChanged(EGameSettingChangeReason::Change)
                    └─ Registry->OnSettingChangedEvent 브로드캐스트
                    └─ ChangeTracker가 감지 → bSettingsChanged = true
                    └─ ListEntry->OnSettingChanged() → UI 갱신

[의존 설정 변경으로 EditCondition 재평가]
OtherSetting 변경 → DependsOn이 있는 Setting들 → RefreshEditableState()
    └─ ComputeEditableState() → 모든 EditCondition->GatherEditState() 순차 실행
    └─ EditableStateCache 갱신
    └─ NotifyEditConditionsChanged()
            └─ ListEntry->HandleEditConditionChanged() → RefreshEditableState()
```
