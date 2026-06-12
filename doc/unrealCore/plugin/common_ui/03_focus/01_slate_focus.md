# 01. Slate 포커스 시스템

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

## "가장 가까운 위젯" 탐색 알고리즘

`Escape` 응답 시 Slate는 **화면 좌표 기반 기하학적 탐색**으로 다음 위젯을 찾는다.

```
[1] 후보 수집
    위젯 트리 전체 순회 → SupportsKeyboardFocus() == true 인 위젯만 수집

[2] 방향 필터링
    현재 포커스 위젯 중심 기준으로
    Up이면 → Y 좌표가 더 작은 후보만 남김

[3] Navigation Score 계산 (거리 + 정렬 보정)
    후보들 중 Score 최솟값 위젯으로 포커스 이동
```

UMG에서 위젯을 배치한 순서와 네비게이션 방향이 일치하는 이유는 트리 순서를 보는 게 아니라 **실제 화면 픽셀 좌표**를 보기 때문이다.

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
