# 05. UI 위젯 계층 — "키를 누르세요" 감지 동작

> 출처: `Source/LyraGame/Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.h/cpp`,  
>        GameSettings 플러그인 `Widgets/Misc/GameSettingPressAnyKey.h`,  
>        `Widgets/Misc/KeyAlreadyBoundWarning.h`

---

## 위젯 계층 구조

```
설정 화면 리스트
    └─ ULyraSettingsListEntrySetting_KeyboardInput  ← 액션 1개의 행(Row)
            ├─ Button_PrimaryKey    [ULyraButtonBase]  ← 현재 Primary 키 표시
            ├─ Button_SecondaryKey  [ULyraButtonBase]  ← 현재 Secondary 키 표시
            ├─ Button_Clear         [ULyraButtonBase]  ← 두 슬롯 모두 Invalid로 클리어
            └─ Button_ResetToDefault [ULyraButtonBase] ← 기본값으로 리셋 (커스텀 시에만 표시)

[모달 레이어 UI.Layer.Modal]
    ├─ UGameSettingPressAnyKey     ← 키 입력 대기 모달
    └─ UKeyAlreadyBoundWarning     ← 중복 키 경고 모달
```

---

## `ULyraSettingsListEntrySetting_KeyboardInput` 상세

### 클래스 선언

```cpp
UCLASS(Abstract, Blueprintable, meta = (Category = "Settings", DisableNativeTick))
class ULyraSettingsListEntrySetting_KeyboardInput : public UGameSettingListEntry_Setting
{
    // BindWidget — 블루프린트에서 이름 일치하는 위젯과 자동 연결
    UPROPERTY(BlueprintReadOnly, meta = (BindWidget))
    TObjectPtr<ULyraButtonBase> Button_PrimaryKey;

    UPROPERTY(BlueprintReadOnly, meta = (BindWidget))
    TObjectPtr<ULyraButtonBase> Button_SecondaryKey;

    UPROPERTY(BlueprintReadOnly, meta = (BindWidget))
    TObjectPtr<ULyraButtonBase> Button_Clear;

    UPROPERTY(BlueprintReadOnly, meta = (BindWidget))
    TObjectPtr<ULyraButtonBase> Button_ResetToDefault;

    // 사용할 모달 위젯 클래스 (블루프린트에서 지정)
    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UGameSettingPressAnyKey> PressAnyKeyPanelClass;

    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UKeyAlreadyBoundWarning> KeyAlreadyBoundWarningPanelClass;

    // 중복 경고 → 확인 시 실제 바인딩할 키를 임시 보관
    UPROPERTY(Transient)
    FKey OriginalKeyToBind = EKeys::Invalid;
};
```

### 초기화

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::NativeOnInitialized()
{
    Super::NativeOnInitialized();

    Button_PrimaryKey->OnClicked().AddUObject(this, &ThisClass::HandlePrimaryKeyClicked);
    Button_SecondaryKey->OnClicked().AddUObject(this, &ThisClass::HandleSecondaryKeyClicked);
    Button_Clear->OnClicked().AddUObject(this, &ThisClass::HandleClearClicked);
    Button_ResetToDefault->OnClicked().AddUObject(this, &ThisClass::HandleResetToDefaultClicked);
}
```

### 설정 연결

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::SetSetting(UGameSetting* InSetting)
{
    KeyboardInputSetting = CastChecked<ULyraSettingKeyboardInput>(InSetting);
    Super::SetSetting(InSetting);
    Refresh();  // 버튼 텍스트를 현재 키 이름으로 갱신
}
```

### UI 갱신 (`Refresh`)

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::Refresh()
{
    if (ensure(KeyboardInputSetting))
    {
        Button_PrimaryKey->SetButtonText(
            KeyboardInputSetting->GetKeyTextFromSlot(EPlayerMappableKeySlot::First));
        Button_SecondaryKey->SetButtonText(
            KeyboardInputSetting->GetKeyTextFromSlot(EPlayerMappableKeySlot::Second));

        // 기본값에서 바뀐 경우에만 "리셋" 버튼 표시
        Button_ResetToDefault->SetVisibility(
            KeyboardInputSetting->IsMappingCustomized()
                ? ESlateVisibility::Visible
                : ESlateVisibility::Hidden);
    }
}
```

`OnSettingChanged()`도 `Refresh()`를 호출한다.  
→ `ChangeBinding()` 후 `NotifySettingChanged()`가 이를 트리거해 버튼이 즉시 갱신된다.

---

## 키 입력 캡처 흐름 — Primary 키 변경 예시

### 1단계: 버튼 클릭 → PressAnyKey 모달 열기

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandlePrimaryKeyClicked()
{
    UGameSettingPressAnyKey* PressAnyKeyPanel = CastChecked<UGameSettingPressAnyKey>(
        UCommonUIExtensions::PushContentToLayer_ForPlayer(
            GetOwningLocalPlayer(),
            PressAnyKeyLayer,          // "UI.Layer.Modal"
            PressAnyKeyPanelClass));   // 블루프린트로 지정한 위젯 클래스

    PressAnyKeyPanel->OnKeySelected.AddUObject(
        this, &ThisClass::HandlePrimaryKeySelected, PressAnyKeyPanel);
    PressAnyKeyPanel->OnKeySelectionCanceled.AddUObject(
        this, &ThisClass::HandleKeySelectionCanceled, PressAnyKeyPanel);
}
```

`PushContentToLayer_ForPlayer("UI.Layer.Modal", ...)`:
- Modal 레이어에 위젯을 push → 게임 입력 차단, 다른 UI 위에 오버레이
- `CommonUIExtensions`는 Common UI의 레이어 스택 시스템 API

---

### 2단계: `UGameSettingPressAnyKey` 동작 (엔진/플러그인)

```cpp
// GameSettingPressAnyKey.cpp (GameSettings 플러그인)
void UGameSettingPressAnyKey::NativeOnActivated()
{
    Super::NativeOnActivated();
    FlushPressedKeys();  // 버튼 클릭 키 등 현재 눌린 키 상태 초기화
    // → Slate 레벨 OnKeyDown 캡처 시작
}

// 키 입력 이벤트
FReply UGameSettingPressAnyKey::NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
    const FKey Key = InKeyEvent.GetKey();

    // ESC = 취소
    if (Key == EKeys::Escape)
    {
        OnKeySelectionCanceled.Broadcast(this);
        DeactivateWidget();
        return FReply::Handled();
    }

    // 단독 한정자 키(Ctrl/Shift/Alt 단독) = 무시
    if (Key.IsModifierKey())
        return FReply::Handled();

    // 유효한 키 → 선택 완료
    OnKeySelected.Broadcast(Key, this);
    DeactivateWidget();
    return FReply::Handled();
}
```

**FlushPressedKeys()의 이유**:  
"Primary 키" 버튼을 클릭하면 마우스 클릭(Left Mouse Button) 이벤트가 발생한다.  
`FlushPressedKeys()` 없이는 이 클릭이 새 키로 즉시 등록되어버린다.

**ESC 예약**:  
ESC는 항상 "취소"로 처리된다. 따라서 ESC 자체를 키 바인딩으로 지정하는 것은 불가능하다.

---

### 3단계: 키 선택됨 → 중복 확인

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandlePrimaryKeySelected(
    FKey InKey, UGameSettingPressAnyKey* PressAnyKeyPanel)
{
    PressAnyKeyPanel->OnKeySelected.RemoveAll(this);
    ChangeBinding(0, InKey);  // Slot 0 = Primary
}
```

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::ChangeBinding(int32 InKeyBindSlot, FKey InKey)
{
    OriginalKeyToBind = InKey;  // 중복 확인 후 실제 적용 시 필요

    // 이 키가 이미 다른 액션에 바인딩되어 있는지 조회
    TArray<FName> ActionsForKey;
    KeyboardInputSetting->GetAllMappedActionsFromKey(InKeyBindSlot, InKey, ActionsForKey);

    if (!ActionsForKey.IsEmpty())
    {
        // 중복 있음 → 경고 모달
        UKeyAlreadyBoundWarning* Warning = CastChecked<UKeyAlreadyBoundWarning>(
            UCommonUIExtensions::PushContentToLayer_ForPlayer(
                GetOwningLocalPlayer(), PressAnyKeyLayer, KeyAlreadyBoundWarningPanelClass));

        FFormatNamedArguments Args;
        Args.Add(TEXT("InKey"), InKey.GetDisplayName());
        Args.Add(TEXT("ActionNames"), FText::FromString(ActionNames));

        Warning->SetWarningText(FText::Format(
            LOCTEXT("WarningText",
                "{InKey} is already bound to {ActionNames} are you sure you want to rebind it?"),
            Args));
        Warning->SetCancelText(FText::Format(
            LOCTEXT("CancelText",
                "Press escape to cancel, or press {InKey} again to confirm rebinding."),
            Args));

        // 슬롯별로 다른 핸들러 등록
        if (InKeyBindSlot == 1)
            Warning->OnKeySelected.AddUObject(this, &ThisClass::HandleSecondaryDuplicateKeySelected, Warning);
        else
            Warning->OnKeySelected.AddUObject(this, &ThisClass::HandlePrimaryDuplicateKeySelected, Warning);

        Warning->OnKeySelectionCanceled.AddUObject(this, &ThisClass::HandleKeySelectionCanceled, Warning);
    }
    else
    {
        // 중복 없음 → 바로 변경
        KeyboardInputSetting->ChangeBinding(InKeyBindSlot, InKey);
    }
}
```

---

### 4단계: 중복 경고 처리

**확인 (같은 키 다시 누름)**:
```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandlePrimaryDuplicateKeySelected(
    FKey InKey, UKeyAlreadyBoundWarning* DuplicateKeyPressAnyKeyPanel) const
{
    DuplicateKeyPressAnyKeyPanel->OnKeySelected.RemoveAll(this);
    KeyboardInputSetting->ChangeBinding(0, OriginalKeyToBind);  // 저장해둔 키로 적용
}
```

**취소 (ESC 누름)**:
```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandleKeySelectionCanceled(
    UKeyAlreadyBoundWarning* PressAnyKeyPanel)
{
    PressAnyKeyPanel->OnKeySelectionCanceled.RemoveAll(this);
    // 아무것도 변경하지 않음
}
```

---

## Clear / ResetToDefault

### Clear (두 슬롯 모두 무효화)

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandleClearClicked()
{
    KeyboardInputSetting->ChangeBinding(0, EKeys::Invalid);
    KeyboardInputSetting->ChangeBinding(1, EKeys::Invalid);
}
```

`EKeys::Invalid`로 바인딩하면 해당 슬롯에 키가 없는 상태가 된다.

### ResetToDefault (기본값으로 리셋)

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::HandleResetToDefaultClicked()
{
    KeyboardInputSetting->ResetToDefault();
}
```

내부적으로:
```cpp
// LyraSettingKeyboardInput.cpp
void ULyraSettingKeyboardInput::ResetToDefault()
{
    FMapPlayerKeyArgs Args = {};
    Args.MappingName = ActionMappingName;

    FGameplayTagContainer FailureReason;
    Settings->ResetAllPlayerKeysInRow(Args, FailureReason);

    NotifySettingChanged(EGameSettingChangeReason::Change);
}
```

`ResetAllPlayerKeysInRow()` — 해당 액션의 모든 슬롯을 `DefaultKey`로 복원.

---

## 전체 상태 다이어그램

```
[초기 상태]
Button_PrimaryKey: "E"
Button_SecondaryKey: "—"
Button_ResetToDefault: 숨김 (기본값 상태)

[Primary 버튼 클릭]
    → PressAnyKey 모달 열림
    → 키 입력 대기

    [ESC 누름]
        → 취소, 원상태 복귀

    [F 누름]
        → "F"가 이미 "달리기"에 바인딩되어 있는 경우
            → 중복 경고 모달 열림
                [ESC 누름] → 취소
                [F 다시 누름] → 확인 → ChangeBinding(0, F)

        → "F"가 아무데도 바인딩 안 된 경우
            → ChangeBinding(0, F)

[ChangeBinding(0, F) 실행]
    → MapPlayerKey() → CurrentKey = F (메모리)
    → NotifySettingChanged()
    → Refresh() 호출
    → Button_PrimaryKey: "F" (갱신됨)
    → Button_ResetToDefault: 표시됨 (IsCustomized() = true)

["기본값으로 리셋" 클릭]
    → ResetToDefault()
    → Refresh()
    → Button_PrimaryKey: "E" (원래 값 복원)
    → Button_ResetToDefault: 숨김 (다시 기본값)
```

---

## `NativeOnEntryReleased()` — 위젯 재사용

```cpp
void ULyraSettingsListEntrySetting_KeyboardInput::NativeOnEntryReleased()
{
    Super::NativeOnEntryReleased();
    KeyboardInputSetting = nullptr;
}
```

리스트 위젯은 **풀링(pooling)**으로 재사용된다.  
항목이 스크롤 밖으로 나가면 `Released` 상태가 되어 `KeyboardInputSetting` 참조를 nil로 초기화한다.  
이후 스크롤로 다시 진입하면 `SetSetting()`이 새 설정과 함께 호출된다.
