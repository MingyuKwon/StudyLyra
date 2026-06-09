# 07. AnalogCursor / CommonAnalogCursor

> 소스 경로  
> - `Engine/Source/Runtime/Slate/Public/Framework/Application/AnalogCursor.h`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/AnalogCursor.cpp`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Public/Input/CommonAnalogCursor.h`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/Input/CommonAnalogCursor.cpp`

---

## 1. FAnalogCursor — 기반 개념

### 역할

게임패드 아날로그 스틱 입력을 **마우스 커서 이동**으로 변환하는 Slate 레이어의 입력 전처리기다.  
`IInputProcessor` 인터페이스를 구현하여 SlateApplication의 입력 파이프라인 **최상단**에 등록된다.  
실제 마우스 하드웨어가 없어도 게임패드로 커서를 제어할 수 있게 해준다.

### 클래스 계층

```
IInputProcessor
└── FAnalogCursor          ← Slate 기본 구현 (Runtime/Slate)
    └── FCommonAnalogCursor ← CommonUI 확장 (CommonUI Plugin)
```

### 동작 모드

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

### 핵심 파라미터

| 필드 | 기본값 | 역할 |
|------|--------|------|
| `Acceleration` | 1000.0f | 가속도 배율 |
| `MaxSpeed` | 1500.0f | 최대 커서 속도 (px/s) |
| `StickySlowdown` | 0.5f | 인터랙터블 위젯 위에서 속도 배율 |
| `DeadZone` | 0.1f | 이 값 이하의 스틱 입력은 무시 |

### Tick 흐름

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

### Virtual_Gamepad_Accept

`HandleKeyDownEvent` / `HandleKeyUpEvent` 에서 `EKeys::Virtual_Gamepad_Accept` 를 감지해  
**좌클릭 FPointerEvent** 로 변환하여 `SlateApp.ProcessMouseButtonDownEvent()` 에 전달한다.  
게임패드의 A/Cross 버튼이 UI 클릭으로 동작하는 근거다.

---

## 2. FCommonAnalogCursor — CommonUI 확장

### 추가된 핵심 아이디어

| 기존 FAnalogCursor | FCommonAnalogCursor |
|-------------------|---------------------|
| 스틱 → 커서 이동 (항상) | **포커스 연동 모드** (기본) vs 아날로그 이동 모드 |
| 커서 항상 표시 | 게임패드 사용 시 커서 숨김 |
| 입력 항상 처리 | 게임 뷰포트가 포커스 경로에 있을 때만 처리 |
| 오른쪽 스틱 미사용 | 오른쪽 스틱 → 스크롤 위젯 ScrollWheel 이벤트 |

### 생성 및 초기화

```cpp
// UCommonUIActionRouterBase가 소유 - 플레이어 1명당 1개
TSharedRef<FCommonAnalogCursor> Cursor =
    FCommonAnalogCursor::CreateAnalogCursor(ActionRouter);

void FCommonAnalogCursor::Initialize()
{
    RefreshCursorSettings();  // UCommonUIInputSettings에서 파라미터 로드
    // UCommonInputSubsystem::OnInputMethodChangedNative 구독
    InputSubsystem.OnInputMethodChangedNative.AddSP(
        this, &FCommonAnalogCursor::HandleInputMethodChanged);
}
```

`ActionRouter`를 멤버 참조로 보관 (`const UCommonUIActionRouterBase& ActionRouter`).  
UObject인 ActionRouter가 먼저 소멸하면 안 되기 때문에, `FCommonAnalogCursor`는 ActionRouter의 수명에 종속된다.

### 두 가지 동작 모드

#### 모드 1: 포커스 연동 모드 (기본, `bIsAnalogMovementEnabled == false`)

게임패드 사용 중(`IsUsingGamepad()`)이고 `ShouldLinkCursorToGamepadFocus()` 설정이 켜져 있을 때 활성화된다.

```
Tick()
  └── 현재 포커스된 위젯 탐색
        ├── ListView면 선택된 Row 위젯으로 대상 변경
        └── CursorTarget->GetTickSpaceGeometry()
              └── AbsoluteWidgetCenter = Geometry.GetAbsolutePositionAtCoordinates(0.5, 0.5)
                    └── SlateUser->SetCursorPosition(AbsoluteWidgetCenter)
```

커서가 **보이지 않는 채로 포커스 위젯 중앙**에 자동 배치된다.  
가상 Accept(A 버튼) 클릭 시 커서가 정확히 해당 위젯 위에 있으므로 히트 테스트가 성공한다.

포커스 변경이나 위젯 이동(`GetAccumulatedRenderTransform()` 변화)이 감지될 때만 커서를 이동시켜 불필요한 이벤트 발생을 막는다.

#### 모드 2: 아날로그 이동 모드 (`bIsAnalogMovementEnabled == true`)

`FAnalogCursor::CalculateTickedCursorPosition()` 을 그대로 호출해 스틱으로 커서를 직접 이동시킨다.  
개발 빌드(`!UE_BUILD_SHIPPING`)에서 **L/R 숄더 + L/R 트리거 동시 누름**으로 토글된다.

### 입력 처리 조건 — IsRelevantInput

```cpp
// 키 이벤트
bool FCommonAnalogCursor::IsRelevantInput(const FKeyEvent& KeyEvent) const
{
    return IsUsingGamepad()                          // 게임패드 입력 장치일 때
        && FAnalogCursor::IsRelevantInput(KeyEvent)  // 올바른 유저 인덱스일 때
        && (IsGameViewportInFocusPathWithoutCapture()
            || (KeyEvent.GetKey() == EKeys::Virtual_Gamepad_Accept && CanReleaseMouseCapture()));
}
```

`IsGameViewportInFocusPathWithoutCapture()` 조건:
- 게임 뷰포트가 포커스 경로에 포함되어 있어야 함 (다른 창이 활성화면 무시)
- 단, 뷰포트가 커서 캡처(마우스 캡처)를 독점하고 있으면 처리하지 않음 → 인게임 플레이 중 UI가 입력을 가로채지 않음

### 오른쪽 스틱 스크롤

```
Tick() (게임패드 + 뷰포트 포커스)
  └── bShouldHandleRightAnalog && TimeUntilScrollUpdate <= 0
        └── ActionRouter.GatherActiveAnalogScrollRecipients()
              └── 등록된 ScrollBox/ListView/ScrollBar 마다
                    ├── DetermineScrollOrientation() → 수직/수평 판단
                    ├── ScrollAmount = (|value| - deadzone) / (1 - deadzone) × multiplier
                    └── SlateApp.ProcessMouseWheelOrGestureEvent(MouseEvent)
```

`AnalogScrollUpdatePeriod = 0.1f` 주기로만 스크롤 이벤트를 발생시켜 과도한 이벤트 발사를 막는다.  
스크롤 위젯은 `UCommonUIActionRouterBase::GatherActiveAnalogScrollRecipients()`를 통해 수집된다.

### Virtual Accept 처리 확장

```cpp
bool FCommonAnalogCursor::HandleKeyDownEvent(...)
{
    // 1순위: ActionRouter에 바인딩된 UIAction이 있으면 먼저 처리
    if (bIsVirtualAccept && ActionRouter.ProcessInput(key, IE_Pressed) == Handled)
        return true;

    // 2순위: 마우스 클릭 시뮬레이션
    // SetIsGamepadSimulatedClick(true) 마킹 후 부모 호출
    InputSubsystem.SetIsGamepadSimulatedClick(bIsVirtualAccept);
    FAnalogCursor::HandleKeyDownEvent(SlateApp, InKeyEvent);
    InputSubsystem.SetIsGamepadSimulatedClick(false);
}
```

`SetIsGamepadSimulatedClick`으로 마킹하면 위젯 측에서 `UCommonInputSubsystem::IsGamepadSimulatedClick()`으로 판별해  
게임패드 클릭과 실제 마우스 클릭을 구분할 수 있다.

오프스크린 위젯 처리: `CVarShouldRouteOffscreenMouseButton`이 켜져 있으면  
히트 테스트 그리드를 우회하고 포커스된 위젯 경로로 직접 이벤트를 라우팅한다 (`RoutePointerDownEvent`).

### 커서 가시성 관리

```cpp
void FCommonAnalogCursor::RefreshCursorVisibility()
{
    const bool bShowCursor =
        bIsAnalogMovementEnabled          // 아날로그 이동 모드면 커서 표시
        || ActionRouter.ShouldAlwaysShowCursor()
        || ActiveInputMethod == ECommonInputType::MouseAndKeyboard;

    SlateUser->SetCursorVisibility(bShowCursor);
}
```

게임패드 전환 시 커서를 숨기고, 마우스로 전환 시 다시 표시한다.  
매 Tick에서 호출해 멀티플레이어 P2 커서 가시성 상태가 꼬이는 버그를 방어한다.

---

## 3. 전체 흐름 요약

```
[게임패드 스틱 입력]
        │
        ▼
FCommonAnalogCursor::HandleAnalogInputEvent()
  └── FAnalogCursor::HandleAnalogInputEvent()  ← AnalogValues 캐싱
        └── bIsAnalogMovementEnabled가 false면 이동 계산 자체를 skip

[매 프레임 Tick]
        │
        ├─ 포커스 연동 모드: 포커스 위젯 중앙으로 커서 텔레포트 (보이지 않게)
        ├─ 아날로그 이동 모드: CalculateTickedCursorPosition() → 커서 이동
        └─ 오른쪽 스틱: ScrollRecipient에 MouseWheel 이벤트 주입

[A버튼 / Virtual_Gamepad_Accept]
        │
        ├─ UIAction 바인딩 있으면 → ActionRouter.ProcessInput()
        └─ 없으면 → FPointerEvent(LeftMouseButton) 변환 → 커서 위치 클릭
```

---

## 4. 설계 포인트

**커서가 보이지 않아도 클릭이 동작하는 이유**  
포커스 연동 모드에서 커서는 항상 포커스된 위젯 중앙에 위치해 있다.  
A 버튼을 누르면 좌클릭으로 변환되고, Slate 히트 테스트가 그 좌표에서 위젯을 찾아 이벤트를 전달한다.  
커서가 숨겨진 것은 표시 여부일 뿐, 논리적 위치는 유효하다.

**`IsGameViewportInFocusPathWithoutCapture()` 의 "sweet spot"**  
헤더 주석에 직접 언급된 설계 의도: 뷰포트가 포커스 경로에 **있으면서** 커서를 **독점 캡처하지 않는** 상태.  
게임 플레이 중(마우스 캡처 상태)에는 UI가 입력을 가로채지 않고, UI 모드(캡처 해제)에서만 동작한다.
