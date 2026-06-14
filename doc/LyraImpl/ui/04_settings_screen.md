# 설정 화면 — 포커스 구현 분석

> 소스: `Source/LyraGame/UI/LyraSettingScreen.h/cpp`  
> `Plugins/GameSettings/Source/Public/Widgets/GameSettingScreen.h/cpp`  
> `Plugins/GameSettings/Source/Public/Widgets/GameSettingPanel.h/cpp`  
> `Source/LyraGame/UI/Common/LyraTabListWidgetBase.h/cpp`

Lyra 설정 화면이 CommonUI 포커스 시스템을 어떻게 활용하는지 구조부터 동작까지 분석한다.

---

## 클래스 계층

```
ULyraSettingScreen           (UCommonActivatableWidget)
  └── UGameSettingScreen     (UCommonActivatableWidget)
```

설정 화면 전체가 하나의 `UCommonActivatableWidget`이다.  
탭별로 ActivatableWidget을 분리하지 않는다.

---

## 위젯 구조

```
ULyraSettingScreen  (UCommonActivatableWidget)
  ├── TopSettingsTabs   (ULyraTabListWidgetBase)
  │    ├── Tab button "Gameplay"
  │    ├── Tab button "Video"
  │    ├── Tab button "Audio"
  │    └── Tab button "Controls"
  └── Settings_Panel    (UGameSettingPanel — UCommonUserWidget)
       ├── ListView_Settings   (UGameSettingListView)
       └── Details_Settings    (UGameSettingDetailView)
```

탭 콘텐츠를 위젯으로 교체하는 게 아니라, `Settings_Panel` 하나가 탭에 따라 **필터만 바꿔** 다른 설정 목록을 표시한다.

---

## 포커스 흐름

### 화면이 열릴 때

```cpp
// GameSettingScreen.cpp
UWidget* UGameSettingScreen::NativeGetDesiredFocusTarget() const
{
    if (UWidget* Target = BP_GetDesiredFocusTarget())
        return Target;

    return Settings_Panel;  // 패널 자체를 포커스 타깃으로 지정
}
```

CommonUI가 `NativeGetDesiredFocusTarget()`을 호출 → `Settings_Panel`에 `SetFocus()` → `NativeOnFocusReceived()` 발동.

```cpp
// GameSettingPanel.cpp
UGameSettingPanel::UGameSettingPanel()
{
    SetIsFocusable(true);  // 패널이 포커스를 받을 수 있어야 NativeOnFocusReceived가 동작
}

FReply UGameSettingPanel::NativeOnFocusReceived(const FGeometry& InGeometry, const FFocusEvent& InFocusEvent)
{
    if (/* 게임패드 입력 */)
    {
        ListView_Settings->NavigateToIndex(0);  // 리스트 첫 항목으로 이동
        ListView_Settings->SetSelectedIndex(0);
        return FReply::Handled();
    }
    return FReply::Unhandled();
}
```

패널이 포커스를 받는 순간 `NativeOnFocusReceived`가 리스트 첫 항목으로 포커스를 밀어넣는다.  
CommonUI의 자동 씨딩(`GetDesiredFocusTarget`)과 수동 전달(`NativeOnFocusReceived`)이 이어지는 구조다.

### 탭이 바뀔 때

```
탭 선택
  → BP에서 NavigateToSetting() 호출
  → Settings_Panel->SetFilterState(새 카테고리 필터)
  → RefreshSettingsList() 예약 (다음 Ticker)
  → ListView_Settings->NavigateToIndex(0)   ← 새 탭 첫 항목으로 재씨딩
  → ListView_Settings->SetSelectedIndex(0)
```

탭이 바뀌어도 `Settings_Panel`은 교체되지 않는다.  
`RefreshSettingsList()`가 내부적으로 `NavigateToIndex(0)`을 호출하기 때문에 포커스가 자동으로 새 탭 첫 항목으로 이동한다.

---

## 탭 전환 입력

탭 버튼(`ULyraTabButtonBase`)은 `UCommonButtonBase`를 상속하므로 기술적으로 포커서블하다.  
그러나 Lyra는 탭 전환을 D-pad 네비게이션이 아닌 **UIAction(LB/RB)**으로 처리한다.

```cpp
// LyraSettingScreen.cpp
void ULyraSettingScreen::NativeOnInitialized()
{
    BackHandle   = RegisterUIActionBinding(...HandleBackAction);
    ApplyHandle  = RegisterUIActionBinding(...HandleApplyAction);
    CancelHandle = RegisterUIActionBinding(...HandleCancelChangesAction);
}
```

탭 전환 LB/RB도 같은 방식으로 등록된다.  
결과적으로 D-pad는 설정 목록 내부 이동에만 사용되고, 탭 바 버튼까지 D-pad로 이동할 일이 없다.

---

## 포커스 설계 선택 요약

| 항목 | 선택 | 이유 |
|------|------|------|
| 탭별 ActivatableWidget | 사용 안 함 | 탭 내용이 필터 차이뿐이라 구조 복잡도 대비 이득이 없음 |
| 탭 전환 후 포커스 재씨딩 | `RefreshSettingsList()` → `NavigateToIndex(0)` | 리스트 갱신과 포커스 재설정을 한 번에 처리 |
| 탭 전환 입력 | UIAction (LB/RB) | D-pad를 탭 바와 공유하지 않아 포커스 격리 불필요 |
| 초기 포커스 | `GetDesiredFocusTarget` → `NativeOnFocusReceived` 체인 | 패널 → 리스트로 두 단계 위임 |
