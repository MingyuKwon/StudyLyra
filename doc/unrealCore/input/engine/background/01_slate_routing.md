# FSlateApplication — 위젯 라우팅

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Widgets/SViewport.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/Slate/SceneViewport.cpp`

---

`FSlateApplication`은 포커스를 가진 위젯 계층으로 이벤트를 라우팅하는 **중앙 허브**다.  
게임이 입력을 받으려면 `SViewport`가 포커스를 가져야 한다.

InputPreProcessor 단계(위젯 라우팅 이전)는 [../02_preprocessor.md](../02_preprocessor.md) 참고.

---

## ProcessKeyDownEvent 흐름

```cpp
// SlateApplication.cpp:4871
bool FSlateApplication::ProcessKeyDownEvent(const FKeyEvent& InKeyEvent)
{
    // ① InputPreProcessor — ../02_preprocessor.md 참고
    if (InputPreProcessors.HandleKeyDownEvent(*this, InKeyEvent))
        return true;

    // ② 드래그 중 ESC → 드래그 취소
    if (SlateUser->IsDragDropping() && InKeyEvent.GetKey() == EKeys::Escape)
    {
        SlateUser->CancelDragDrop();
        return true;
    }

    // ③ 포커스 경로(FWidgetPath) 조회
    TSharedRef<FWidgetPath> EventPathRef = SlateUser->GetFocusPath();

    // ④ Tunnel: 루트 → 리프, OnPreviewKeyDown 호출
    Reply = FEventRouter::RouteAlongFocusPath(this,
        FEventRouter::FTunnelPolicy(EventPath), InKeyEvent,
        [](const FArrangedWidget& Widget, const FKeyEvent& Event) {
            return Widget.Widget->OnPreviewKeyDown(Widget.Geometry, Event);
        });

    // ⑤ Bubble: 리프 → 루트, OnKeyDown 호출 (Tunnel이 Unhandled일 때만)
    if (!Reply.IsEventHandled())
    {
        Reply = FEventRouter::RouteAlongFocusPath(this,
            FEventRouter::FBubblePolicy(EventPath), InKeyEvent,
            [](const FArrangedWidget& Widget, const FKeyEvent& Event) {
                return Widget.Widget->OnKeyDown(Widget.Geometry, Event);
            });
    }

    // ⑥ 아무도 처리 안 하면 UnhandledKeyDownEventHandler 폴백
    if (!Reply.IsEventHandled() && UnhandledKeyDownEventHandler.IsBound())
        Reply = UnhandledKeyDownEventHandler.Execute(InKeyEvent);

    return Reply.IsEventHandled();
}
```

---

## FWidgetPath — 포커스 경로

키보드 이벤트는 포커스를 가진 단일 위젯이 아니라 **루트까지의 경로 전체**를 대상으로 라우팅된다.

```
FWidgetPath (게임 플레이 중)
  [0] SWindow       ← 루트
  [1] SOverlay
  [2] SViewport     ← 포커스 보유
```

`SlateUser->GetFocusPath()`가 이 배열을 반환한다. 경로가 없으면 Tunnel/Bubble 자체가 실행되지 않는다.

---

## Tunnel → Bubble 두 단계 라우팅

| 단계 | 방향 | 호출 함수 | 우선권 |
|------|------|-----------|--------|
| Tunnel (`FTunnelPolicy`) | 루트 → 리프 (0 → N-1) | `OnPreviewKeyDown()` | 부모 우선 |
| Bubble (`FBubblePolicy`) | 리프 → 루트 (N-1 → 0) | `OnKeyDown()` | 자식 우선 |

```cpp
// FTunnelPolicy: 0부터 증가
void Next() { ++WidgetIndex; }

// FBubblePolicy: N-1부터 감소
void Next() { --WidgetIndex; }
```

### 왜 두 단계로 나뉘어져 있는가

두 요구가 상충하기 때문이다.

```
SWindow [0]
  SDialog [1]
    SButton [2]  ← 포커스
```

- `SDialog`는 Escape로 창을 닫고 싶다 — `SButton`보다 **먼저** 받아야 한다
- `SButton`은 Enter로 클릭을 수행하고 싶다 — `SDialog`가 **가로채면 안 된다**

단일 방향으로는 두 요구를 동시에 만족시킬 수 없다. 그래서 단계를 분리했다.

### 왜 방향이 반대인가

**Tunnel (루트→리프) = 부모 우선권** — 부모가 자식보다 먼저 이벤트를 본다. `Handled()` 반환 시 Bubble 단계 전체가 건너뛰어진다.

```cpp
FReply SDialog::OnPreviewKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Escape)
    {
        CloseDialog();
        return FReply::Handled();  // SButton은 이 이벤트를 보지 못함
    }
    return FReply::Unhandled();
}
```

**Bubble (리프→루트) = 자식 우선권** — 포커스 위젯이 먼저 처리한다. `Unhandled()` 반환 시 부모로 올라간다.

```cpp
FReply SButton::OnKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Enter)
    {
        OnClicked.ExecuteIfBound();
        return FReply::Handled();  // SDialog, SWindow는 이 이벤트를 보지 못함
    }
    return FReply::Unhandled();
}
```

---

## SViewport → FSceneViewport → UGameViewportClient

Bubble 단계가 `SViewport`에 도달하면 게임 엔진으로 이어진다.

```cpp
// SViewport.cpp:286
FReply SViewport::OnKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    return ViewportInterface.Pin()->OnKeyDown(MyGeometry, KeyEvent);
    // ViewportInterface = FSceneViewport
}

// SceneViewport.cpp:1072
FReply FSceneViewport::OnKeyDown(const FGeometry&, const FKeyEvent& InKeyEvent)
{
    KeyStateMap.Add(Key, true);
    ViewportClient->InputKey(...);  // UGameViewportClient
}
```

```
SViewport::OnKeyDown()               ← Slate 위젯
    └─ FSceneViewport::OnKeyDown()   ← ISlateViewport 브릿지
            └─ UGameViewportClient::InputKey()   ← 게임 엔진
```

`FSceneViewport`가 Slate와 게임 엔진 사이의 브릿지 역할을 한다.

---

## 입력 가로채기 — 위젯 라우팅 안에서

위젯 라우팅 레이어 안에서 입력을 차단하는 방법 두 가지.

### 포커스 이동

포커스를 가진 위젯으로만 이벤트가 전달된다. UI 창이 열리면서 포커스가 이동하면 `SViewport`는 자동으로 키보드 입력을 받지 못한다.

```cpp
FSlateApplication::Get().SetKeyboardFocus(MyWidget, EFocusCause::SetDirectly);
```

```
포커스 = SMyUIWidget 일 때:
  Bubble → SMyUIWidget::OnKeyDown() 호출
         ← SViewport::OnKeyDown()는 호출되지 않음
```

마우스 이벤트는 포커스가 아닌 커서 위치 기준으로 라우팅된다.

### FReply::Handled()

같은 포커스 경로 안에서 이벤트 전파를 중단한다.

```cpp
FReply SMyWidget::OnKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Escape)
    {
        CloseUI();
        return FReply::Handled();   // 전파 중단 — 부모 위젯은 이 이벤트를 보지 못함
    }
    return FReply::Unhandled();     // 부모로 계속 전파
}
```

---

## 시나리오별 흐름

| 상황 | 작동하는 레이어 |
|------|----------------|
| 일반 게임 플레이 | Bubble → SViewport → UGameViewportClient |
| Enhanced Input 처리 | Bubble → SViewport → UGameViewportClient → UEnhancedPlayerInput 적재 → PlayerController 틱에서 콜백 |
| 인벤토리 UI 열림 | 포커스가 UI 위젯으로 이동 → SViewport 키보드 차단 |
| 컷신 중 입력 차단 | PreProcessor 등록, 특정 키만 허용 |
| 일시 정지 메뉴 ESC | UI에서 `Handled()` 반환 → 게임으로 전파 안 됨 |

---

## UI vs 게임 입력 분기

물리 입력(키보드/마우스/게임패드) 하나가 들어오면 **항상 Slate가 먼저 받고, 게임은 Slate가 소비하지 않은 입력만 받는다.**  
동시에 두 곳에 가는 게 아니라 순차적이다.

```
[물리 입력]
      │
      ▼
FSlateApplication  ← 모든 입력이 여기 먼저 도착
      │
      ├─ Tunnel → Bubble → 포커스 위젯
      │       │
      │       ├─ Handled()   → 여기서 끝. 게임 경로로 내려가지 않음
      │       │
      │       └─ Unhandled() → SViewport까지 버블링
      │                            └─ FSceneViewport → UGameViewportClient → PlayerInput
      │
```

이 구조는 키보드·마우스·게임패드 모두 동일하게 적용된다.

```
키보드 ESC    → UI가 먼저 받음 → 모달 닫기(Handled)    → 게임으로 전달 안 됨
마우스 클릭   → UI가 먼저 받음 → 버튼 클릭(Handled)    → 게임 월드 클릭 안 됨
게임패드 스틱 → UI가 먼저 받음 → 포커스 이동(Handled)  → 캐릭터 이동 안 됨
WASD 이동     → UI가 먼저 받음 → 처리 안 함(Unhandled) → SViewport → PlayerInput → 이동
```

### CommonUI의 ECommonInputMode

CommonUI는 이 분기를 **더 명시적으로** 제어한다.  
스택 최상위 위젯의 `ECommonInputMode` 설정이 어느 경로를 허용할지 결정한다.

| InputMode | 동작 |
|-----------|------|
| `Menu` | UI 위젯에 포커스. SViewport는 포커스 경로 밖 → 게임 경로 원천 차단 |
| `Game` | SViewport에 포커스. UI 위젯은 포커스 경로 밖 → UI 입력 차단 |
| `All` (GameAndMenu) | Slate 우선 순차 처리. UI가 소비한 입력은 게임 못 받고, UI가 흘린 입력은 게임이 받음 |

`All` 모드는 "둘 다 동시에 받는다"가 아니다.  
**입력마다 UI가 먼저 처리 여부를 결정하고, 소비 안 한 것만 게임으로 내려간다.**

```
[All 모드, 인게임 미니맵 UI 열린 상태]
  미니맵 클릭   → UI Handled()    → 게임 월드 클릭 없음
  WASD          → UI Unhandled()  → PlayerInput → 캐릭터 이동
```

Lyra에서 UI를 열 때 `ELyraWidgetInputMode::Menu`로 전환하는 이유가 이것이다.  
→ [CommonUI 입력 모드 상세](../../../../../plugin/common_ui/02_input_mode.md)
