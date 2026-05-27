# 위젯 스택 — UCommonActivatableWidget

> 관련 소스: `UI/LyraActivatableWidget.h/cpp`, `UI/LyraHUDLayout.h/cpp`,  
>             `UI/Subsystem/LyraUIManagerSubsystem.h`

---

## UMG vs CommonUI 위젯 관리 방식 차이

```
[일반 UMG]
AddToViewport() → 그냥 화면에 올라감
SetVisibility(Hidden) → 그냥 숨김
입력 제어, 포커스, 닫기 처리를 직접 구현해야 함

[CommonUI]
PushContentToLayer() → 레이어 스택에 올라감
DeactivateWidget()   → 스택에서 내려옴
입력 제어, 포커스, 닫기를 프레임워크가 자동 처리
```

---

## UCommonActivatableWidget

CommonUI 위젯의 기반 클래스. "활성화/비활성화"가 핵심 개념이다.

```
활성화(Activated)   → 스택 최상위에 올라와 있음. 포커스 받음. 입력 모드 결정.
비활성화(Deactivated) → 다른 위젯이 위에 올라옴. 포커스 없음.
```

### 주요 콜백

```cpp
virtual void NativeOnActivated() override;    // 활성화될 때 (스택 최상위 진입)
virtual void NativeOnDeactivated() override;  // 비활성화될 때 (다른 위젯이 위에 올라옴)

// BP에서 오버라이드
event OnActivated();
event OnDeactivated();
```

`NativeOnActivated()`에서 애니메이션 재생, 데이터 갱신 등을 처리.  
`NativeOnDeactivated()`에서 타이머 정리, 사운드 정지 등을 처리.

### DeactivateWidget()

```cpp
// 자기 자신을 스택에서 꺼내는 함수 (닫기 버튼에 바인딩)
DeactivateWidget();
```

pop 되면 아래 위젯이 자동으로 다시 활성화된다.

---

## 레이어 스택 — UGameUIManagerSubsystem

CommonUI는 화면을 **레이어**로 구분하고, 각 레이어가 독립적인 스택을 갖는다.

```
UI.Layer.Modal   ← 가장 위 (확인창, 경고 팝업)
UI.Layer.Menu    ← 메뉴 팝업 (설정 화면, ESC 메뉴)
UI.Layer.GameMenu ← 게임 내 메뉴 (인벤토리 등)
UI.Layer.Game    ← 가장 아래 (HUD, 크로스헤어)
```

각 레이어는 독립적인 스택을 가진다. 게임패드 입력 수신자는 다음 규칙으로 결정된다:

```
활성 위젯이 있는 레이어 중 가장 높은 레이어를 찾는다
→ 그 레이어의 스택 최상위 위젯이 입력을 독점
→ 나머지 모든 레이어는 입력 차단
```

예: `Modal`에 위젯이 하나라도 있으면 `Menu` 스택 최상위 위젯도 입력을 받지 못한다.  
`Modal`이 pop 되면 `Menu`가 다시 최상위 레이어가 되어 포커스를 돌려받는다.

Lyra에서는 `ULyraUIManagerSubsystem`이 `UGameUIManagerSubsystem`을 상속해서 사용한다.

### 위젯 추가 방법

```cpp
// C++에서 레이어에 푸시
UCommonUIExtensions::PushContentToLayer_ForPlayer(
    GetOwningLocalPlayer(),
    TAG_UI_LAYER_MENU,        // "UI.Layer.Menu"
    EscapeMenuClass           // 표시할 위젯 클래스
);
```

Blueprint에서는 `Push Content to Layer for Player` 노드를 사용.

---

## 전체 흐름 — 설정 화면 열기/닫기 예시

```
[열기]
HUDLayout에서 ESC 입력 감지
    └─ PushContentToLayer(UI.Layer.Menu, SettingsMenuClass)
            └─ SettingsMenu 위젯 생성
            └─ NativeOnActivated() 호출
            └─ GetDesiredFocusTarget() → 첫 버튼에 포커스
            └─ GetDesiredInputConfig() → Menu 모드 → 게임 입력 차단

[닫기]
닫기 버튼 클릭 (또는 B버튼 UIAction)
    └─ DeactivateWidget()
            └─ NativeOnDeactivated() 호출
            └─ 스택에서 제거
            └─ 아래 HUD 위젯이 다시 활성화
            └─ GetDesiredInputConfig() → Game 모드 → 게임 입력 복구
```

---

## Lyra의 ULyraActivatableWidget

`UCommonActivatableWidget`을 상속. 추가된 것은 입력 모드 설정 프로퍼티뿐이다.

```cpp
UPROPERTY(EditDefaultsOnly, Category = Input)
ELyraWidgetInputMode InputConfig = ELyraWidgetInputMode::Default;

UPROPERTY(EditDefaultsOnly, Category = Input)
EMouseCaptureMode GameMouseCaptureMode = EMouseCaptureMode::CapturePermanently;
```

에디터에서 위젯 Blueprint의 디테일 패널에서 직접 설정한다.
