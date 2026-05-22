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
