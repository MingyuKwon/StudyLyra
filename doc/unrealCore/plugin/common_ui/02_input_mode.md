# 입력 모드 — FUIInputConfig

> 관련 소스: `UI/LyraActivatableWidget.h/cpp`

---

## 개념

CommonUI는 **스택 최상위 위젯의 입력 설정이 전체 입력을 지배**한다.  
위젯이 push/pop 될 때마다 CommonUI가 자동으로 입력 모드를 전환해준다.

```
[스택]
  ▶ Modal (ELyraWidgetInputMode::Menu)    ← 현재 입력 모드: Menu
  ─ Menu  (ELyraWidgetInputMode::Menu)
  ─ HUD   (ELyraWidgetInputMode::Game)
```

Modal이 pop 되면 → Menu 모드로 자동 전환.  
Menu까지 pop 되면 → Game 모드로 자동 전환.

---

## ELyraWidgetInputMode 4가지

### Default
```
부모 스택에게 위임한다.
이 위젯 자체는 입력 모드를 바꾸지 않는다.
HUD 안에 포함된 서브 위젯처럼, 단독으로 스택에 올라가지 않는 위젯에 사용.
```

### Menu
```
ECommonInputMode::Menu
EMouseCaptureMode::NoCapture

→ UI만 입력 받음. 게임 입력(캐릭터 이동 등) 차단.
→ 마우스가 캡처되지 않아 자유롭게 움직임.
→ 설정 화면, ESC 메뉴, 인벤토리 등에 사용.
```

### Game
```
ECommonInputMode::Game
EMouseCaptureMode::CapturePermanently (기본값)

→ 게임만 입력 받음. UI 클릭 등 차단.
→ 마우스가 캡처되어 게임 시점 조작에 사용됨.
→ HUD, 크로스헤어처럼 항상 떠 있는 오버레이에 사용.
```

### GameAndMenu
```
ECommonInputMode::All

→ 게임 + UI 둘 다 입력 받음.
→ 인게임 미니맵 클릭처럼 게임 중에도 UI 상호작용이 필요한 경우.
```

---

## 내부 동작 — GetDesiredInputConfig()

```cpp
// LyraActivatableWidget.cpp
TOptional<FUIInputConfig> ULyraActivatableWidget::GetDesiredInputConfig() const
{
    switch (InputConfig)
    {
    case ELyraWidgetInputMode::GameAndMenu:
        return FUIInputConfig(ECommonInputMode::All, GameMouseCaptureMode);
    case ELyraWidgetInputMode::Game:
        return FUIInputConfig(ECommonInputMode::Game, GameMouseCaptureMode);
    case ELyraWidgetInputMode::Menu:
        return FUIInputConfig(ECommonInputMode::Menu, EMouseCaptureMode::NoCapture);
    case ELyraWidgetInputMode::Default:
    default:
        return TOptional<FUIInputConfig>();  // 빈 값 = 부모에게 위임
    }
}
```

CommonUI가 스택을 순회하면서 `TOptional`이 값을 가진 첫 번째 위젯의 설정을 적용한다.

---

## 실제 설정 방법

Blueprint에서 위젯 클래스를 열고 디테일 패널:

```
Class Defaults
└─ Input
    ├─ Input Config: Menu        ← 여기서 선택
    └─ Game Mouse Capture Mode: No Capture
```

C++에서는 생성자에서:

```cpp
UMyWidget::UMyWidget(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
    InputConfig = ELyraWidgetInputMode::Menu;
}
```

---

## 주의: Visibility로 숨기는 것과의 차이

```
SetVisibility(ESlateVisibility::Hidden)
→ 위젯은 스택에 남아있음
→ 입력 모드가 그대로 유지됨
→ 포커스가 아래 위젯으로 내려가지 않음

DeactivateWidget()
→ 스택에서 완전히 제거
→ 입력 모드 자동 복구
→ 포커스 아래 위젯으로 자동 이동
```

UI를 "닫는" 동작은 반드시 `DeactivateWidget()`을 써야 한다.
