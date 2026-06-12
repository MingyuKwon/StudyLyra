# 01. FAnalogCursor — 기반 구현

> 소스: `Engine/Source/Runtime/Slate/Private/Framework/Application/AnalogCursor.cpp`

---

## 역할

게임패드 아날로그 스틱 입력을 **마우스 커서 이동**으로 변환하는 Slate 레이어의 입력 전처리기다.  
`IInputProcessor` 인터페이스를 구현하여 SlateApplication의 입력 파이프라인 **최상단**에 등록된다.  
실제 마우스 하드웨어가 없어도 게임패드로 커서를 제어할 수 있게 해준다.

---

## 동작 모드

```cpp
namespace AnalogCursorMode
{
    enum Type
    {
        Accelerated,  // 스틱 기울기로 가속 → 관성 있는 움직임
        Direct,       // 스틱 기울기 × MaxSpeed → 즉각 반응
    };
}
```

`Accelerated` 모드: 큐빅 가속 곡선(`AdjAnalogVals³ × Acceleration`) 적용, 방향 전환 시 속도 즉시 반전  
`Direct` 모드: `CurrentSpeed = AnalogValue × MaxSpeed`, 가속 없음

---

## 핵심 파라미터

| 필드 | 기본값 | 역할 |
|------|--------|------|
| `Acceleration` | 1000.0f | 가속도 배율 |
| `MaxSpeed` | 1500.0f | 최대 커서 속도 (px/s) |
| `StickySlowdown` | 0.5f | 인터랙터블 위젯 위에서 속도 배율 |
| `DeadZone` | 0.1f | 이 값 이하의 스틱 입력은 무시 |

---

## Tick 흐름

```
FAnalogCursor::Tick()
  └── CalculateTickedCursorPosition()
        ├── 데드존 보정: (|값| - DeadZone) / (1 - DeadZone)
        ├── 위젯 히트 테스트: LocateWindowUnderMouse()
        │     └── IsInteractable() → StickySlowdown 적용
        ├── 가속/Direct 계산 → CurrentSpeed
        └── NewPosition = OldPos + CurrentSpeed × DeltaTime × SpeedMult
  └── UpdateCursorPosition()
        └── SlateUser->SetCursorPosition() + ProcessMouseMoveEvent()
```

서브픽셀 오프셋(`CurrentOffset`)을 매 프레임 보존해 픽셀 단위 이동에서 발생하는 정밀도 손실을 보정한다.

---

## HandleKeyDownEvent — 소비 정책

```cpp
bool FAnalogCursor::HandleKeyDownEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent)
{
    if (IsRelevantInput(InKeyEvent))
    {
        FKey Key = InKeyEvent.GetKey();

        // 왼쪽 스틱 디지털 이벤트는 소비 (커서 이동용이므로 하위로 전달하지 않음)
        if (Key == EKeys::Gamepad_LeftStick_Right ||
            Key == EKeys::Gamepad_LeftStick_Left  ||
            Key == EKeys::Gamepad_LeftStick_Up    ||
            Key == EKeys::Gamepad_LeftStick_Down)
        {
            return true;  // consumed
        }

        // A/Cross 버튼 → 좌클릭 변환
        if (Key == EKeys::Virtual_Gamepad_Accept.GetVirtualKey())
        {
            // FPointerEvent(LeftMouseButton) 생성 → ProcessMouseButtonDownEvent()
            return SlateApp.ProcessMouseButtonDownEvent(...);
        }
    }
    return false;  // 그 외 키(D-Pad 등)는 소비하지 않음
}
```

`Gamepad_LeftStick_*` 이벤트를 소비한다는 점이 중요하다.  
이 이벤트들은 Slate 네비게이션 시스템의 `KeyEventRules`에도 등록되어 있지 않으므로,  
소비 여부와 무관하게 네비게이션을 발생시키지 않는다.  
→ 왼쪽 스틱이 포커스 네비게이션을 일으키는 경로는 **디지털 이벤트가 아닌 analog axis 이벤트**다.

---

## Virtual_Gamepad_Accept

`HandleKeyDownEvent` / `HandleKeyUpEvent` 에서 `EKeys::Virtual_Gamepad_Accept` 를 감지해  
**좌클릭 FPointerEvent** 로 변환하여 `SlateApp.ProcessMouseButtonDownEvent()` 에 전달한다.  
게임패드의 A/Cross 버튼이 UI 클릭으로 동작하는 근거다.
