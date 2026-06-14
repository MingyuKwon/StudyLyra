# Slate 포커스 시스템

> 소스 경로  
> - `Engine/Source/Runtime/SlateCore/Public/Input/Events.h`  
> - `Engine/Source/Runtime/SlateCore/Public/Input/NavigationReply.h`  
> - `Engine/Source/Runtime/SlateCore/Public/Widgets/SWidget.h`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/NavigationConfig.cpp`

---

## 포커스란

Slate에서 포커스(Keyboard Focus)는 **"현재 키보드·게임패드 입력을 받는 위젯"** 을 가리킨다.

- 유저 한 명당 **포커스를 가진 위젯은 항상 하나**다 (`FSlateUser` 단위로 관리).
- 마우스 호버와 독립적이다. 커서가 다른 곳에 있어도 포커스 위젯은 유지된다.
- 게임패드 D-pad/스틱 입력은 이 포커스를 이동시키는 방식으로 UI를 탐색한다.

> 이름이 "Keyboard Focus"인 이유: 게임패드 지원 이전에 설계된 시스템이라 이름이 그대로 남았다.  
> 실제 의미는 "방향 네비게이션의 대상이 될 수 있는가"다.

---

## 포커스를 받을 수 있는 위젯의 조건

```cpp
// SWidget.h
virtual bool SupportsKeyboardFocus() const;  // 기본값: false
```

이 함수가 `true`를 반환하는 위젯만 방향 네비게이션의 후보가 된다.

```cpp
// SButton (UMG 기본 버튼)
virtual bool SupportsKeyboardFocus() const override { return false; }  // 후보 제외

// SCommonButton (CommonUI 버튼)
virtual bool SupportsKeyboardFocus() const override { return bIsFocusable; }  // 후보 포함
```

`UButton`으로 만든 버튼은 후보 수집 단계에서 제외되어 방향키로 이동 불가능하다.

---

## 포커스 이동 — Navigate() 흐름

```
[1] D-pad 누름 / 왼쪽 스틱 기울기
        ↓
[2] FNavigationConfig
     ├─ 키 이벤트 → KeyEventRules 테이블 조회
     │    예) Gamepad_DPad_Up → EUINavigation::Up
     └─ Analog axis → 임계값(0.5) 초과 시 EUINavigation 생성

[3] FSlateApplication::Navigate(EUINavigation::Up)
        ↓
[4] 현재 포커스 위젯에서 OnNavigation() 호출
        ↓
[5] FNavigationReply 반환 → 다음 동작 결정
        ↓
[6] 포커스 이동 → OnFocusLost / OnFocusReceived 호출
```

---

## 방향 네비게이션의 두 단계 — OnKeyDown과 OnNavigation

> 소스  
> - `Engine/Source/Runtime/SlateCore/Private/Widgets/SWidget.cpp:412`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp:440, 3600`  
> - `Engine/Source/Runtime/SlateCore/Public/Input/NavigationReply.h`

방향 네비게이션은 내부적으로 **완전히 다른 두 단계**로 분리되어 있다.  
이 구조를 모르면 "누가 언제 뭘 결정하는가"를 혼동하기 쉽다.

```
① OnKeyDown()   → "이 키가 방향키인가? 맞으면 네비게이션 시작해."   FReply 반환
② OnNavigation() → "네비게이션이 내 경계에 도달했을 때 어떻게 할 건가?"  FNavigationReply 반환
```

두 함수는 **서로 다른 질문에 답한다.** 반환 타입도 다르다.

---

### 1단계 — OnKeyDown: 네비게이션 개시 신호

D-pad Down이 들어오면 Slate는 Bubble 단계에서 포커스 위젯들의 `OnKeyDown()`을 순서대로 호출한다.  
위젯이 `OnKeyDown()`을 오버라이드하지 않았다면 `SWidget`의 기본 구현이 실행된다.

```cpp
// SWidget.cpp:412
FReply SWidget::OnKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
    if (bCanSupportFocus && SupportsKeyboardFocus())
    {
        EUINavigation Direction = FSlateApplicationBase::Get().GetNavigationDirectionFromKey(InKeyEvent);
        if (Direction != EUINavigation::Invalid)
        {
            const ENavigationGenesis Genesis = InKeyEvent.GetKey().IsGamepadKey()
                ? ENavigationGenesis::Controller : ENavigationGenesis::Keyboard;
            return FReply::Handled().SetNavigation(Direction, Genesis);
        }
    }
    return FReply::Unhandled();
}
```

- `GetNavigationDirectionFromKey(DPad_Down)` → `EUINavigation::Down`
- `FReply::Handled().SetNavigation(Down, Controller)` 반환

`SetNavigation()`은 Reply 안에 방향 정보를 심는 것이다.  
이 Reply가 Handled로 표시되는 순간, 이벤트 라우팅 루프도 중단된다.

---

### 중간 — FEventRouter::Route가 즉시 ProcessReply 호출

라우팅 루프는 각 위젯 Reply를 받을 때마다 즉시 `ProcessReply()`를 호출한다.

```cpp
// SlateApplication.cpp:452
for (; !Reply.IsEventHandled() && RoutingPolicy.ShouldKeepGoing(); RoutingPolicy.Next())
{
    Reply = Lambda(ArrangedWidget, EventCopy).SetHandler(...);
    //       ↑ SWidget::OnKeyDown() 호출

    ProcessReply(ThisApplication, RoutingPath, Reply, ...);
    //  ↑ Handled().SetNavigation() 감지 → 즉시 OnNavigation 순회 시작
}
```

루프가 끝난 뒤 한 번 처리하는 것이 아니라, Reply가 나온 그 자리에서 바로 처리한다.

---

### 2단계 — OnNavigation: 경계 규칙 선언

`ProcessReply()`가 Reply 안의 네비게이션 정보를 감지하면,  
포커스 경로를 **리프→루트 방향으로 다시 순회**하며 각 위젯의 `OnNavigation()`을 호출한다.

```cpp
// SlateApplication.cpp:3631
for (int32 WidgetIndex = NavigationSource.Widgets.Num() - 1; WidgetIndex >= 0; --WidgetIndex)
{
    NavigationReply = SomeWidget->OnNavigation(Geometry, NavigationEvent).SetHandler(SomeWidget);

    if (NavigationReply.GetBoundaryRule() != EUINavigationRule::Escape || WidgetIndex == 0)
    {
        AttemptNavigation(NavigationSource, NavigationEvent, NavigationReply, SomeWidget);
        break;  // Escape가 아니면 더 이상 올라가지 않음
    }
    // Escape면 계속 루트 방향으로 올라감
}
```

각 위젯은 `OnNavigation()`에서 `FNavigationReply`를 반환해 **"네비게이션이 내 영역에 도달했을 때 어떻게 할 건지"** 를 선언한다.  
`Escape`가 반환되면 계속 루트 방향으로 올라가고, 다른 규칙이 반환되면 그 자리에서 처리한다.

`SListView`는 이를 직접 구현한 대표 예다.

```cpp
// SListView.h:512
virtual FNavigationReply OnNavigation(const FGeometry& MyGeometry, const FNavigationEvent& InNavigationEvent) override
{
    const int32 AttemptSelectIndex = CurSelectionIndex + NumItemsPerLine;  // Down이면 +1

    if (ItemsSourceRef.IsValidIndex(AttemptSelectIndex))
    {
        NavigationSelect(ItemToSelect.GetValue(), InNavigationEvent);  // 선택 + 스크롤
        return FNavigationReply::Explicit(nullptr);                    // "내가 처리했음, 포커스 그대로"
    }

    return STableViewBase::OnNavigation(MyGeometry, InNavigationEvent);  // 범위 벗어남 → Escape
}
```

- 인덱스 유효 → `Explicit(nullptr)`: 내부에서 직접 처리 완료. 포커스 위젯 변동 없음.
- 인덱스 무효 (첫 항목에서 Up 등) → `Escape()`: "나는 처리 못 함, 더 위로 올라가라."

---

### 전체 연결 요약

```
[Gamepad_DPad_Down]
        ↓
FEventRouter Bubble 단계
  → SWidget::OnKeyDown() 기본 구현
      → GetNavigationDirectionFromKey(DPad_Down) → EUINavigation::Down
      → FReply::Handled().SetNavigation(Down, Controller)
        ↑ "키 이벤트 처리 완료, 네비게이션 시작해" 신호
        ↓
FEventRouter::ProcessReply() → FSlateApplication::ProcessReply()
  → Reply 안에 Navigation 정보 감지
  → 포커스 경로 위젯들의 OnNavigation(Down) 순회 (리프→루트)
        ↓
SListView::OnNavigation(Down)
  → 다음 인덱스 계산 + NavigationSelect()
  → FNavigationReply::Explicit(nullptr)
    ↑ "경계 규칙: 내가 직접 처리했음, 포커스 유지" 선언
        ↓
[다음 항목 선택 + 시각 포커스 이동 완료]
```

`Explicit(nullptr)`의 `nullptr`는 "포커스를 옮길 위젯이 없다"는 뜻이 아니라,  
"Slate가 포커스를 바꿀 필요 없다, 내가 내부 상태로 이미 처리했다"는 뜻이다.

---

### 3단계 — AttemptNavigation: FNavigationReply 해석

> 소스: `Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp:6382`

`OnNavigation()` 순회가 끝나 `FNavigationReply`가 결정되면, `AttemptNavigation()`이 그 규칙에 따라 실제 포커스 이동을 수행한다.

```
FNavigationReply 종류별 분기 (AttemptNavigation 내부):

Explicit(SomeWidget)  → 유효한 위젯이면 즉시 그 위젯으로 포커스 이동
                         (SupportsKeyboardFocus() 검사 통과 시)

Explicit(nullptr)     → FocusRecipient 유효성 검사 실패
                         → DestinationWidget = null → 포커스 변동 없음
                         (SListView가 내부 처리 완료 후 쓰는 패턴)

Custom(Delegate)      → 델리게이트 실행 → 반환 위젯으로 포커스 이동

그 외                 → HitTestGrid.FindNextFocusableWidget()
(Escape / Stop / Wrap)  ← 화면 좌표 기반 기하 탐색 (아래 참고)
```

```cpp
// SlateApplication.cpp:6397
if (NavigationReply.GetBoundaryRule() == EUINavigationRule::Explicit)
{
    // nullptr이면 조건 불통과 → DestinationWidget 비어있음
    if (FocusRecipient && FocusRecipient->IsEnabled() && FocusRecipient->SupportsKeyboardFocus())
        DestinationWidget = NavigationReply.GetFocusRecipient();
}
else if (NavigationReply.GetBoundaryRule() == EUINavigationRule::Custom)
{
    DestinationWidget = FocusDelegate.Execute(NavigationType);
}
else
{
    // Escape / Stop / Wrap → 기하 탐색
    DestinationWidget = HitTestGrid.FindNextFocusableWidget(
        FocusedArrangedWidget, NavigationType, NavigationReply, BoundaryWidget, UserIndex);
}
```

기하 탐색은 `OnNavigation()`을 통해 **아무 위젯도 처리를 선언하지 않았을 때** Slate가 화면을 직접 보고 찾아주는 최후 수단이다.

#### 화면 좌표 기반 기하 탐색 — FindNextFocusableWidget

`Escape`가 최상위까지 올라오면 `HitTestGrid.FindNextFocusableWidget()`이 실행된다.

```
[1] 후보 수집
    화면에 렌더링된 위젯 중 SupportsKeyboardFocus() == true 인 것만

[2] 방향 필터링
    현재 포커스 위젯 중심 기준으로
    Down이면 → Y 좌표가 더 큰 후보만 남김

[3] Navigation Score 계산 (거리 + 정렬 보정)
    후보들 중 Score 최솟값 위젯으로 포커스 이동
```

위젯 트리 순서가 아니라 **실제 화면 픽셀 좌표**를 기준으로 탐색하기 때문에,  
에디터에서 배치한 위치 그대로 네비게이션이 자연스럽게 동작한다.

#### 요약

```
OnNavigation 순회 결과
    │
    ├── Explicit(SomeWidget) → 바로 그 위젯으로 포커스 이동  (기하 탐색 없음)
    ├── Explicit(nullptr)    → 포커스 변동 없음              (SListView 케이스)
    ├── Custom(Delegate)     → 델리게이트 반환 위젯으로 이동  (기하 탐색 없음)
    └── Escape (최상위까지)  → FindNextFocusableWidget()      ← 기하 탐색 발동
                               화면 좌표 기준 최근접 포커서블 위젯
```

---

## FNavigationReply — 위젯의 네비게이션 응답

위젯은 `SWidget::OnNavigation()` 에서 `FNavigationReply` 를 반환해 포커스가 어떻게 이동할지 결정한다.

```cpp
// Engine/Source/Runtime/SlateCore/Public/Input/NavigationReply.h
```

| 응답 | 의미 |
|------|------|
| `FNavigationReply::Escape()` | 기본값. 이 컨테이너 경계를 통과해 가장 가까운 위젯으로 이동 |
| `FNavigationReply::Stop()` | 이 방향으로 이동 불가. 포커스 그대로 |
| `FNavigationReply::Wrap()` | 경계에 도달하면 반대편으로 순환 |
| `FNavigationReply::Explicit(Widget)` | 특정 위젯으로 바로 이동 |
| `FNavigationReply::Custom(Delegate)` | 델리게이트가 반환하는 위젯으로 이동 |

기본값이 `Escape`이기 때문에, 특별히 오버라이드하지 않으면 방향에 맞는 가장 가까운 포커서블 위젯으로 이동한다.

UMG에서는 각 `UWidget`의 `Navigation` 프로퍼티에서 방향별로 설정할 수 있다.

---

## EFocusCause — 포커스가 바뀐 이유

`OnFocusReceived` / `OnFocusLost` 이벤트에 `FFocusEvent` 로 전달된다.

```cpp
// Engine/Source/Runtime/SlateCore/Public/Input/Events.h
enum class EFocusCause : uint8
{
    Mouse,                // 마우스 클릭으로 포커스 변경
    Navigation,           // D-pad/스틱/키보드 방향키로 이동
    SetDirectly,          // 코드에서 SetUserFocus() 직접 호출
    Cleared,              // ESC 등으로 포커스 명시적 해제
    OtherWidgetLostFocus, // 같은 포커스 경로의 다른 위젯이 포커스를 잃음
    WindowActivate,       // 창이 활성화되면서 포커스 설정
};
```

`EFocusCause::Navigation` 은 게임패드/키보드 방향 이동으로 포커스가 온 경우다.  
CommonUI의 `UCommonButtonBase`는 이 원인을 보고 시각 상태를 구분할 수 있다.

---

## SWidget 포커스 이벤트

```cpp
// SWidget.h
virtual FReply OnFocusReceived(const FGeometry& MyGeometry, const FFocusEvent& InFocusEvent);
virtual void   OnFocusLost(const FFocusEvent& InFocusEvent);
```

UMG에서는 `NativeOnFocusReceived` / `NativeOnFocusLost` 로 오버라이드한다.

포커스가 이동하면 Slate는 **포커스 경로(Focus Path)** 단위로 이벤트를 전파한다.  
포커스 경로는 루트 위젯부터 포커스된 위젯까지의 조상 체인이다.  
경로에서 벗어나는 위젯은 `OnFocusLost`, 새로 진입하는 위젯은 `OnFocusReceived`를 받는다.

---

## FSlateApplication::SetUserFocus()

```cpp
// 멀티플레이어 지원: 유저 인덱스 지정
bool SetUserFocus(uint32 UserIndex, const TSharedPtr<SWidget>& WidgetToFocus,
                  EFocusCause ReasonFocusIsChanging = EFocusCause::SetDirectly);

// 싱글플레이어(P1) 단축 버전
bool SetKeyboardFocus(const TSharedPtr<SWidget>& OptionalWidgetToFocus,
                      EFocusCause ReasonFocusIsChanging = EFocusCause::SetDirectly);

// 현재 포커스 위젯 조회
TSharedPtr<SWidget> GetUserFocusedWidget(uint32 UserIndex) const;
```

UMG 레이어에서는 `UWidget::SetFocus()` 를 사용하면 내부적으로 `SetUserFocus`를 호출한다.

---

## 네비게이션 커스터마이징

"다음 포커스 위젯을 어디로 할지"는 세 단계에서 개입할 수 있다.

```
입력 → FNavigationConfig → Navigate() → OnNavigation() → FNavigationReply 해석
         ↑ 레벨 3 (전역)                  ↑ 레벨 2 (C++)    ↑ 레벨 1 (UMG 프로퍼티)
```

### 레벨 1 — UMG Navigation 프로퍼티 (가장 흔한 방법)

위젯 디테일 패널 → **Navigation** 섹션에서 방향별로 Rule을 지정한다.

> 소스: `Engine/Source/Runtime/UMG/Public/Blueprint/WidgetNavigation.h`

| Rule | 동작 |
|------|------|
| `Escape` | 기본값. 기하 탐색으로 가장 가까운 위젯 |
| `Stop` | 이 방향 이동 차단 |
| `Wrap` | 경계 도달 시 반대편으로 순환 |
| `Explicit` | 지정한 이름의 위젯으로 바로 이동 |
| `Custom` | 델리게이트가 반환하는 위젯으로 이동 (항상 호출) |
| `CustomBoundary` | 경계에 부딪혔을 때만 델리게이트 호출 |

`Custom` / `CustomBoundary` 선택 시 Blueprint에 `GetCustomNavigationTarget` 이벤트가 생성된다.  
인자로 `EUINavigation` 방향을 받고, 이동할 `UWidget*`을 반환하면 된다.

```cpp
// 내부 델리게이트 타입
DECLARE_DYNAMIC_DELEGATE_RetVal_OneParam(UWidget*, FCustomWidgetNavigationDelegate,
                                         EUINavigation, Navigation);
```

### 레벨 2 — SWidget::OnNavigation() 오버라이드 (C++ 위젯)

```cpp
virtual FNavigationReply OnNavigation(const FGeometry& MyGeometry,
                                       const FNavigationEvent& InNavigationEvent) override
{
    if (InNavigationEvent.GetNavigationType() == EUINavigation::Down)
    {
        return FNavigationReply::Explicit(NextWidget);  // 특정 위젯으로 강제 이동
    }
    return FNavigationReply::Escape();  // 나머지는 기본 동작
}
```

레벨 1이 UMG 레이어 위에서 동작하는 반면, 이 오버라이드는 Slate 레이어에서 직접 동작한다.  
`FNavigationReply`에서 `Custom(Delegate)`을 반환하면 C++에서도 동적 타깃 지정이 가능하다.

### 레벨 3 — FNavigationConfig 교체 (전역)

입력 → 방향 매핑 자체를 바꾸거나, 조건에 따라 네비게이션 전체를 제어하는 경우.

```cpp
// SlateApplication.h
SLATE_API void SetNavigationConfig(TSharedRef<FNavigationConfig> InNavigationConfig);
```

```cpp
class FMyNavigationConfig : public FNavigationConfig
{
    virtual EUINavigation GetNavigationDirectionFromKey(
        const FKeyEvent& InKeyEvent) const override
    {
        if (bNavigationLocked) return EUINavigation::Invalid;
        return FNavigationConfig::GetNavigationDirectionFromKey(InKeyEvent);
    }
};

FSlateApplication::Get().SetNavigationConfig(MakeShared<FMyNavigationConfig>());
```

CommonUI는 이 레벨을 건드리지 않는다. 기본 `FNavigationConfig`를 그대로 사용하며,  
레이어 격리는 `FActivatableTreeNode`로 포커스 씨딩 단계에서 처리한다.
