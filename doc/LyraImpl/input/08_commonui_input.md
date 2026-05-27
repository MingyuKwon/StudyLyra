# CommonUI 입력 레이어

> 출처: `UI/LyraActivatableWidget.h/cpp`, `UI/Foundation/LyraActionWidget.h/cpp`,  
>        `UI/Foundation/LyraControllerDisconnectedScreen.h`,  
>        `UI/LyraGameViewportClient.cpp`

---

## 개요

Lyra의 모든 UI는 CommonUI 위에 구축된다.  
CommonUI는 **어떤 입력이 UI에 도달하는지**, **게임패드 포커스 이동**,  
**버튼 아이콘 표시** 등을 담당한다.

---

## ULyraActivatableWidget — 입력 모드 제어

모든 Lyra UI 위젯의 기반 클래스. `UCommonActivatableWidget`을 상속.

### ELyraWidgetInputMode

```cpp
enum class ELyraWidgetInputMode : uint8
{
    Default,      // 부모 위젯에 위임 (기본)
    GameAndMenu,  // 게임 + UI 모두 입력 수신
    Game,         // 게임 입력만 수신
    Menu,         // UI 입력만 수신 (마우스 캡처 없음)
};
```

### GetDesiredInputConfig() 구현

```cpp
TOptional<FUIInputConfig> ULyraActivatableWidget::GetDesiredInputConfig() const
{
    switch (InputConfig)
    {
    case GameAndMenu: return FUIInputConfig(ECommonInputMode::All,  GameMouseCaptureMode);
    case Game:        return FUIInputConfig(ECommonInputMode::Game, GameMouseCaptureMode);
    case Menu:        return FUIInputConfig(ECommonInputMode::Menu, EMouseCaptureMode::NoCapture);
    case Default:
    default:          return TOptional<FUIInputConfig>();  // 부모에게 위임
    }
}
```

CommonUI 스택에서 가장 위에 있는 활성 위젯의 `InputConfig`가 전체 입력 모드를 결정한다.  
팝업(확인창 등)을 열면 그 위젯의 Mode가 적용되고, 닫히면 아래 위젯의 Mode로 복구된다.

### 게임패드 UI 탐색 — BP_GetDesiredFocusTarget

```
위젯이 활성화될 때 CommonUI가 BP_GetDesiredFocusTarget()을 호출해
게임패드 커서의 첫 포커스 위젯을 결정한다.

이 함수를 구현하지 않으면:
→ 에디터 컴파일 경고: "GetDesiredFocusTarget wasn't implemented,
   you're going to have trouble using gamepads on this screen."
```

Blueprint에서 반드시 구현해야 게임패드로 해당 화면을 탐색할 수 있다.

---

## ULyraActionWidget — 버튼 아이콘 자동 갱신

`UCommonActionWidget`을 상속. UI에 "이 액션에 해당하는 버튼 아이콘"을 표시하는 위젯.

### GetIcon() 구현

```cpp
FSlateBrush ULyraActionWidget::GetIcon() const
{
    if (AssociatedInputAction)
    {
        // 1. 현재 이 액션에 매핑된 키 목록 조회 (리맵핑 반영)
        TArray<FKey> BoundKeys = EnhancedInputSubsystem->QueryKeysMappedToAction(AssociatedInputAction);

        // 2. 현재 입력 장치 종류 + 게임패드 이름으로 아이콘 브러시 획득
        if (!BoundKeys.IsEmpty())
            UCommonInputPlatformSettings::Get()->TryGetInputBrush(
                SlateBrush,
                BoundKeys[0],
                CommonInputSubsystem->GetCurrentInputType(),   // 키보드 vs 게임패드
                CommonInputSubsystem->GetCurrentGamepadName()  // Xbox / PS5 등
            );
    }
    return Super::GetIcon();  // 못 찾으면 DataTable 기본값 사용
}
```

결과: 플레이어가 키를 리맵핑해도 아이콘이 즉시 정확한 키로 업데이트된다.  
게임패드로 전환하면 키보드 아이콘 대신 게임패드 버튼 아이콘이 표시된다.

### 입력 장치 전환 감지

입력 장치 감지는 CommonUI가 담당한다.  
`UCommonInputSubsystem::GetCurrentInputType()` → `ECommonInputType::MouseAndKeyboard | Gamepad | Touch`

게임패드를 사용하기 시작하면 CommonUI가 자동으로 `CurrentInputType`을 갱신하고  
`LyraActionWidget`이 다음 갱신 시 정확한 아이콘을 표시한다.

---

## ULyraControllerDisconnectedScreen — 컨트롤러 연결 끊김

컨트롤러가 모두 연결 해제될 때 표시되는 전용 화면.  
`UCommonActivatableWidget`을 상속해 CommonUI 스택에 올라간다.

```
NativeOnActivated()
    └─ ShouldDisplayChangeUserButton() 확인
            ├─ PlatformSupportsUserChangeTags (FGameplayTagContainer) 체크
            └─ false → HBox_SwitchUser 숨김 / true → 표시

Button_ChangeUser 클릭
    └─ HandleChangeUserClicked()
            └─ 플랫폼 유저 선택 UI 표시
            └─ HandleChangeUserCompleted(Params)
```

플랫폼별 strict controller pairing 요구사항 (`Platform.Trait.Input.HasStrictControllerPairing`)이  
있는 플랫폼에서만 "Change User" 버튼을 노출한다.

---

## ULyraGameViewportClient — 커서 처리

```cpp
void ULyraGameViewportClient::Init(...)
{
    Super::Init(...);

    // Platform.Trait.Input.HardwareCursor 태그가 있으면 하드웨어 커서 사용
    const bool UseHardwareCursor =
        ICommonUIModule::GetSettings().GetPlatformTraits()
            .HasTag(TAG_Platform_Trait_Input_HardwareCursor);

    SetUseSoftwareCursorWidgets(!UseHardwareCursor);
}
```

- **PC (HardwareCursor 태그 있음)**: OS 하드웨어 커서 사용
- **콘솔/모바일 (HardwareCursor 태그 없음)**: UMG 소프트웨어 커서 위젯 사용

---

## 전체 CommonUI 입력 구조 요약

```
[입력 장치 감지]
UCommonInputSubsystem
    ├─ GetCurrentInputType()     ← KB/마우스 vs 게임패드 vs 터치
    └─ GetCurrentGamepadName()   ← Xbox / DualSense 등

[UI 입력 모드 스택]
CommonUI 활성화 스택 (LIFO)
    └─ 최상위 ULyraActivatableWidget의 ELyraWidgetInputMode가 현재 입력 모드 결정
            ├─ Menu  → 게임 입력 차단, 마우스 해방
            ├─ Game  → UI 입력 차단, 마우스 캡처
            └─ GameAndMenu → 모두 허용

[게임패드 UI 탐색]
CommonUI → BP_GetDesiredFocusTarget() → 첫 포커스 위젯
    └─ 방향키/스틱 → 다음 포커스 이동 (CommonUI가 자동 처리)

[버튼 아이콘]
ULyraActionWidget::GetIcon()
    └─ EnhancedInput.QueryKeysMappedToAction()  ← 현재 매핑 키
    └─ CommonInputPlatformSettings.TryGetInputBrush()  ← 플랫폼 아이콘
```
