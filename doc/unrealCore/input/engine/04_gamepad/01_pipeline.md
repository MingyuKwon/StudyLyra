# 패드 입력 파이프라인

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/InputCore/Classes/InputCoreTypes.h`

---

## 핵심 전제 — 패드도 같은 파이프라인을 쓴다

패드 버튼과 스틱은 키보드 키와 동일하게 `FKey`로 추상화된다.  
`UPlayerInput::InputKey()` → `EventAccumulator` → 매 틱 flush 흐름이 **완전히 동일**하다.

```cpp
// InputCoreTypes.h — 패드 키 목록
FKey Gamepad_FaceButton_Bottom   // Xbox: A, PS: Cross(×)
FKey Gamepad_FaceButton_Right    // Xbox: B, PS: Circle(○)
FKey Gamepad_LeftX               // 왼쪽 스틱 수평축 (-1 ~ 1)
FKey Gamepad_RightY              // 오른쪽 스틱 수직축 (-1 ~ 1)
FKey Gamepad_LeftTriggerAxis     // L2 아날로그 (0 ~ 1)
FKey Gamepad_LeftTrigger         // L2 디지털 (0 or 1) — 같은 하드웨어, 다른 해석
```

---

## FSlateApplication 진입 경로 — 키보드와의 차이

### 폴링 vs 인터럽트

키보드와 패드는 엔진에 입력이 전달되는 방식 자체가 다르다.

**키보드** — OS 인터럽트 기반  
버튼을 누르는 순간 OS가 `WM_KEYDOWN` 메시지를 생성해서 메시지 큐에 밀어넣는다.  
엔진이 폴링하지 않아도 OS가 먼저 알려준다.

**패드(XInput)** — 엔진 폴링 기반  
XInput API 자체가 폴링 방식이다. `XInputGetState()`를 호출해야만 현재 상태를 알 수 있다.  
OS가 버튼 이벤트를 생성하지 않는다.

```
[키보드 A 누름]
    OS WM_KEYDOWN → 메시지 큐 → FWindowsApplication::ProcessMessage()
    → FSlateApplication::OnKeyDown() → ProcessKeyDownEvent()
    ← Tick과 무관하게 즉시 처리

[패드 A 누름]
    (아무것도 안 일어남)
        ↓
    다음 FSlateApplication::Tick()
        PlatformApplication->Tick()
            XInputGetState() 호출 → 이전 프레임 상태와 비교 → 변화 감지
            OnControllerButtonPressed() 합성 이벤트 발생
        → ProcessKeyDownEvent()
    ← 다음 틱에서야 처리
```

패드 버튼을 누른 시점이 아니라 **다음 틱에서야** 엔진이 인지한다.  
`PlatformApplication->Tick()` 내부가 매 틱 `XInputGetState()`를 호출해 직전 프레임 상태와 비교하고, 변화가 있으면 합성 이벤트를 발생시킨다.

### 디지털 버튼 → ProcessKeyDownEvent (키보드와 동일)

```cpp
// SlateApplication.cpp:6560
bool FSlateApplication::OnControllerButtonPressed(FGamepadKeyNames::Type KeyName, ...)
{
    FKey Key(KeyName);
    FKeyEvent KeyEvent(Key, ...);
    return ProcessKeyDownEvent(KeyEvent);  // 키보드와 완전히 동일한 함수
}
```

`FKey` 값만 다를 뿐, 이후 `InputPreProcessor → Tunnel/Bubble → SViewport` 경로는 키보드와 동일하다.

### 아날로그 (스틱, 트리거) → ProcessAnalogInputEvent (별도 경로)

```cpp
// SlateApplication.cpp:6547
bool FSlateApplication::OnControllerAnalog(FGamepadKeyNames::Type KeyName, ..., float AnalogValue)
{
    FAnalogInputEvent AnalogInputEvent(Key, ..., AnalogValue);
    return ProcessAnalogInputEvent(AnalogInputEvent);
}
```

아날로그는 "변화 감지"가 아니라 매 틱 현재 값을 그대로 `OnControllerAnalog()`로 보낸다.

| | 디지털 버튼 | 아날로그 |
|---|---|---|
| **Slate 진입 함수** | `OnControllerButtonPressed()` | `OnControllerAnalog()` |
| **처리 함수** | `ProcessKeyDownEvent()` | `ProcessAnalogInputEvent()` |
| **InputPreProcessor** | `HandleKeyDownEvent()` | `HandleAnalogInputEvent()` |
| **위젯 콜백** | `OnKeyDown()` | `OnAnalogValueChanged()` |
| **Tunnel 단계** | 있음 | 없음 |

---

## 디지털 vs 아날로그

키보드 키는 누르면 1, 놓으면 0이다.  
패드 스틱과 트리거는 **소수점 값**을 매 프레임 보낸다.

```
키보드 A키     → EventAccumulator에 IE_Pressed 이벤트 1개 추가
패드 왼쪽 스틱 → RawValueAccumulator에 (X=-0.73, Y=0.41) 누적 (매 틱)
```

| 입력 종류 | 타입 | 범위 | FKey 예시 |
|----------|------|------|-----------|
| 버튼 | 디지털 | 0 or 1 | `Gamepad_FaceButton_Bottom` |
| 스틱 축 | 아날로그 | -1.0 ~ 1.0 | `Gamepad_LeftX`, `Gamepad_RightY` |
| 트리거 (아날로그) | 아날로그 | 0.0 ~ 1.0 | `Gamepad_LeftTriggerAxis` |
| 트리거 (디지털) | 디지털 | 0 or 1 | `Gamepad_LeftTrigger` |

트리거가 두 FKey로 분리된 이유: 같은 하드웨어를 **조금만 눌러도 반응하는 버튼**으로 쓸 수도 있고, **얼마나 눌렀는지 측정하는 축**으로 쓸 수도 있기 때문이다.
