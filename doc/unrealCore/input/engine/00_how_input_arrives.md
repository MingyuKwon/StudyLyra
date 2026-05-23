# 언리얼이 입력을 받는 원리 — 개요

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

각 계층의 상세 흐름은 아래 두 문서에서 다룬다.

| 문서 | 내용 |
|------|------|
| [00_os_to_playerinput.md](00_os_to_playerinput.md) | OS → FWindowsApplication → UGameViewportClient → PlayerInput 수신 경로, 패드 vs 키보드 차이 |
| [00_slate_routing.md](00_slate_routing.md) | FSlateApplication 내부 — ProcessKeyDownEvent, FWidgetPath, Tunnel/Bubble 라우팅, 가로채기 3메커니즘 |

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
