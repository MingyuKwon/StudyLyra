# FSlateApplication — UI 라우팅 + 입력 가로채기

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Widgets/SViewport.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/Slate/SceneViewport.cpp`

---

`FSlateApplication`은 UI 이벤트와 게임 입력 이벤트를 모두 처리하는 **중앙 허브**다.

콘솔 창이나 에디터 위젯에 포커스가 있으면 게임 쪽으로 전달되지 않는다.  
**게임이 입력을 받으려면 뷰포트가 포커스를 가져야 한다.**

---

## InputPreProcessor vs Tunnel/Bubble — 두 레이어의 차이

`ProcessKeyDownEvent` 안에는 성격이 다른 두 레이어가 존재한다.

| | 질문 | 대상 |
|---|---|---|
| **InputPreProcessor** | "이 입력이 위젯 시스템에 들어가야 하는가?" | 애플리케이션 레벨 |
| **Tunnel/Bubble** | "위젯 계층 중 누가 이 입력을 처리하는가?" | 위젯 레벨 |

```
ProcessKeyDownEvent()
    ├─ ① InputPreProcessors   ← 위젯 시스템 진입 여부를 결정하는 게이트
    │        true  반환 → 위젯 라우팅 전체 생략
    │        false 반환 → 아래로 계속
    │
    └─ ② Tunnel/Bubble 라우팅  ← 어느 위젯이 처리할지 결정
```

### 왜 Enhanced Input이 PreProcessor인가

`UEnhancedInputLocalPlayerSubsystem`은 UI 위젯이 아니다. 게임 입력을 변환하는 레이어다.  
PreProcessor로 등록하는 이유는 두 가지다.

**포커스와 무관하게 항상 실행되어야 한다.**  
Tunnel/Bubble은 포커스 경로 위젯에만 전달된다. UI가 열려서 포커스가 `SViewport`를 벗어나도, Enhanced Input은 모든 키를 계속 받아야 한다.

**결과물이 위젯이 아닌 게임 코드로 간다.**  
W키 → `InputAction "Move"` 변환 → `UEnhancedInputComponent` 콜백 호출. Slate 위젯과 무관한 경로다.

**`false`를 반환해 위젯 라우팅도 계속 진행한다.**  
Enhanced Input은 키를 처리한 뒤 `false`를 반환한다. 덕분에 같은 키가 Enhanced Input 변환과 Bubble 라우팅을 동시에 거친다.

---

## ProcessKeyDownEvent 내부 흐름

```cpp
// SlateApplication.cpp:4871
bool FSlateApplication::ProcessKeyDownEvent(const FKeyEvent& InKeyEvent)
{
    // ① PreProcessor 선처리 — 포커스/위젯과 무관하게 먼저 실행
    if (InputPreProcessors.HandleKeyDownEvent(*this, InKeyEvent))
        return true;  // 여기서 종료, 아래 위젯 라우팅 없음

    // ② 드래그 중 ESC → 드래그 취소 (특수 처리)
    if (SlateUser->IsDragDropping() && InKeyEvent.GetKey() == EKeys::Escape)
    {
        SlateUser->CancelDragDrop();
        return true;
    }

    // ③ 포커스 경로(FWidgetPath) 조회
    TSharedRef<FWidgetPath> EventPathRef = SlateUser->GetFocusPath();

    // ④ Tunnel 단계: 루트 → 리프 방향으로 OnPreviewKeyDown 호출
    Reply = FEventRouter::RouteAlongFocusPath(this,
        FEventRouter::FTunnelPolicy(EventPath), InKeyEvent,
        [](const FArrangedWidget& Widget, const FKeyEvent& Event) {
            return Widget.Widget->OnPreviewKeyDown(Widget.Geometry, Event);
        });

    // ⑤ Bubble 단계: 리프 → 루트 방향으로 OnKeyDown 호출 (Tunnel이 Unhandled일 때만)
    if (!Reply.IsEventHandled())
    {
        Reply = FEventRouter::RouteAlongFocusPath(this,
            FEventRouter::FBubblePolicy(EventPath), InKeyEvent,
            [](const FArrangedWidget& Widget, const FKeyEvent& Event) {
                return Widget.Widget->OnKeyDown(Widget.Geometry, Event);
            });
    }

    // ⑥ 아무도 처리 안 했으면 UnhandledKeyDownEventHandler 폴백
    if (!Reply.IsEventHandled() && UnhandledKeyDownEventHandler.IsBound())
        Reply = UnhandledKeyDownEventHandler.Execute(InKeyEvent);

    return Reply.IsEventHandled();
}
```

---

## FWidgetPath — 포커스 경로란 무엇인가

키보드 이벤트는 "포커스를 가진 단일 위젯"이 아니라 **루트까지의 경로 전체**를 대상으로 라우팅된다.

```
FWidgetPath (포커스 경로 예시 — 게임 플레이 중)
  [0] SWindow          ← 루트 (OS 윈도우)
  [1] SOverlay
  [2] SViewport        ← 게임 뷰포트 위젯 (포커스 보유)
```

`SlateUser->GetFocusPath()`가 이 배열을 반환한다.  
이 경로가 있어야 Tunnel/Bubble 라우팅이 가능하다.

---

## Tunnel → Bubble 두 단계 라우팅

Slate의 키보드 이벤트는 항상 두 단계로 라우팅된다.

| 단계 | 방향 | 호출 함수 | 우선권 |
|------|------|-----------|--------|
| Tunnel (`FTunnelPolicy`) | 루트 → 리프 (index 0 → N-1) | `OnPreviewKeyDown()` | 부모 우선 |
| Bubble (`FBubblePolicy`) | 리프 → 루트 (index N-1 → 0) | `OnKeyDown()` | 자식 우선 |

```cpp
// FTunnelPolicy — WidgetIndex를 0부터 증가
bool ShouldKeepGoing() const { return WidgetIndex < RoutingPath.Widgets.Num(); }
void Next() { ++WidgetIndex; }

// FBubblePolicy — WidgetIndex를 N-1부터 감소
bool ShouldKeepGoing() const { return WidgetIndex >= 0; }
void Next() { --WidgetIndex; }
```

Tunnel 단계에서 `OnPreviewKeyDown()`이 `Handled()`를 반환하면 Bubble 단계 자체가 건너뛰어진다.  
Bubble 단계에서 어떤 위젯이 `Handled()`를 반환하면 그 위젯에서 전파가 멈춘다.

---

### 왜 두 단계로 나뉘어져 있는가

두 단계는 **"누가 먼저 처리할 권한을 갖는가"** 문제를 해결���기 위해 존재한다.

이런 위젯 트리가 있다고 하자.

```
SWindow [0]
  SDialog [1]
    SButton [2]  ← 포커스
```

이 구조에서 상충되는 두 요구가 생긴다.

- **부모가 먼저 처리해야 하는 경우**: `SDialog`가 Escape로 창을 닫아야 한다. `SButton`이 먼저 받으면 안 된다.
- **자식이 먼저 처리해야 하는 경우**: `SButton`이 Enter로 클릭 동작을 수행한다. `SDialog`가 가로채면 안 된다.

이 두 요구를 단일 방향으로는 동시에 만족시킬 수 없다. 그래서 단계를 분리한 것이다.

---

### 왜 방향이 반대인가

**Tunnel (루트→리프) = 부모 우선권**

부모가 자식보다 먼저 이벤트를 본다. 필요하면 `Handled()`로 자식에게 도달하기 전에 차단할 수 있다.

```cpp
// SDialog가 Escape를 Tunnel에서 가로채는 예시
FReply SDialog::OnPreviewKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Escape)
    {
        CloseDialog();
        return FReply::Handled();  // Bubble 단��� 자체가 실행되지 않음 — SButton은 보지 못함
    }
    return FReply::Unhandled();
}
```

**Bubble (리프→루트) = 자식 우선권**

포커스를 가진 가장 구체적인 위젯이 먼저 처리한다. 처리 못하면 부모로 올라간다.

```cpp
// SButton이 Enter를 Bubble에서 먼저 처리하는 예시
FReply SButton::OnKeyDown(const FGeometry&, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Enter)
    {
        OnClicked.ExecuteIfBound();
        return FReply::Handled();  // SDialog, SWindow는 이 이벤트를 보지 못함
    }
    return FReply::Unhandled();   // 처리 못하면 SDialog로 올라감
}
```

**방향이 반대인 이유는 두 단계가 서로 반대 우선권을 구현하기 때문이다.**  
Tunnel이 루트→리프여야 부모가 먼저 개입할 수 있고, Bubble이 리프→루트여야 자식이 먼저 처리할 수 있다.

---

### 두 단계가 커버하는 시나리오

| 시나리오 | 처리 단계 |
|----------|----------|
| 부모가 특정 키를 자식보다 먼저 가로채야 할 때 | Tunnel — `OnPreviewKeyDown`에서 `Handled()` |
| 포커스 위젯이 이벤트를 직접 처리할 때 | Bubble — `OnKeyDown`에서 `Handled()` |
| 자식이 처리 못한 이벤트를 부모가 받아야 할 때 | Bubble — 자식이 `Unhandled()` → 부모로 올라감 |
| 아무도 처리 못한 이벤트 | `UnhandledKeyDownEventHandler` 폴백 |

---

## SViewport → FSceneViewport → UGameViewportClient 연결

Bubble 단계가 `SViewport`에 도달하면 다음 체인으로 이어진다.

```cpp
// SViewport.cpp:286
FReply SViewport::OnKeyDown(const FGeometry& MyGeometry, const FKeyEvent& KeyEvent)
{
    // ViewportInterface = FSceneViewport (ISlateViewport 구현체)
    return ViewportInterface.Pin()->OnKeyDown(MyGeometry, KeyEvent);
}

// SceneViewport.cpp:1072
FReply FSceneViewport::OnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
    CurrentReplyState = FReply::Handled();
    FKey Key = InKeyEvent.GetKey();
    if (Key.IsValid())
    {
        KeyStateMap.Add(Key, true);  // FSceneViewport 자체 KeyState 갱신
        if (ViewportClient && GetSizeXY() != FIntPoint::ZeroValue)
        {
            FScopedConditionalWorldSwitcher WorldSwitcher(ViewportClient);
            // ViewportClient = UGameViewportClient
            if (!ViewportClient->InputKey(FInputKeyEventArgs(this, InKeyEvent.GetInputDeviceId(),
                                          Key, InKeyEvent.IsRepeat() ? IE_Repeat : IE_Pressed, ...)))
            {
                CurrentReplyState = FReply::Unhandled();
            }
        }
    }
    return CurrentReplyState;
}
```

`FSceneViewport`는 `ISlateViewport`를 구현한 **Slate ↔ 게임 엔진 브릿지**다.  
`SViewport`(Slate 위젯)가 `FSceneViewport`(인터페이스 구현체)를 통해 `UGameViewportClient`를 호출하는 2단 간접 구조다.

```
SViewport::OnKeyDown()               ← Slate 위젯 (UI 레이어)
    └─ FSceneViewport::OnKeyDown()   ← ISlateViewport 브릿지 (Slate ↔ 엔진)
            └─ UGameViewportClient::InputKey()   ← 게임 엔진 레이어
```

---

## Slate가 입력을 가로채는 세 가지 메커니즘

Slate 계층에서 입력을 중간에 차단하는 방법은 세 가지다. 방식과 범위가 각각 다르다.

### 메커니즘 1 — InputPreProcessor (가장 이른 개입)

```cpp
// SlateApplication.h
void RegisterInputPreProcessor(TSharedRef<IInputProcessor> InputProcessor, const int32 Index = INDEX_NONE);
```

`IInputProcessor`를 구현해 `FSlateApplication`에 등록하면, **포커스 위젯 라우팅보다 먼저** 모든 입력을 본다.

```
ProcessKeyDownEvent()
    └─ InputPreProcessors 순회
            ├─ processor->HandleKeyDownEvent() → true 반환 시 여기서 종료
            └─ false 반환 시 다음 processor로
```

**Enhanced Input 자체가 이 방식을 사용한다.**  
`UEnhancedInputLocalPlayerSubsystem`가 `IInputProcessor`를 구현하고 스스로 등록한다. 즉, 키 → InputAction 변환은 Slate 위젯 라우팅 이전에 일어난다.

InputPreProcessor의 특징:
- 위젯 포커스와 무관하게 **무조건** 실행된다.
- 여러 개 등록 가능. `Index`로 순서를 지정한다.
- 단일 이벤트를 삼키거나(`true`), 통과시키거나(`false`), 변형할 수 있다.

### 메커니즘 2 — 위젯 포커스 (가장 자연스러운 차단)

Slate는 현재 포커스를 가진 위젯으로만 키보드 이벤트를 보낸다.  
UI 창이 열리면서 포커스가 그 UI 위젯으로 이동하면, `SViewport`(게임 뷰포트)는 자동으로 키보드 입력을 받지 못한다. 별도의 "게임 입력 잠금" 코드가 필요 없다.

```cpp
// 포커스 이동 — UI가 열릴 때 내부적으로 이런 일이 일어남
FSlateApplication::Get().SetKeyboardFocus(MyWidget, EFocusCause::SetDirectly);
```

포커스 이동만으로 게임 입력이 차단되는 이유:

```
ProcessKeyDownEvent()
    └─ GetKeyboardFocusedWidget() 조회
            └─ SMyUIWidget이 포커스 보유
                    └─ SMyUIWidget::OnKeyDown() 호출
                    ← SViewport::OnKeyDown()는 호출되지 않음
```

마우스 이벤트는 포커스가 아닌 **커서 위치**를 기준으로 라우팅된다. 위젯 위에 마우스를 올리면 그 위젯이 받는다.

### 메커니즘 3 — FReply::Handled() (위젯 간 전파 제어)

같은 포커스 체인 안에서 부모-자식 위젯이 이벤트를 어떻게 처리할지 결정한다.

```cpp
FReply SMyWidget::OnKeyDown(const FGeometry& Geometry, const FKeyEvent& KeyEvent)
{
    if (KeyEvent.GetKey() == EKeys::Escape)
    {
        CloseUI();
        return FReply::Handled();    // 전파 중단
    }
    return FReply::Unhandled();      // 부모 위젯으로 전파 계속
}
```

`Handled()`를 반환한 위젯에서 라우팅이 멈춘다. `Unhandled()`를 반환하면 Slate가 부모 위젯으로 올라가며 재시도한다.

---

## 실제 시나리오별 흐름

| 상황 | 어떤 메커니즘이 작동하는가 |
|------|--------------------------|
| 일반 게임 플레이 | 포커스 = SViewport → UGameViewportClient로 전달 |
| 인벤토리 UI 열림 | 포커스가 UI 위젯으로 이동 → SViewport 키보드 차단 (메커니즘 2) |
| 컷신 중 입력 차단 | InputPreProcessor 등록, 특정 키만 허용 (메커니즘 1) |
| Enhanced Input 처리 | UEnhancedInputLocalPlayerSubsystem이 PreProcessor로 등록, 포커스보다 먼저 실행 (메커니즘 1) |
| 일시 정지 메뉴 ESC | UI가 Handled() 반환 → 게임으로 전파 안 됨 (메커니즘 3) |
