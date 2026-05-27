# Lyra UI 클래스 계층

> 출처: `UI/LyraActivatableWidget.h`, `UI/Foundation/LyraButtonBase.h`,  
>        `UI/Common/LyraBoundActionButton.h`, `UI/Foundation/LyraActionWidget.h`,  
>        `UI/LyraHUDLayout.h`, `UI/Subsystem/LyraUIManagerSubsystem.h`

---

## 전체 계층도

```
[위젯 기반]
UCommonActivatableWidget (CommonUI)
    └─ ULyraActivatableWidget          ← 모든 Lyra UI 화면의 기반
            └─ ULyraHUDLayout          ← 인게임 HUD 루트 위젯

[버튼]
UCommonButtonBase (CommonUI)
    └─ ULyraButtonBase                 ← 일반 버튼 (텍스트 오버라이드, 스타일 BP 이벤트)

UCommonBoundActionButton (CommonUI)
    └─ ULyraBoundActionButton          ← UIAction 연결 버튼 (장치별 스타일 에셋 교체)

[아이콘]
UCommonActionWidget (CommonUI)
    └─ ULyraActionWidget               ← 리맵핑/장치 반영 버튼 아이콘 위젯

[연결 끊김]
UCommonActivatableWidget (CommonUI)
    └─ ULyraControllerDisconnectedScreen  ← 컨트롤러 연결 끊김 화면

[서브시스템]
UGameUIManagerSubsystem (CommonUI)
    └─ ULyraUIManagerSubsystem         ← HUD 가시성 틱 관리
```

---

## ULyraActivatableWidget

**모든 Lyra UI 화면의 기반 클래스.** Blueprint에서 이 클래스를 상속해 화면을 만든다.

CommonUI에서 추가된 것:
```cpp
// 에디터 디테일 패널에서 설정
UPROPERTY(EditDefaultsOnly, Category = Input)
ELyraWidgetInputMode InputConfig = ELyraWidgetInputMode::Default;
// Default / GameAndMenu / Game / Menu

UPROPERTY(EditDefaultsOnly, Category = Input)
EMouseCaptureMode GameMouseCaptureMode = EMouseCaptureMode::CapturePermanently;
```

`GetDesiredInputConfig()`를 오버라이드해서 설정값을 CommonUI에 전달한다.  
→ 자세한 내용: [`doc/unrealCore/plugin/common_ui/02_input_mode.md`](../../unrealCore/plugin/common_ui/02_input_mode.md)

**에디터 경고**: Blueprint에서 `GetDesiredFocusTarget`을 구현하지 않으면 컴파일 경고가 뜬다.

---

## ULyraHUDLayout

인게임 HUD의 루트 위젯. `ULyraActivatableWidget`을 상속.  
GameFeature의 `AddWidget` 액션으로 `UI.Layer.Game` 레이어에 추가된다.

역할:
- ESC 키 → 일시정지 메뉴 push
- 컨트롤러 연결 끊김 감지 → 연결 끊김 화면 push

→ 자세한 내용: [`02_hud_layout.md`](02_hud_layout.md)

---

## ULyraButtonBase

일반 게임 버튼. Blueprint에서 이 클래스를 상속해 커스텀 버튼을 만든다.

```cpp
// 텍스트 오버라이드 프로퍼티 (에디터에서 설정)
UPROPERTY(EditAnywhere, Category="Button", meta=(InlineEditConditionToggle))
uint8 bOverride_ButtonText : 1;

UPROPERTY(EditAnywhere, Category="Button", meta=(editcondition="bOverride_ButtonText"))
FText ButtonText;
```

Blueprint 이벤트:
```
UpdateButtonText(InText)  ← 텍스트 변경 시 호출
UpdateButtonStyle()       ← 입력 장치 변경 시 호출 (게임패드 ↔ 키보드)
```

---

## ULyraBoundActionButton

UIAction 태그에 연결되는 버튼. 장치가 바뀌면 스타일 에셋 자체를 교체한다.

```cpp
// 에디터에서 장치별 스타일 에셋 지정
TSubclassOf<UCommonButtonStyle> KeyboardStyle;
TSubclassOf<UCommonButtonStyle> GamepadStyle;
TSubclassOf<UCommonButtonStyle> TouchStyle;
```

`CommonInputSubsystem::OnInputMethodChangedNative`를 구독해서 자동 전환.  
→ 자세한 내용: [`doc/unrealCore/plugin/common_ui/04_button.md`](../../unrealCore/plugin/common_ui/04_button.md)

---

## ULyraActionWidget

버튼에 "현재 이 InputAction에 매핑된 키의 아이콘"을 표시하는 위젯.

```
EnhancedInputSubsystem.QueryKeysMappedToAction(AssociatedInputAction)
    → 현재 리맵핑된 키 확인
CommonInputPlatformSettings.TryGetInputBrush(Key, InputType, GamepadName)
    → 플랫폼/장치별 아이콘 브러시 반환
```

설정 방법: Blueprint에서 `AssociatedInputAction` 프로퍼티에 InputAction 에셋 연결.

---

## ULyraControllerDisconnectedScreen

컨트롤러가 모두 연결 해제될 때 표시되는 화면.  
`UI.Layer.Menu` 레이어에 push 된다.

```
Platform.Trait.Input.PrimarlyController 태그가 있는 플랫폼에서만 활성화
(콘솔 등 컨트롤러가 필수인 플랫폼)

PC는 이 태그가 없으므로 연결 끊김 화면이 표시되지 않음
```

---

## ULyraUIManagerSubsystem

`UGameUIManagerSubsystem`을 상속. 추가된 것:

```cpp
// 매 틱 HUD 가시성을 게임 상태에 맞게 동기화
void SyncRootLayoutVisibilityToShowHUD();
```

쇼 HUD 플래그(`PlayerController::bShowHUD`)에 따라 루트 레이아웃의 가시성을 자동 조정한다.
