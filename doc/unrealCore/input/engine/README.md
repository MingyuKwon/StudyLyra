# 엔진 입력 파이프라인

키보드의 W키를 누르면 `UPlayerInput`의 `EventAccumulator`에 적재되기까지 5개 계층을 거친다.

```
[물리 장치]
    ↓
OS                      WM_KEYDOWN 발생
    ↓
FWindowsApplication     VirtualKey → FKey 변환 후 FSlateApplication에 전달
    ↓
FSlateApplication       InputPreProcessor → 위젯 라우팅(Tunnel/Bubble) → SViewport
    ↓
UGameViewportClient     콘솔 우선 처리, InputDevice → LocalPlayer 매핑
    ↓
APlayerController
    ↓
UPlayerInput            EventAccumulator에 적재 (처리는 다음 틱)
```

**왜 Slate가 입력을 먼저 받는가**: FSlateApplication이 OS 윈도우(HWND)를 소유하기 때문이다. 게임 뷰포트(`SViewport`)도 Slate 위젯이므로, Slate 입장에서는 UI 입력과 게임 입력을 동일하게 라우팅한다.

**키보드 vs 패드**: 키보드는 이벤트 기반(WM_KEYDOWN), 패드는 폴링 기반(매 틱 XInput 조회). `UPlayerInput::InputKey()` 이후는 동일한 로직.

---

## 전체 흐름

```
[W키 누름]  (비동기 — OS 이벤트)
    → FWindowsApplication::ProcessMessage()
    → FSlateApplication::OnKeyDown()           VirtualKey → FKey
    → FSlateApplication::ProcessKeyDownEvent() InputPreProcessor → Tunnel/Bubble
    → UGameViewportClient::InputKey()          콘솔 우선 / LocalPlayer 매핑
    → APlayerController::InputKey()
    → UPlayerInput::InputKey()
    → EventAccumulator 적재

[다음 틱]  (동기)
    → APlayerController::PlayerTick()
    → PlayerInput->ProcessInputStack()
    → EvaluateKeyMapState()    Accumulator → EventCounts flush
    → EvaluateInputDelegates() 콜백 실행
    → PostProcessInput()       Lyra: ProcessAbilityInput
```

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. InputPreProcessor](01_input_preprocessor.md) | 위젯 라우팅 이전 단계 — IInputProcessor 인터페이스, Enhanced Input이 여기 속하는 이유 |
| [02. FSlateApplication 위젯 라우팅](02_slate_routing.md) | FWidgetPath, Tunnel/Bubble 두 단계(설계 이유 포함), SViewport→FSceneViewport 브릿지, 포커스/FReply 가로채기 |
| [03. 틱 처리 파이프라인](03_tick_pipeline.md) | PlayerController 틱 → ProcessInputStack, Accumulator 패턴, bDown 홀드 유지 원리, BuildInputStack 우선순위 |
| [04. Enhanced Input](04_enhanced_input.md) | Subsystem vs Component 역할 분리, BindAction 오버로드 3종, FInputActionValue vs FInputActionInstance |
| [05. 게임패드 입력](05_gamepad.md) | 아날로그 vs 디지털, 데드존(InputModifier), 진동/햅틱, DualSense 어댑티브 트리거 |
