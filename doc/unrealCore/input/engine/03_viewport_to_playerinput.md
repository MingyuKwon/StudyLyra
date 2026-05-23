# UGameViewportClient → UPlayerInput 적재

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/GameViewportClient.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`

---

Slate의 `SViewport::OnKeyDown()` → `FSceneViewport::OnKeyDown()` → `UGameViewportClient::InputKey()`까지는 [02_slate_routing.md](02_slate_routing.md)에서 다룬다.  
이 문서는 `UGameViewportClient`에서 `UPlayerInput`의 `EventAccumulator`에 적재되기까지를 다룬다.

---

## 전체 흐름

```
UGameViewportClient::InputKey()          ← GameViewportClient.cpp:696
    │
    ├─ TryToggleFullscreenOnInputKey()   ← Alt+Enter 등 처리, true면 이후 없음
    ├─ RemapControllerInput()            ← 컨트롤러 키 리매핑
    ├─ IgnoreInput() 확인                ← true면 콘솔에만 전달하고 종료
    ├─ ViewportConsole->InputKey()       ← 콘솔 입력 우선 처리
    └─ GEngine->GetLocalPlayerFromInputDevice()  ← InputDevice → LocalPlayer 매핑
            └─ PlayerController->InputKey()      ← PlayerController.cpp:2407
                    └─ PlayerInput->InputKey()   ← PlayerInput.cpp:278
                            └─ EventAccumulator 적재
```

---

## UGameViewportClient::InputKey() — 핵심 처리 순서

```cpp
// GameViewportClient.cpp:696
bool UGameViewportClient::InputKey(const FInputKeyEventArgs& InEventArgs)
{
    // 1. Alt+Enter 등 전체화면 전환 — 처리되면 즉시 반환
    if (TryToggleFullscreenOnInputKey(EventArgs.Key, EventArgs.Event))
        return true;

    // 2. 컨트롤러 리매핑 (플랫폼별 버튼 재지정)
    RemapControllerInput(EventArgs);

    // 3. IgnoreInput 플래그 — true면 게임 PC로 전달 안 함
    //    ViewportConsole에는 전달 (콘솔은 항상 작동)
    if (IgnoreInput())
        return ViewportConsole ? ViewportConsole->InputKey(...) : false;

    // 4. 콘솔 우선 처리 (` 키 등)
    bool bResult = ViewportConsole ? ViewportConsole->InputKey(...) : false;

    // 5. 콘솔이 소비 안 했으면 InputDevice → LocalPlayer → PlayerController로 전달
    if (!bResult)
    {
        ULocalPlayer* TargetPlayer = GEngine->GetLocalPlayerFromInputDevice(this, EventArgs.InputDevice);
        if (TargetPlayer && TargetPlayer->PlayerController)
            bResult = TargetPlayer->PlayerController->InputKey(EventArgs);
    }
    return bResult;
}
```

**콘솔 우선**: `ViewportConsole->InputKey()`가 `true`를 반환하면 PlayerController에 도달하지 않는다.  
**LocalPlayer 매핑**: `InputDevice`(패드 인덱스 등)를 기준으로 어느 LocalPlayer에게 보낼지 결정한다. 스플릿스크린에서 패드1/패드2가 각자의 PlayerController로 분기되는 지점이다.

---

## APlayerController::InputKey() — 필터링 후 PlayerInput 위임

```cpp
// PlayerController.cpp:2407
bool APlayerController::InputKey(const FInputKeyEventArgs& Params)
{
    // 플랫폼 유저 필터 — 다른 플레이어의 기기 입력 차단
    if (bFilterInputByPlatformUser &&
        IPlatformInputDeviceMapper::Get().GetUserForInputDevice(Params.InputDevice) != GetPlatformUserId())
        return false;

    // XR 핸들러 우선 확인 (VR 컨트롤러 등)
    if (GEngine->XRSystem.IsValid())
    {
        IXRInput* XRInput = GEngine->XRSystem->GetXRInput();
        if (XRInput && XRInput->HandleInputKey(...))
            return true;
    }

    // PlayerInput에 위임 — 실제 적재 발생
    if (PlayerInput)
        bResult = PlayerInput->InputKey(Params);

    return bResult;
}
```

PlayerController는 직접 처리하지 않는다. 필터링만 하고 `PlayerInput`에 위임한다.

---

## UPlayerInput::InputKey() — EventAccumulator 적재

```cpp
// PlayerInput.cpp:278
bool UPlayerInput::InputKey(const FInputKeyEventArgs& Params)
{
    FKeyState& KeyState = KeyStateMap.FindOrAdd(Params.Key);

    switch (Params.Event)
    {
    case IE_Pressed:
    case IE_Repeat:
        KeyState.RawValueAccumulator.X = Params.AmountDepressed;
        KeyState.EventAccumulator[Params.Event].Add(++EventCount);  // 누적
        break;
    case IE_Released:
        KeyState.RawValueAccumulator.X = 0.f;
        KeyState.EventAccumulator[IE_Released].Add(++EventCount);
        break;
    }
}
```

이 시점에서는 아무 콜백도 실행되지 않는다. `EventAccumulator`에 이벤트 번호(`EventCount`)를 추가할 뿐이다.  
실제 처리는 다음 틱의 `EvaluateKeyMapState()`에서 Accumulator를 flush할 때 일어난다. → [04_tick_pipeline.md](04_tick_pipeline.md)

---

## IgnoreInput 플래그

`UGameViewportClient::SetIgnoreInput(true)`로 세팅하면 `IgnoreInput()`이 `true`를 반환한다.  
콘솔 입력은 여전히 통과하지만 게임 PlayerController로의 전달이 차단된다.  
로딩 화면, 컷신 등에서 게임 입력을 막는 방법 중 하나다.

InputPreProcessor를 쓴 차단 방식과의 차이:

| | IgnoreInput | InputPreProcessor (true 반환) |
|---|---|---|
| **차단 위치** | UGameViewportClient | FSlateApplication |
| **콘솔 통과** | 통과함 | 막힘 |
| **UI 위젯** | Slate 라우팅은 이미 끝난 뒤 — UI는 정상 작동 | Tunnel/Bubble 전에 차단 — UI도 막힘 |
