# 02. CommonUI 포커스 처리

> 소스 경로  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/CommonActivatableWidget.cpp`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/Input/UIActionRouterTypes.cpp`

CommonUI는 Slate 포커스 시스템 위에 세 가지를 추가한다:

1. **초기 포커스 씨딩** — 레이어가 열릴 때 어느 위젯이 포커스를 받는가
2. **네비게이션 격리** — 포커스가 현재 활성 레이어 밖으로 나가지 않도록
3. **포커스 복귀** — 레이어가 닫힐 때 아래 레이어의 마지막 위치로 자동 복원

---

## 1. 초기 포커스 씨딩 — GetDesiredFocusTarget()

`UCommonActivatableWidget`이 활성화될 때 CommonUI는 `GetDesiredFocusTarget()`을 호출해 첫 포커스 위치를 결정한다.

```cpp
// CommonActivatableWidget.cpp
UWidget* UCommonActivatableWidget::NativeGetDesiredFocusTarget() const
{
    UWidget* DesiredFocusTarget = BP_GetDesiredFocusTarget();  // BP에서 구현
    if (!DesiredFocusTarget)
    {
        DesiredFocusTarget = GetDesiredFocusWidget();  // C++ fallback
    }
    return DesiredFocusTarget;
}
```

```cpp
// UIActionRouterTypes.cpp — 활성화 시 호출되는 포커스 씨딩 로직
if (UWidget* DesiredTarget = LeafWidget->GetDesiredFocusTarget())
{
    DesiredTarget->SetFocus();          // 지정한 위젯으로 즉시 포커스
}
else if (LeafWidget->IsFocusable())
{
    LeafWidget->SetFocus();             // fallback: 위젯 자신에게 포커스
}
```

### Blueprint 구현

```
GetDesiredFocusTarget 이벤트 오버라이드
    └─ Return: Button_FirstOption   ← 화면에서 처음 선택될 버튼 반환
```

구현하지 않으면 포커스가 설정되지 않아 게임패드로 아무것도 선택되지 않는다.

---

## 2. 네비게이션 격리 — FActivatableTreeNode

Slate의 기본 포커스 탐색은 화면에 보이는 모든 포커서블 위젯을 후보로 삼는다.  
여러 레이어(팝업 + 메뉴)가 동시에 보일 때 포커스가 레이어 경계를 넘어가는 문제가 생긴다.

CommonUI는 `FActivatableTreeNode`로 이 문제를 해결한다.

```
[스택 상태]
  PopupMenu (활성, 최상위)   ← FActivatableTreeNode: leaf
    └── Button_OK
    └── Button_Cancel
  MainMenu  (비활성)
    └── Button_Play
    └── Button_Settings

네비게이션: PopupMenu 내부에서만 순환
            Button_OK ↔ Button_Cancel
            MainMenu의 버튼으로 이동 안 됨
```

```cpp
// FActivatableTreeNode::IsExclusiveParentOfWidget()
// 위젯이 이 노드의 독점적 자식인지 확인 (하위 활성 노드 소속이 아닌 경우)
bool FActivatableTreeNode::IsExclusiveParentOfWidget(const TSharedPtr<SWidget>& SlateWidget) const
{
    if (IsParentOfWidget(SlateWidget, ExcludeSelf))
    {
        for (const FActivatableTreeNodeRef& ChildNode : GetChildren())
        {
            // 더 안쪽 활성 노드의 자식이면 이 노드의 독점 자식이 아님
            if (ChildNode->DoesWidgetSupportActivationFocus()
                && ChildNode->IsParentOfWidget(SlateWidget, ExcludeSelf))
            {
                return false;
            }
        }
        return true;
    }
    return false;
}
```

포커스를 설정할 때 `IsExclusiveParentOfWidget`으로 현재 활성 레이어 안에 있는 위젯인지 검증한다.  
이를 통해 가장 위에 있는 활성 레이어 안에서만 포커스가 움직이도록 강제한다.

---

## 3. 포커스 복귀 — 스택 pop 시 자동 복원

```
[예시]
MainMenu  에서 Button_Settings에 포커스
    → SettingsPopup 열림 → Button_OK에 포커스
    → SettingsPopup 닫힘 (DeactivateWidget)
    → MainMenu의 마지막 포커스였던 Button_Settings로 자동 복귀
```

CommonUI는 각 `UCommonActivatableWidget`의 **마지막 포커스 위치를 기억**하고,  
해당 레이어가 다시 최상위가 될 때 그 위치로 포커스를 복원한다.

---

## 4. 포커스 시각 피드백 — UCommonButtonBase

`UCommonButtonBase`는 마우스 호버와 게임패드 포커스를 별도 상태로 관리한다.

| 상태 | 트리거 |
|------|--------|
| `Hovered` | 마우스 커서가 버튼 위에 있을 때 (`OnMouseEnter`) |
| `Focused` | 게임패드가 이 버튼을 선택했을 때 (`OnFocusReceived`) |
| `Selected` | 선택 완료 상태 |
| `Disabled` | 비활성화 상태 |

포커스 연동 모드에서 커서가 보이지 않아도, `Focused` 상태가 트리거되어 버튼이 시각적으로 강조된다.  
`UCommonButtonStyle`에 각 상태별 브러시/색상을 정의한다.

---

## 포커스 이동이 안 될 때 체크리스트

| 원인 | 해결 |
|------|------|
| `UButton` 사용 | `UCommonButtonBase` (또는 `ULyraButtonBase`)로 교체 |
| `IsFocusable = false` | 버튼 디테일에서 `Is Focusable = true` 설정 |
| `GetDesiredFocusTarget` 미구현 | 레이어 진입 시 포커스 시작점 없음 → 구현 필요 |
| 위젯이 `Disabled` 상태 | Enable 처리 확인 |
| `Visibility = HitTestInvisible` | `SelfHitTestInvisible` 또는 `Visible`로 변경 |
| 다른 활성 레이어가 포커스 독점 | 의도치 않게 열린 레이어 확인 |

---

## 전체 흐름 요약

```
[UCommonActivatableWidget 활성화]
        ↓
GetDesiredFocusTarget() → SetFocus()
        ↓
[포커스 씨딩 완료 — 첫 위젯이 포커스를 가짐]
        ↓
[D-pad / 왼쪽 스틱]
        ↓
FNavigationConfig → Navigate() → FNavigationReply
        ↓
FActivatableTreeNode 격리 검증
        ↓
포커스 이동 → OnFocusLost / OnFocusReceived
        ↓
UCommonButtonBase: Focused 상태로 시각 전환
        ↓
[UCommonActivatableWidget 비활성화]
        ↓
마지막 포커스 위치 기억 → 아래 레이어 복원
```
