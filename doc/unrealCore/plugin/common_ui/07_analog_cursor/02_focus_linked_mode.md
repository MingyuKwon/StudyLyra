# 02. 포커스 연동 모드

> 소스: `CommonAnalogCursor.cpp`, `NavigationConfig.cpp`, `CommonActivatableWidget.cpp`

`bIsAnalogMovementEnabled == false` 일 때 활성화되는 기본 동작 모드.  
게임패드 사용 중이고 `ShouldLinkCursorToGamepadFocus()` 설정이 켜져 있을 때 동작한다.

---

## 핵심 아이디어: 커서가 포커스를 "추종"

아날로그 이동 모드와 포커스 연동 모드의 근본적인 차이는 **누가 네비게이션을 주도하는가**다.

| 아날로그 이동 모드 | 포커스 연동 모드 |
|-----------|---------|
| AnalogCursor가 커서를 이동 | **Slate 네비게이션 시스템**이 포커스를 이동 |
| 커서가 히트 테스트 위치를 결정 | 포커스가 상호작용 대상을 결정 |
| 커서를 보여줌 | 커서는 숨겨진 채 포커스 위젯 중앙에 텔레포트 |
| A 버튼 → 커서 있는 곳 클릭 | A 버튼 → 포커스 위젯 클릭 (커서가 이미 거기 있음) |

`FCommonAnalogCursor`는 이 모드에서 커서를 **직접 이동시키지 않는다**.  
Slate 포커스가 변경될 때마다 커서를 포커스 위젯 중앙으로 조용히 따라붙이는 역할만 한다.

---

## 입력이 어떻게 처리되는가

같은 왼쪽 스틱이지만 이벤트 종류에 따라 처리 경로가 완전히 다르다.

### 경로 1: 왼쪽 스틱 Analog Axis 이벤트 (`Gamepad_LeftX/Y`)

```cpp
bool FCommonAnalogCursor::HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent)
{
    if (IsRelevantInput(InAnalogInputEvent))
    {
        bool bParentHandled = FAnalogCursor::HandleAnalogInputEvent(SlateApp, InAnalogInputEvent);
        // FAnalogCursor::HandleAnalogInputEvent: AnalogValues 배열에 값 캐싱 후 true 반환

        if (bIsAnalogMovementEnabled)
        {
            return bParentHandled;  // 아날로그 이동 모드: true (소비)
        }
    }
    return false;  // 포커스 연동 모드: false (소비하지 않음) → Slate로 통과
}
```

포커스 연동 모드에서는 `false` 를 반환한다. 이벤트가 소비되지 않고 Slate까지 전달된다.  
Slate의 `FNavigationConfig`는 이 axis 값을 받아 임계값을 넘으면 네비게이션 방향을 생성한다.

### 경로 2: 왼쪽 스틱 디지털 이벤트 (`Gamepad_LeftStick_Up/Down/Left/Right`)

스틱이 일정 각도 이상 기울면 엔진이 디지털 키 이벤트도 함께 발생시킨다.  
이 이벤트들은 `FAnalogCursor::HandleKeyDownEvent`가 소비한다 (`return true`).

```
Gamepad_LeftStick_Up → FAnalogCursor::HandleKeyDownEvent → return true (소비)
                                                         → Slate 네비게이션 도달 안 함
```

추가로, 기본 `FNavigationConfig`의 `KeyEventRules`에는 `Gamepad_LeftStick_*` 가 없다.  
소비 여부와 무관하게 이 키는 Slate 네비게이션을 발생시키지 않는다.  
**왼쪽 스틱 네비게이션은 axis 이벤트 경로로만 이루어진다.**

### 경로 3: D-Pad (`Gamepad_DPad_Up/Down/Left/Right`)

```
Gamepad_DPad_Up → FCommonAnalogCursor::HandleKeyDownEvent
                       → FAnalogCursor::HandleKeyDownEvent
                             → LeftStick_*? No. Virtual_Accept? No.
                             → return false (소비 안 함)
                       → Slate 네비게이션 도달 → 포커스 이동
```

`FAnalogCursor`는 D-Pad 키를 소비하지 않는다. Slate의 `FNavigationConfig`가 처리한다.

---

## Slate FNavigationConfig — 네비게이션의 주체

> 소스: `Engine/Source/Runtime/Slate/Private/Framework/Application/NavigationConfig.cpp`

소비되지 않은 입력 이벤트가 `FSlateApplication`에 도달하면,  
등록된 `FNavigationConfig`가 해당 이벤트가 네비게이션을 의미하는지 판단한다.

### 키 이벤트 → 네비게이션

```cpp
// FNavigationConfig 기본 KeyEventRules
KeyEventRules.Emplace(EKeys::Gamepad_DPad_Left,  EUINavigation::Left);
KeyEventRules.Emplace(EKeys::Gamepad_DPad_Right, EUINavigation::Right);
KeyEventRules.Emplace(EKeys::Gamepad_DPad_Up,    EUINavigation::Up);
KeyEventRules.Emplace(EKeys::Gamepad_DPad_Down,  EUINavigation::Down);
// 키보드 방향키도 동일하게 등록됨
```

### Analog Axis 이벤트 → 네비게이션

```cpp
// FNavigationConfig 기본 아날로그 설정
AnalogHorizontalKey = EKeys::Gamepad_LeftX;  // 왼쪽 스틱 좌우
AnalogVerticalKey   = EKeys::Gamepad_LeftY;  // 왼쪽 스틱 상하
AnalogNavigationHorizontalThreshold = 0.50f;
AnalogNavigationVerticalThreshold   = 0.50f;
```

임계값(50%)을 초과하면 네비게이션 방향이 결정된다:

```
Gamepad_LeftX >  0.5 → EUINavigation::Right
Gamepad_LeftX < -0.5 → EUINavigation::Left
Gamepad_LeftY >  0.5 → EUINavigation::Up
Gamepad_LeftY < -0.5 → EUINavigation::Down
```

임계값 범위 이내로 돌아오면 해당 방향의 반복 상태가 리셋되어, 다음 기울임 시 초기 딜레이부터 다시 시작한다.

### 아날로그 네비게이션 반복 속도

```cpp
float FNavigationConfig::GetRepeatRateForPressure(float InPressure, int32 InRepeats) const
{
    const float RepeatRate = (InRepeats == 0) ? 0.5f : 0.25f;  // 첫 반복: 0.5s, 이후: 0.25s
    if (InPressure > 0.90f)
    {
        return RepeatRate * 0.5f;  // 90% 이상 압력: 속도 2배
    }
    return RepeatRate;
}
```

스틱을 살짝 기울이면 0.5초 간격, 이후 0.25초 간격으로 반복 네비게이션이 발생한다.  
스틱을 끝까지 밀면(90% 이상) 속도가 2배가 된다.

---

## FNavigationReply — 위젯의 네비게이션 응답

`FSlateApplication::Navigate(EUINavigation Direction)` 가 호출되면  
현재 포커스된 위젯에서 `SWidget::OnNavigation(Direction)` 을 호출한다.  
위젯은 `FNavigationReply` 를 반환하여 어떤 일이 일어날지 결정한다.

| 응답 종류 | 의미 |
|----------|------|
| `FNavigationReply::Next()` | 해당 방향에서 기하학적으로 가장 가까운 포커서블 위젯으로 이동 (기본값) |
| `FNavigationReply::Explicit(Widget)` | 지정한 특정 위젯으로 점프 |
| `FNavigationReply::Stop()` | 이 방향 네비게이션을 차단 |
| `FNavigationReply::Escape(Direction)` | 현재 컨테이너를 탈출해 부모에게 네비게이션을 위임 |

UMG에서는 `UWidget`의 `Navigation` 프로퍼티로 각 방향의 응답을 블루프린트에서 설정할 수 있다.  
`FNavigationReply::Next()`는 Slate가 위젯 트리를 순회하며 가장 가까운 포커서블 위젯을 찾는다.

---

## UCommonActivatableWidget — 초기 포커스 씨딩

UI 레이어가 열릴 때 어떤 위젯이 처음 포커스를 받는가는 `UCommonActivatableWidget`이 결정한다.

```cpp
// UIActionRouterTypes.cpp
void SetFocusForActivatableWidget(...)
{
    if (UWidget* DesiredTarget = LeafWidget->GetDesiredFocusTarget())
    {
        DesiredTarget->SetFocus();  // 활성화된 위젯이 원하는 초기 포커스 대상
    }
    else if (LeafWidget->IsFocusable())
    {
        LeafWidget->SetFocus();     // fallback: 위젯 자신에게 포커스
    }
}
```

`GetDesiredFocusTarget()` 은 `UCommonActivatableWidget::NativeGetDesiredFocusTarget()` 를 호출한다.  
블루프린트에서 `BP_GetDesiredFocusTarget` 이벤트를 오버라이드해 첫 포커스 위젯을 지정한다.

이 초기 포커스가 `FCommonAnalogCursor` 입장에서는 첫 "커서 위치"가 된다.  
레이어 활성화 → 포커스 씨딩 → Tick에서 감지 → 커서 텔레포트.

---

## Tick에서의 커서 추종 메커니즘

```cpp
// FCommonAnalogCursor::Tick() 중 포커스 연동 모드 처리
TSharedPtr<SWidget> CursorTarget = SlateUser->GetFocusedWidget();

// ListView 특수 처리: 포커스된 ListView 대신 선택된 Row 위젯을 타깃으로
if (TSharedPtr<ITableViewMetadata> TableViewMetadata = CursorTarget->GetMetaData<ITableViewMetadata>())
{
    TArray<TSharedPtr<ITableRow>> SelectedRows = TableViewMetadata->GatherSelectedRows();
    if (SelectedRows.Num() > 0)
    {
        CursorTarget = SelectedRows[0]->AsWidget();
    }
}

// 포커스가 바뀌거나, 포커스된 위젯이 이동한 경우에만 커서 이동 (매 프레임 이동 방지)
if (CursorTarget != PinnedLastCursorTarget
    || TargetGeometry.GetAccumulatedRenderTransform() != LastCursorTargetTransform)
{
    // 커서 캡처 중이면 해제 (애니메이션 위젯 전환 시 캡처가 남는 버그 방지)
    if (SlateUser->HasCursorCapture() && !SlateUser->DoesWidgetHaveAnyCapture(CursorTarget))
    {
        SlateUser->ReleaseCursorCapture();
    }

    const FVector2D AbsoluteWidgetCenter =
        TargetGeometry.GetAbsolutePositionAtCoordinates(FVector2D(0.5f, 0.5f));
    SlateUser->SetCursorPosition(AbsoluteWidgetCenter);
}
```

**게임 뷰포트가 포커스 대상인 경우**  
활성화된 UI 레이어가 없고 게임 뷰포트 자체가 포커스된 상태면,  
커서를 뷰포트 중앙이 아닌 **플레이어의 위젯 호스트 레이어(`GetPlayerWidgetHostGeometry`) 중앙**으로 이동시킨다.

**유효 타깃 없음**  
`CursorTarget`이 null이거나 크기가 0에 가까우면 `SetNormalizedCursorPosition(FVector2D::ZeroVector)` 를 호출해 커서를 뷰포트 좌상단 근처로 이동시킨다.

---

## 정리: 왜 아날로그 스틱만의 문제가 아닌가

포커스 연동 모드의 네비게이션에는 아날로그 커서 클래스 자체보다 훨씬 많은 레이어가 관여한다.

```
[사용자가 스틱을 기울임]
        ↓
FCommonAnalogCursor: "나는 이 이벤트를 소비하지 않겠다" (return false)
        ↓
FSlateApplication: FNavigationConfig에게 위임
        ↓
FNavigationConfig: "이 방향으로 네비게이션해야 함" (임계값 판단 + 반복 타이밍)
        ↓
FSlateApplication::Navigate(): 현재 포커스 위젯에게 OnNavigation() 호출
        ↓
SWidget::OnNavigation() → FNavigationReply: "다음 위젯은 여기" 또는 "막아" 또는 "탈출"
        ↓
Slate: 위젯 트리 탐색 → 다음 포커서블 위젯으로 포커스 이동
        ↓
FCommonAnalogCursor::Tick(): "포커스가 바뀌었군" → 커서 텔레포트
        ↓
[A 버튼] → 커서 위치에 좌클릭 → 히트 테스트 성공
```

아날로그 커서는 전체 시스템에서 **시작 트리거**(이벤트를 흘려보냄)와 **마지막 단계**(커서 위치 동기화)만 담당한다.  
중간의 네비게이션 방향 결정, 위젯 탐색, 포커스 설정은 모두 Slate가 처리한다.
