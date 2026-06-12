# 03. 스크롤 · 입력 처리 · 커서 가시성

> 소스: `CommonAnalogCursor.cpp`

---

## 아날로그 이동 모드

`bIsAnalogMovementEnabled == true` 일 때.  
`FAnalogCursor::CalculateTickedCursorPosition()` 을 그대로 호출해 스틱으로 커서를 직접 이동시킨다.  
개발 빌드(`!UE_BUILD_SHIPPING`)에서 L/R 숄더 + L/R 트리거 동시 누름으로 토글된다.

---

## 오른쪽 스틱 스크롤

```
Tick() (게임패드 + 뷰포트 포커스)
  └── bShouldHandleRightAnalog && TimeUntilScrollUpdate <= 0
        └── ActionRouter.GatherActiveAnalogScrollRecipients()
              ├── 반환값이 비어 있으면 → 스크롤 이벤트 발생하지 않음
              └── 등록된 ScrollBox/ListView/ScrollBar 마다
                    ├── DetermineScrollOrientation() → 수직/수평 판단
                    ├── ScrollAmount = (|value| - deadzone) / (1 - deadzone) × multiplier
                    └── SlateApp.ProcessMouseWheelOrGestureEvent(MouseEvent)
```

`AnalogScrollUpdatePeriod = 0.1f` 주기로만 스크롤 이벤트를 발생시켜 과도한 이벤트 발사를 막는다.

**스크롤이 동작하지 않는 근본 원인**: `GatherActiveAnalogScrollRecipients()`가 빈 배열을 반환하면 이벤트 자체가 발생하지 않는다.  
이 함수는 **사전에 명시적으로 등록된 위젯 목록**만 반환하며, 단순히 ScrollBox/ListView 위젯이 화면에 있다는 것만으로는 스크롤이 되지 않는다.

---

## GatherActiveAnalogScrollRecipients 동작 원리

```
GatherActiveAnalogScrollRecipients()
  └── ActiveRootNode->GatherScrollRecipients()
        └── FActivatableTreeNode::AppendValidScrollRecipients()
              └── 노드에 AddScrollRecipient()로 등록된 위젯만 수집
                    └── 자식 노드 재귀 탐색
```

등록 경로는 두 가지다:

**경로 1 — C++ / Blueprint에서 직접 호출**

```cpp
// UCommonUserWidget의 멤버 함수
void UCommonUserWidget::RegisterScrollRecipient(const UWidget& AnalogScrollRecipient);
void UCommonUserWidget::UnregisterScrollRecipient(const UWidget& AnalogScrollRecipient);

// Blueprint 노출 버전 (외부 위젯 등록용)
void RegisterScrollRecipientExternal(const UWidget* AnalogScrollRecipient);
void UnregisterScrollRecipientExternal(const UWidget* AnalogScrollRecipient);
```

`RegisterScrollRecipient`를 호출하면 내부적으로 `UCommonUIActionRouterBase::RegisterScrollRecipient()`를 거쳐  
`FActivatableTreeNode::AddScrollRecipient()`에 저장된다.

**경로 2 — OnWidgetRebuilt 자동 등록**

`UCommonUserWidget::OnWidgetRebuilt()`에서 `GetScrollRecipients()`가 반환하는 목록을  
ActionRouter에 일괄 등록한다.  
즉, `ScrollRecipients` 배열에 미리 담아 놓으면 위젯이 생성될 때 자동으로 등록된다.

---

## 스크롤이 안 될 때 체크리스트

**1. ScrollRecipient 등록 여부**

스크롤을 원하는 `ScrollBox` / `ListView`가 `RegisterScrollRecipient()`로 등록되었는지 확인한다.

```cpp
// NativeConstruct 또는 위젯 생성 시점에 호출
RegisterScrollRecipient(*MyScrollBox);
```

Blueprint에서는 `Register Scroll Recipient External` 노드를 사용한다.

**2. 위젯이 UCommonUserWidget 안에 있는지**

`RegisterScrollRecipient`는 `UCommonUserWidget`의 멤버다.  
일반 `UUserWidget`을 사용하는 경우 이 함수를 사용할 수 없다.  
`UCommonActivatableWidget`은 `UCommonUserWidget`을 상속하므로 사용 가능하다.

**3. bShouldHandleRightAnalog 플래그**

`FCommonAnalogCursor::ShouldHandleRightAnalog(false)`가 어딘가에서 호출된 경우  
오른쪽 스틱 스크롤 처리 자체가 비활성화된다.

**4. 게임패드 입력 중인지**

`IsUsingGamepad()` → `ActiveInputMethod == ECommonInputType::Gamepad` 가 true여야 한다.  
마우스/키보드 입력 상태에서는 오른쪽 스틱 스크롤이 동작하지 않는다.

**5. 게임 뷰포트가 포커스 경로에 있는지**

`IsGameViewportInFocusPathWithoutCapture()`가 false이면 Tick 처리 자체를 건너뛴다.  
뷰포트가 마우스 캡처 상태(게임 플레이 중)이거나 다른 창이 포커스를 가지고 있으면 해당된다.

---

## 입력 처리 조건 — IsRelevantInput

```cpp
// 키 이벤트
bool FCommonAnalogCursor::IsRelevantInput(const FKeyEvent& KeyEvent) const
{
    return IsUsingGamepad()                          // 게임패드 입력 장치일 때
        && FAnalogCursor::IsRelevantInput(KeyEvent)  // 올바른 유저 인덱스일 때
        && (IsGameViewportInFocusPathWithoutCapture()
            || (KeyEvent.GetKey() == EKeys::Virtual_Gamepad_Accept && CanReleaseMouseCapture()));
}
```

`IsGameViewportInFocusPathWithoutCapture()` 조건:
- 게임 뷰포트가 포커스 경로에 포함되어 있어야 함 (다른 창이 활성화면 무시)
- 단, 뷰포트가 커서 캡처(마우스 캡처)를 독점하고 있으면 처리하지 않음 → 인게임 플레이 중 UI가 입력을 가로채지 않음

---

## Virtual Accept 처리 확장

```cpp
bool FCommonAnalogCursor::HandleKeyDownEvent(...)
{
    // 1순위: ActionRouter에 바인딩된 UIAction이 있으면 먼저 처리
    if (bIsVirtualAccept && ActionRouter.ProcessInput(key, IE_Pressed) == Handled)
        return true;

    // 2순위: 마우스 클릭 시뮬레이션
    // SetIsGamepadSimulatedClick(true) 마킹 후 부모 호출
    InputSubsystem.SetIsGamepadSimulatedClick(bIsVirtualAccept);
    FAnalogCursor::HandleKeyDownEvent(SlateApp, InKeyEvent);
    InputSubsystem.SetIsGamepadSimulatedClick(false);
}
```

`SetIsGamepadSimulatedClick`으로 마킹하면 위젯 측에서 `UCommonInputSubsystem::IsGamepadSimulatedClick()`으로 판별해  
게임패드 클릭과 실제 마우스 클릭을 구분할 수 있다.

**오프스크린 위젯 처리**: `CVarShouldRouteOffscreenMouseButton`이 켜져 있으면  
히트 테스트 그리드를 우회하고 포커스된 위젯 경로로 직접 이벤트를 라우팅한다 (`RoutePointerDownEvent`).  
애니메이션 중이거나 뷰포트 밖으로 나간 위젯을 클릭할 때 히트 테스트가 실패하는 경우를 보완한다.

---

## 커서 가시성 관리

```cpp
void FCommonAnalogCursor::RefreshCursorVisibility()
{
    const bool bShowCursor =
        bIsAnalogMovementEnabled          // 아날로그 이동 모드면 커서 표시
        || ActionRouter.ShouldAlwaysShowCursor()
        || ActiveInputMethod == ECommonInputType::MouseAndKeyboard;

    SlateUser->SetCursorVisibility(bShowCursor);
}
```

게임패드 전환 시 커서를 숨기고, 마우스로 전환 시 다시 표시한다.  
매 Tick에서 호출해 멀티플레이어 P2 커서 가시성 상태가 꼬이는 버그를 방어한다.
