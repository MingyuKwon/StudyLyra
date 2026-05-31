# 09. Model-View 바인딩 — Setting 데이터와 위젯 연결

> 소스:
> `Plugins/GameSettings/Source/Private/Widgets/GameSettingListEntry.cpp`
> `Plugins/GameSettings/Source/Private/Widgets/GameSettingPanel.cpp`
> `Plugins/GameSettings/Source/Public/Widgets/GameSettingListEntry.h`

Registry의 데이터(UGameSetting)가 실제 화면 위젯에 어떻게 연결되고,
사용자 입력이 어떻게 Setting 모델에 전달되는지를 설명한다.

---

## 전체 구조 — MVC

```
Model  : UGameSetting (값, EditCondition 보유)
View   : UGameSettingListEntryBase 서브클래스 (위젯)
연결점 : SetSetting() — 이벤트 구독으로 Model↔View를 연결
```

ListView는 `UGameSetting*`을 아이템으로 갖는다.
항목이 화면에 보일 때 ListView가 ListEntry 위젯을 꺼내 `SetSetting(Setting)`을 호출하여 연결한다.

---

## 1단계 — SetSetting() : 연결 진입점

ListView에서 항목을 렌더링할 때 한 번 호출된다.

```cpp
// GameSettingListEntry.cpp:26
void UGameSettingListEntryBase::SetSetting(UGameSetting* InSetting)
{
    Setting = InSetting;

    // Model → View : Setting 값이 바뀌면 UI 갱신
    Setting->OnSettingChangedEvent.AddUObject(this, &ThisClass::HandleSettingChanged);

    // Model → View : EditCondition이 바뀌면 활성/숨김 상태 갱신
    Setting->OnSettingEditConditionChangedEvent.AddUObject(this, &ThisClass::HandleEditConditionChanged);

    // 연결 직후 현재 EditCondition 상태를 즉시 반영
    HandleEditConditionChanged(Setting);
}
```

서브클래스는 `Super::SetSetting()` 이후 자신의 초기 표시를 세팅한다:

```cpp
// Discrete 서브클래스
void UGameSettingListEntrySetting_Discrete::SetSetting(UGameSetting* InSetting)
{
    DiscreteSetting = Cast<UGameSettingValueDiscrete>(InSetting);
    Super::SetSetting(InSetting);   // 이벤트 구독
    Refresh();                      // 현재 값으로 Rotator 초기화
}
```

---

## 2단계 — UI → Model : 사용자 입력 흐름

### Discrete (좌/우 버튼, Rotator)

```
[오른쪽 버튼 클릭]
Button_Increase->OnClicked
    └─ HandleOptionIncrease()
            └─ Rotator_SettingValue->ShiftTextRight()     // Rotator UI 즉시 갱신
            └─ DiscreteSetting->SetDiscreteOptionByIndex(NewIndex)
                    └─ 값 저장
                    └─ NotifySettingChanged(EGameSettingChangeReason::Change)
                            └─ OnSettingChangedEvent.Broadcast(this, Reason)
```

### Scalar (슬라이더)

슬라이더는 드래그 중에는 Model에 값을 쓰지만 `bSuspendChangeUpdates`로 역방향 이벤트(Model→UI)를 차단한다.
슬라이더가 이미 움직이고 있는데 Setting 변경 이벤트가 다시 Slider 값을 바꾸면 루프가 생기기 때문이다.

```cpp
void UGameSettingListEntrySetting_Scalar::HandleSliderValueChanged(float Value)
{
    TGuardValue<bool> Suspend(bSuspendChangeUpdates, true);  // ← 역방향 갱신 차단

    ScalarSetting->SetValueNormalized(Value);    // Model에 쓰기
    Value = ScalarSetting->GetValueNormalized(); // 클램프된 값 다시 읽기

    Slider_SettingValue->SetValue(Value);        // 클램프된 값으로 보정
    Text_SettingValue->SetText(ScalarSetting->GetFormattedText());
    OnValueChanged(Value);
}
```

`HandleSettingChanged()`에서 `bSuspendChangeUpdates`를 확인:

```cpp
void UGameSettingListEntryBase::HandleSettingChanged(UGameSetting* InSetting, EGameSettingChangeReason Reason)
{
    if (!bSuspendChangeUpdates)   // 슬라이더 드래그 중이면 무시
    {
        OnSettingChanged();
    }
}
```

---

## 3단계 — Model → UI : 값 변경 반영 흐름

Setting 값이 외부(의존 설정, ResetToDefault 등)에 의해 바뀌면 UI에 반영된다.

```
Setting->NotifySettingChanged()
    └─ OnSettingChangedEvent.Broadcast(this, Reason)
            └─ ListEntry->HandleSettingChanged()
                    └─ if (!bSuspendChangeUpdates)
                            └─ OnSettingChanged()
                                    └─ Refresh()   // 현재 값으로 위젯 다시 채움
```

`Refresh()`는 서브클래스마다 다르게 구현된다:

```cpp
// Discrete: Rotator에 현재 선택 인덱스 반영
void UGameSettingListEntrySetting_Discrete::Refresh()
{
    Rotator_SettingValue->SetSelectedItem(DiscreteSetting->GetDiscreteOptionIndex());
}

// Scalar: 슬라이더와 텍스트에 현재 값 반영
void UGameSettingListEntrySetting_Scalar::Refresh()
{
    Slider_SettingValue->SetValue(ScalarSetting->GetValueNormalized());
    Text_SettingValue->SetText(ScalarSetting->GetFormattedText());
}
```

---

## 4단계 — EditCondition 변경 → 위젯 상태 반영

Setting의 EditCondition이 재평가되면(`RefreshEditableState`) UI의 활성/비활성 상태가 바뀐다.

```
Setting->NotifyEditConditionsChanged()
    └─ OnSettingEditConditionChangedEvent.Broadcast(this)
            └─ ListEntry->HandleEditConditionChanged(Setting)
                    └─ EditableState = Setting->GetEditState()   // 캐시된 상태 읽기
                    └─ RefreshEditableState(EditableState)
```

서브클래스에서 `RefreshEditableState()`로 실제 위젯을 제어:

```cpp
// Discrete
void UGameSettingListEntrySetting_Discrete::RefreshEditableState(const FGameSettingEditableState& InEditableState)
{
    const bool bLocalIsEnabled = InEditableState.IsEnabled();
    Button_Decrease->SetIsEnabled(bLocalIsEnabled);
    Rotator_SettingValue->SetIsEnabled(bLocalIsEnabled);
    Button_Increase->SetIsEnabled(bLocalIsEnabled);
    Panel_Value->SetIsEnabled(bLocalIsEnabled);
}

// Scalar
void UGameSettingListEntrySetting_Scalar::RefreshEditableState(const FGameSettingEditableState& InEditableState)
{
    Slider_SettingValue->SetIsEnabled(InEditableState.IsEnabled());
    Panel_Value->SetIsEnabled(InEditableState.IsEnabled());
}
```

Discrete는 `HandleEditConditionChanged()`를 추가로 오버라이드해서 `Refresh()`도 같이 호출한다.
EditCondition이 바뀌면 선택지 목록 자체가 달라질 수 있기 때문이다(`DisableOption` 등).

```cpp
void UGameSettingListEntrySetting_Discrete::HandleEditConditionChanged(UGameSetting* InSetting)
{
    Super::HandleEditConditionChanged(InSetting);  // RefreshEditableState 호출
    Refresh();                                     // 선택지 목록도 재구성
}
```

---

## 5단계 — ListView 풀링과 위젯 반환

ListView는 위젯을 풀(Pool)로 관리한다.
스크롤 등으로 항목이 화면 밖으로 나가면 위젯이 풀로 반환되고, 다른 항목에 재사용된다.

반환 시 `NativeOnEntryReleased()` 에서 이벤트 구독을 해제한다:

```cpp
void UGameSettingListEntryBase::NativeOnEntryReleased()
{
    StopAllAnimations();

    if (ensure(Setting))
    {
        Setting->OnSettingEditConditionChangedEvent.RemoveAll(this);
        Setting->OnSettingChangedEvent.RemoveAll(this);
    }

    Setting = nullptr;   // 참조 해제
}
```

해제하지 않으면 다른 Setting에 재사용된 위젯이 이전 Setting의 이벤트에 반응하는 버그가 생긴다.

---

## 전체 이벤트 흐름 요약

```
[사용자가 값 변경]
ListEntry(View) → Setting->SetValue()
                        └─ OnSettingChangedEvent.Broadcast
                                └─ (같은 ListEntry) HandleSettingChanged → OnSettingChanged → Refresh
                                └─ (의존하는 Setting) HandleEditDependencyChanged → RefreshEditableState
                                └─ (ChangeTracker) bSettingsChanged = true → "적용" 버튼 활성화

[의존 설정 변경으로 EditCondition 재평가]
OtherSetting 변경
    └─ AddEditDependency로 연결된 Setting → RefreshEditableState()
            └─ EditableStateCache 갱신
            └─ OnSettingEditConditionChangedEvent.Broadcast
                    └─ ListEntry->HandleEditConditionChanged → RefreshEditableState(위젯 활성/비활성)
                    └─ Panel->HandleSettingEditConditionsChanged → 가시성 바뀌면 RefreshSettingsList()
```

---

## 위젯 타입별 구조 요약

| ListEntry 클래스 | Setting 타입 | 핵심 위젯 | 입력 처리 |
|---|---|---|---|
| `*_Discrete` | `UGameSettingValueDiscrete` | `UGameSettingRotator` + 좌/우 버튼 | `SetDiscreteOptionByIndex()` |
| `*_Scalar` | `UGameSettingValueScalar` | `UAnalogSlider` + `UCommonTextBlock` | `SetValueNormalized()` |
| `*_Action` | `UGameSettingAction` | `UCommonButtonBase` | `ExecuteAction()` |
| `*_Navigation` | `UGameSettingCollectionPage` | `UCommonButtonBase` | `ExecuteNavigation()` |

모두 Abstract 클래스다. Blueprint에서 `BindWidget`으로 실제 위젯을 연결한다.
