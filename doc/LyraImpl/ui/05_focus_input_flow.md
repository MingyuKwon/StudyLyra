# 포커스 입력 처리 전체 경로 — 시나리오별 분석

> 소스 경로  
> - `Source/LyraGame/UI/LyraHUDLayout.cpp`  
> - `Plugins/CommonUI/.../CommonActivatableWidget.cpp`  
> - `Plugins/CommonUI/.../CommonUIActionRouterBase.cpp`  
> - `Plugins/CommonUI/.../UIActionRouterTypes.cpp`  
> - `Engine/Source/Runtime/Slate/.../SlateApplication.cpp`  
> - `Engine/Source/Runtime/Slate/.../SListView.h`

---

## 입력 파이프라인 전체 구조

게임패드 입력이 들어왔을 때 두 갈래로 나뉜다.

```
[게임패드 입력]
        ↓
FSlateApplication (입력 수신)
        ↓
UCommonUIActionRouterBase::ProcessInput()  ← Slate 전처리기로 등록됨
        │
        ├─ UIAction 키(LB/RB/B/ESC)인가?
        │       YES → FUIActionBinding 실행 → return Handled
        │               (Slate 포커스 시스템에 도달하지 않음)
        │
        └─ 아니오 (D-pad/스틱)
                ↓ return Unhandled
        FNavigationConfig::GetNavigationDirectionFromKey()
                ↓ EUINavigation::Up / Down / Left / Right
        FSlateApplication: 포커스 경로 상향 순회
                ↓
        각 위젯의 OnNavigation() 호출
                ↓
        FNavigationReply 해석 → 포커스 이동
```

**핵심 분기점**: LB/RB/B/ESC 같은 UIAction 키는 Slate 네비게이션에 절대 도달하지 않는다.  
D-pad만이 Slate 포커스 시스템을 통과한다.

---

## 시나리오 1 — ESC 누름 → 설정 화면 열림 → 초기 포커스 씨딩

```
[ESC 입력]
        ↓
UCommonUIActionRouterBase::ProcessInput()
        ↓ "UI.Action.Escape" UIAction 매칭
FUIActionBinding::ExecuteIfBound()
        ↓
ULyraHUDLayout::HandleEscapeAction()
        ↓
UCommonUIExtensions::PushStreamedContentToLayer_ForPlayer(TAG_UI_LAYER_MENU, EscapeMenuClass)
        ↓
ULyraSettingScreen 위젯 생성 → 레이어 스택에 push
        ↓
FActivatableTreeNode 생성 → HandleWidgetActivated() 바인딩
        ↓
UCommonActivatableWidget::ActivateWidget()
  → NativeOnActivated()
        ↓
FActivatableTreeNode::HandleWidgetActivated()
  → GetRoot()->UpdateLeafmostActiveNode(SettingsScreenNode)
        ↓
FActivatableTreeRoot::ApplyLeafmostNodeConfig()
  → FocusLeafmostNode()
        ↓
[포커스 씨딩 우선순위 결정]
  1순위: LeafWidget->AutoRestoresFocus() && GetFocusFallbackTarget()
         → 이전에 이 화면이 열렸던 적이 있으면 마지막 포커스 위치 복원
  2순위: LeafWidget->GetDesiredFocusTarget()
         → UGameSettingScreen::NativeGetDesiredFocusTarget() → Settings_Panel 반환
  3순위: LeafWidget 자신에게 SetFocus()
        ↓
Settings_Panel->SetFocus()
        ↓
UGameSettingPanel::NativeOnFocusReceived()
  → 게임패드 입력 감지
  → ListView_Settings->NavigateToIndex(0)
  → ListView_Settings->SetSelectedIndex(0)
        ↓
[첫 번째 설정 항목에 포커스 완료]
```

**소스 근거** (`UIActionRouterTypes.cpp:1651`):
```cpp
if (TSharedPtr<SWidget> AutoRestoreTarget = LeafWidget->AutoRestoresFocus()
        ? PinnedLeafmostNode->GetFocusFallbackTarget() : nullptr)
{
    FSlateApplication::Get().SetUserFocus(OwnerSlateId, AutoRestoreTarget);  // 복원
}
else if (UWidget* DesiredTarget = LeafWidget->GetDesiredFocusTarget())
{
    DesiredTarget->SetFocus();   // 씨딩
}
```

---

## 시나리오 2 — D-pad Down → 리스트 다음 항목으로 이동

```
[Gamepad_DPad_Down 입력]
        ↓
UCommonUIActionRouterBase::ProcessInput()
  → UIAction 키 아님 → Unhandled 반환
        ↓
FSlateApplication::OnKeyDown()
        ↓
FNavigationConfig::GetNavigationDirectionFromKey(DPad_Down)
  → EUINavigation::Down
        ↓
FReply::Navigate(Down) 생성
        ↓
FSlateApplication::ProcessReply()  (SlateApplication.cpp:3629)
  포커스 경로 위젯을 아래에서 위로 순회:
    [현재 포커스: 리스트 아이템 위젯]
        ↓
SListView::OnNavigation(Down)  (SListView.h:512)
  → AttemptSelectIndex = CurSelectionIndex + 1
  → ItemsSourceRef.IsValidIndex(AttemptSelectIndex) == true (리스트 안)
  → NavigationSelect(NextItem)   ← 내부에서 선택 + 스크롤
  → return FNavigationReply::Explicit(nullptr)   ← "처리 완료"
        ↓
AttemptNavigation() → 타깃이 nullptr → 포커스 변동 없음 (이미 내부 처리됨)
        ↓
[다음 설정 항목 선택 + 시각 포커스 이동 완료]
```

`Explicit(nullptr)`는 "네비게이션을 내가 처리했으니 외부로 나가지 말라"는 신호다.  
포커스가 리스트 밖으로 나가지 않는 핵심 이유가 여기에 있다.

---

## 시나리오 3 — D-pad Up (첫 번째 항목에서) → 경계 동작

```
[Gamepad_DPad_Up, 현재: 리스트 첫 번째 항목]
        ↓
SListView::OnNavigation(Up)
  → AttemptSelectIndex = 0 - 1 = -1
  → ItemsSourceRef.IsValidIndex(-1) == false
  → return STableViewBase::OnNavigation()
           → SWidget::OnNavigation() 기본값
           → FNavigationReply::Escape()   ← "경계 통과 허용"
        ↓
SlateApplication: Escape 반환 → 부모 위젯으로 계속 올라감
        ↓
UGameSettingPanel의 OnNavigation() → 오버라이드 없음 → Escape
        ↓
ULyraSettingScreen의 OnNavigation() → 오버라이드 없음 → Escape
        ↓
최상위 도달 → AttemptNavigation() with Escape
  → 화면 좌표 기반 기하 탐색: Up 방향의 포커서블 위젯 후보 수집
  → 탭 바 버튼(ULyraTabButtonBase)이 IsFocusable == false 이면 후보 제외
  → 후보 없음 → 포커스 변동 없음
```

기하 탐색 후보에서 탭 버튼이 제외되는 이유가 `IsFocusable = false` 설정이다.  
C++ 코드에는 명시적 차단이 없고, Blueprint 레벨의 설정이 방어선이 된다.

---

## 시나리오 4 — LB → 탭 전환 → 포커스 재씨딩

```
[Gamepad_LeftShoulder 입력]
        ↓
UCommonUIActionRouterBase::ProcessInput()
  → "UI.Action.PrevTab" UIAction 매칭 (LyraSettingScreen에 등록됨)
        ↓
탭 전환 델리게이트 실행
  → ULyraTabListWidgetBase::SelectTabByID(PrevTabId)
        ↓
UCommonTabListWidgetBase 탭 선택 변경
  → OnTabSelected 브로드캐스트
        ↓
[BP에서 NavigateToSetting() 또는 SetFilterState() 호출]
        ↓
UGameSettingPanel::SetFilterState(새 탭 필터)
  → RefreshSettingsList() 예약 (FTSTicker 다음 프레임)
        ↓
[다음 Tick]
RefreshSettingsList() 실행
  → Registry->GetSettingsForFilter() → 새 탭 설정 목록
  → ListView_Settings->SetListItems(VisibleSettings)
  → ListView_Settings->NavigateToIndex(0)   ← 포커스 수동 재씨딩
  → ListView_Settings->SetSelectedIndex(0)
        ↓
[새 탭 첫 번째 항목에 포커스 완료]
```

탭 전환은 ActivatableWidget 교체가 아니므로 CommonUI의 자동 씨딩이 없다.  
`RefreshSettingsList()` 내부의 `NavigateToIndex(0)` 호출이 유일한 포커스 재씨딩 지점이다.

---

## 시나리오 5 — B버튼 → 설정 화면 닫힘 → HUD 포커스 복귀

```
[Gamepad_FaceButton_Right (B) 입력]
        ↓
UCommonUIActionRouterBase::ProcessInput()
  → "UI.Action.Back" UIAction 매칭 (LyraSettingScreen에 등록됨)
        ↓
ULyraSettingScreen::HandleBackAction()
  → ApplyChanges()
  → DeactivateWidget()
        ↓
UCommonActivatableWidget::InternalProcessDeactivation()
  → NativeOnDeactivated()
  → OnDeactivated().Broadcast()
        ↓
FActivatableTreeNode::HandleWidgetDeactivated()
  → SetCanReceiveInput(false)
  → NearestActiveParent 탐색 (HUDLayout 노드)
  → GetActionRouter().UpdateLeafNodeAndConfig(Root, HUDNode)
        ↓
FActivatableTreeRoot::UpdateLeafmostActiveNode()
  [LeafmostActiveNode 교체 직전]
  → PinnedLeafmostActiveNode->CacheFocusRestorationTarget()
    (SettingsScreen의 마지막 포커스 위치 기억 — 다음번 열릴 때 복원에 사용)
  → LeafmostActiveNode = HUDNode
        ↓
FocusLeafmostNode()
  → LeafWidget (HUDLayout)->AutoRestoresFocus() 확인
      YES: HUDNode->GetFocusFallbackTarget() → 설정 열리기 전 마지막 포커스 위치
           FSlateApplication::SetUserFocus(OwnerSlateId, AutoRestoreTarget)
      NO:  HUDLayout->GetDesiredFocusTarget() → 또는 게임 뷰포트에 포커스
        ↓
[HUD 또는 게임 뷰포트로 포커스 복귀 완료]
```

**포커스 캐시 타이밍** (`UIActionRouterTypes.cpp:1470`):
```cpp
// 새 leafmost로 교체하기 직전에 현재 leafmost의 포커스를 기억
PinnedLeafmostActiveNode->CacheFocusRestorationTarget();
```

설정 화면이 열릴 때 HUDLayout이 leafmost였으므로, 그 시점의 HUD 포커스가 캐시된다.  
설정 화면이 닫히면 그 캐시를 꺼내서 복원한다.

---

## 시나리오 요약

| 시나리오 | 입력 경로 | 포커스 결정자 |
|----------|-----------|--------------|
| 설정 화면 열림 | UIAction → PushToLayer → ActivateWidget | `GetDesiredFocusTarget()` → `NativeOnFocusReceived()` |
| D-pad 리스트 이동 | Slate Navigate → `SListView::OnNavigation()` | `NavigationSelect()` + `Explicit(nullptr)` |
| D-pad 경계 | Slate Navigate → `Escape()` → 기하 탐색 | 탭 버튼 `IsFocusable=false`로 후보 제외 |
| 탭 전환 | UIAction → `SetFilterState()` | `RefreshSettingsList()` → `NavigateToIndex(0)` |
| 화면 닫힘 | UIAction → `DeactivateWidget()` | `CacheFocusRestorationTarget()` → `AutoRestoresFocus()` |

---

## 핵심 패턴 정리

CommonUI의 포커스 관리는 세 가지 레이어가 협력한다.

```
[UIAction 레이어]   — 탭 전환 / 화면 열고 닫기 / 뒤로가기
                      Slate 포커스 시스템에 도달하지 않음

[CommonUI 레이어]   — ActivatableWidget 활성화 시 포커스 씨딩·복귀 자동화
                      FActivatableTreeNode / FocusLeafmostNode()

[Slate 레이어]      — D-pad 방향 이동만 담당
                      SListView::OnNavigation() + 기하 탐색
```

각 레이어가 담당 영역이 명확히 분리되어 있어서, Slate 포커스 로직을 건드리지 않아도 화면 전환이나 탭 전환에서 포커스가 자연스럽게 처리된다.
