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

```
[키보드]  누름 → OS WM_KEYDOWN → ProcessKeyDownEvent()        (Tick과 무관, 즉시)
[패드]    누름 → (침묵) → 다음 Tick → PlatformApplication->Tick()
                              → XInputGetState() → 변화 감지
                              → OnControllerButtonPressed() → ProcessKeyDownEvent()
```

키보드는 OS가 이벤트를 밀어주고, 패드는 엔진이 매 틱 직접 당겨온다.  
패드 버튼을 누른 시점이 아니라 **다음 틱에서야** 엔진이 인지한다.

**XInput** — Microsoft의 Windows 게임패드 입력 API. `XInputGetState()` 한 번 호출로 버튼·스틱·트리거 전부를 반환한다. OS 이벤트가 없으니 매 틱 직접 호출해서 이전 값과 비교하는 방식이다.

플랫폼별로 내부 구현만 다르고 이후 경로는 동일하다.

```
FSlateApplication::Tick() → PlatformApplication->Tick()
    [Windows/Xbox]  XInputGetState() 폴링
    [PlayStation]   Sony SDK 폴링
    [Switch]        Nintendo SDK 폴링
    → OnControllerButtonPressed() / OnControllerAnalog()  ← 여기서부터 동일
```

### 디지털 vs 아날로그 처리 경로

변화 감지 후 디지털/아날로그 여부에 따라 분기된다.

| | 디지털 버튼 | 아날로그 |
|---|---|---|
| **감지 방식** | 이전 프레임과 비교, 변화 시만 발생 | 매 틱 현재 값 그대로 전송 |
| **Slate 진입** | `OnControllerButtonPressed()` | `OnControllerAnalog()` |
| **처리 함수** | `ProcessKeyDownEvent()` — 키보드와 동일 | `ProcessAnalogInputEvent()` — 별도 |
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
