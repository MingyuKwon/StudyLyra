# 언리얼이 입력을 받는 원리

> 출처: `C:/UE_5.7/Engine/Source/Runtime/ApplicationCore/Private/Windows/WindowsApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/GameViewportClient.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`

---

## 큰 그림

물리 키보드의 W키를 누르면, 그 정보가 `UPlayerInput`의 `EventAccumulator`에 도달하기까지 **5개 계층**을 거친다.

```
[물리 장치]
    ↓
OS (Windows 메시지 루프)
    ↓
FWindowsApplication   ← 플랫폼 추상화 레이어
    ↓
FSlateApplication     ← UI/입력 중앙 라우터
    ↓
UGameViewportClient   ← 게임 뷰포트 관문
    ↓
APlayerController → UPlayerInput   ← 여기서 EventAccumulator에 쌓임
```

각 계층이 하는 일이 다르다. 하나씩 본다.

---

## 1단계 — OS: 하드웨어 신호 → Windows 메시지

키보드를 누르면 OS가 `WM_KEYDOWN` 메시지를 윈도우 프로시저로 보낸다.

```cpp
// WindowsApplication.cpp:3184
case WM_KEYDOWN:
{
    int32 Win32Key = (int32)wParam;
    bool bIsRepeat = (lParam & 0x40000000) != 0;  // LPARAM 비트 30 = 반복 키 여부

    // VK_CONTROL → VK_LCONTROL/VK_RCONTROL 구분 등 정제
    // ...

    MessageHandler->OnKeyDown(ActualKey, CharCode, bIsRepeat);  // 다음 계층 호출
}
```

이 시점의 키는 아직 Windows Virtual Key Code (`VK_W` 등)다. 언리얼의 `FKey`가 아니다.

---

## 2단계 — FWindowsApplication: VirtualKey → FKey 변환

`FWindowsApplication`이 `IMessageHandler`(= `FSlateApplication`)의 `OnKeyDown`을 호출한다.  
`FSlateApplication::OnKeyDown` 내부에서 변환이 일어난다.

### 왜 UI 프레임워크인 Slate가 입력을 받는가?

직관적으로 이상하게 느껴질 수 있다. 이유는 하나다: **FSlateApplication이 OS 윈도우(HWND)를 소유하고 있기 때문이다.**

OS 입력은 윈도우에 귀속된다. 키를 누르면 포커스를 가진 윈도우로 `WM_KEYDOWN`이 날아오는데, 그 윈도우를 만들고 관리하는 주체가 `FSlateApplication`이다. 윈도우 소유자니까 당연히 입력을 먼저 받는다.

그리고 결정적으로 — **게임 뷰포트 자체가 Slate 위젯이다.**

```
Slate 위젯 트리
  SWindow  (OS 윈도우 — FSlateApplication이 소유)
    └─ SOverlay
          ├─ SViewport  ← 게임 3D 화면이 여기에 렌더링됨
          │    (FSceneViewport = UGameViewportClient의 Slate 측 짝)
          └─ SCanvas    ← HUD, UMG 위젯들
```

`FSlateApplication` 입장에서는 게임 입력이든 UI 입력이든 동일하다 — "현재 포커스를 가진 Slate 위젯으로 이벤트를 라우팅"하면 끝이다.

이 구조 덕분에 UI 창이 열리면 포커스가 UI 위젯으로 이동해서 게임 쪽으로 입력이 자연스럽게 차단된다. 별도의 "입력 잠금" 메커니즘이 필요 없다.

```cpp
// SlateApplication.cpp:4863
bool FSlateApplication::OnKeyDown(const int32 KeyCode, const uint32 CharacterCode, const bool IsRepeat)
{
    // VirtualKeyCode → FKey 변환 (FInputKeyManager가 매핑 테이블 보유)
    FKey const Key = FInputKeyManager::Get().GetKeyFromCodes(KeyCode, CharacterCode);

    FKeyEvent KeyEvent(Key, ModifierKeys, UserIndex, IsRepeat, CharacterCode, KeyCode);
    return ProcessKeyDownEvent(KeyEvent);
}
```

`FInputKeyManager`가 VirtualKey → `FKey` 변환 테이블을 가지고 있다.  
이 변환 이후부터는 플랫폼 독립적인 `FKey`(`EKeys::W`, `EKeys::SpaceBar` 등)로만 처리된다.

---

## 3단계 — FSlateApplication: UI 라우팅 + InputPreProcessor

`FSlateApplication`은 UI 이벤트와 게임 입력 이벤트를 모두 처리하는 **중앙 허브**다.

```
FSlateApplication::ProcessKeyDownEvent()
    ├─ InputPreProcessors.HandleKeyDownEvent()   ← 가로채는 PreProcessor가 있으면 여기서 끝
    └─ 포커스된 Slate 위젯으로 이벤트 전달
            └─ FSceneViewport (게임 화면 위젯) → UGameViewportClient::InputKey()
```

콘솔 창이나 에디터 위젯에 포커스가 있으면 게임 쪽으로 전달되지 않는다.  
**게임이 입력을 받으려면 뷰포트가 포커스를 가져야 한다.**

---

### Slate가 입력을 가로채는 세 가지 메커니즘

Slate 계층에서 입력을 중간에 차단하는 방법은 세 가지다. 방식과 범위가 각각 다르다.

#### 메커니즘 1 — InputPreProcessor (가장 이른 개입)

```cpp
// SlateApplication.h
void RegisterInputPreProcessor(TSharedRef<IInputProcessor> InputProcessor, const int32 Index = INDEX_NONE);
```

`IInputProcessor`를 구현해 `FSlateApplication`에 등록하면, **포커스 위젯 라우팅보다 먼저** 모든 입력을 본다.

```
ProcessKeyDownEvent()
    └─ InputPreProcessors 순회
            ├─ processor->HandleKeyDownEvent() → true 반환 시 여기서 종료  ← 이 이후 위젯 라우팅 없음
            └─ false 반환 시 다음 processor로
```

**Enhanced Input 자체가 이 방식을 사용한다.**  
`UEnhancedInputLocalPlayerSubsystem`가 `IInputProcessor`를 구현하고 스스로 등록한다. 즉, 키 → InputAction 변환은 Slate 위젯 라우팅 이전에 일어난다.

InputPreProcessor의 특징:
- 위젯 포커스와 무관하게 **무조건** 실행된다.
- 여러 개 등록 가능. `Index`로 순서를 지정한다.
- 단일 이벤트를 삼키거나(`true`), 통과시키거나(`false`), 변형할 수 있다.

#### 메커니즘 2 — 위젯 포커스 (가장 자연스러운 차단)

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

#### 메커니즘 3 — FReply::Handled() (위젯 간 전파 제어)

같은 포커스 체인 안에서 부모-자식 위젯이 이벤트를 어떻게 처리할지 결정한다.

```cpp
// 위젯이 이벤트를 처리했고 더 이상 전파하지 않겠다고 선언
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

### 실제 시나리오별 흐름

| 상황 | 어떤 메커니즘이 작동하는가 |
|------|--------------------------|
| 일반 게임 플레이 | 포커스 = SViewport → UGameViewportClient로 전달 |
| 인벤토리 UI 열림 | 포커스가 UI 위젯으로 이동 → SViewport 키보드 차단 (메커니즘 2) |
| 컷신 중 입력 차단 | InputPreProcessor 등록, 특정 키만 허용 (메커니즘 1) |
| Enhanced Input 처리 | UEnhancedInputLocalPlayerSubsystem이 PreProcessor로 등록, 포커스보다 먼저 실행 (메커니즘 1) |
| 일시 정지 메뉴 ESC | UI가 Handled() 반환 → 게임으로 전파 안 됨 (메커니즘 3) |

---

---

## 4단계 — UGameViewportClient: 게임 진입 관문

`FSceneViewport`에서 `UGameViewportClient::InputKey()`가 호출된다.

```cpp
// GameViewportClient.cpp:696
bool UGameViewportClient::InputKey(const FInputKeyEventArgs& InEventArgs)
{
    // 전체화면 토글 키 처리 (Alt+Enter 등)
    if (TryToggleFullscreenOnInputKey(...)) return true;

    // PIE에서 패드를 두 번째 창으로 라우팅 (에디터 전용)
    // ...

    // 개발자 콘솔로 먼저 전달 (~ 키 등)
    bool bResult = ViewportConsole ? ViewportConsole->InputKey(...) : false;

    if (!bResult)
    {
        // 이 입력 장치를 소유한 LocalPlayer 찾기
        ULocalPlayer* TargetPlayer = GEngine->GetLocalPlayerFromInputDevice(this, EventArgs.InputDevice);
        if (TargetPlayer && TargetPlayer->PlayerController)
        {
            bResult = TargetPlayer->PlayerController->InputKey(EventArgs);  // 다음 계층
        }
    }
    return bResult;
}
```

여기서 중요한 일이 두 가지 일어난다:
- **콘솔 우선 처리**: `~` 키로 개발자 콘솔을 여는 것이 게임 입력보다 먼저다.
- **InputDevice → LocalPlayer 매핑**: 스플릿스크린에서 어떤 패드가 어떤 플레이어 것인지 여기서 결정된다.

---

## 5단계 — PlayerController → UPlayerInput: Accumulator에 적재

```cpp
// PlayerController.cpp:2407
bool APlayerController::InputKey(const FInputKeyEventArgs& Params)
{
    // 이 입력이 우리 플레이어 소유 장치에서 온 것인지 확인
    if (bFilterInputByPlatformUser && ...)
        return false;

    if (Params.Key.IsAnalog())
        bResult = PlayerInput->InputKey(Params);  // 아날로그 → PlayerInput으로
    else
        bResult = PlayerInput->InputKey(Params);  // 디지털도 동일
}

// PlayerInput.cpp:278
bool UPlayerInput::InputKey(const FInputKeyEventArgs& Params)
{
    FKeyState& KeyState = KeyStateMap.FindOrAdd(Params.Key);
    KeyState.EventAccumulator[IE_Pressed].Add(++EventCount);  // 여기에 쌓임!
    KeyState.RawValueAccumulator.X += Params.AmountDepressed;
}
```

여기서 "적재"만 하고 아무것도 실행하지 않는다.  
실제 처리는 다음 틱의 `EvaluateKeyMapState()` → `EvaluateInputDelegates()`에서 일어난다.

---

## 전체 흐름 요약

```
[W키 누름]
    │
    ▼  (비동기 — OS 이벤트 발생 시)
WM_KEYDOWN
    → FWindowsApplication::ProcessMessage()
    → FSlateApplication::OnKeyDown()          VirtualKey → FKey 변환
    → FSlateApplication::ProcessKeyDownEvent() InputPreProcessor 확인
    → UGameViewportClient::InputKey()          콘솔 우선 / LocalPlayer 매핑
    → APlayerController::InputKey()           장치 소유권 확인
    → UPlayerInput::InputKey()
    → KeyStateMap["W"].EventAccumulator 적재   ← 여기까지가 "수신"

    │
    ▼  (동기 — 다음 틱)
APlayerController::PlayerTick()
    → ProcessPlayerInput()
    → PlayerInput->ProcessInputStack()
    → EvaluateKeyMapState()                    Accumulator → EventCounts flush
    → EvaluateInputDelegates()                 콜백 실행
    → PostProcessInput()                       Lyra: ProcessAbilityInput
```

---

## 패드 입력은 어떻게 다른가

키보드는 키를 누를 때 OS 이벤트(WM_KEYDOWN)가 발생한다.  
패드는 **폴링(Polling)** 방식으로 처리된다.

```
[매 틱] FPlatformApplicationMisc::PumpMessages()
    → 플랫폼별 패드 상태 조회 (XInput API 등)
    → 버튼 상태 변화가 있으면 FSlateApplication::OnControllerButtonPressed() 호출
    → 스틱 값은 FSlateApplication::OnControllerAnalog() 호출
    → 이후 동일 경로: GameViewportClient → PlayerController → PlayerInput
```

키보드는 이벤트 기반(눌렸을 때만 알림), 패드는 폴링 기반(매 틱 상태 조회)이다.  
하지만 `UPlayerInput::InputKey()`에 도달한 이후는 **완전히 동일한 로직**으로 처리된다.
