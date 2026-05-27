# 버튼 — CommonButtonBase 계층

> 관련 소스: `UI/Foundation/LyraButtonBase.h`,  
>             `UI/Common/LyraBoundActionButton.h/cpp`

---

## 클래스 계층

```
UWidget (엔진)
    └─ UButton (UMG 기본 버튼)

UCommonButtonBase (CommonUI)
    └─ ULyraButtonBase (Lyra)
            └─ (일반 게임 버튼)

UCommonBoundActionButton (CommonUI) ← UIAction에 자동 연결되는 버튼
    └─ ULyraBoundActionButton (Lyra) ← 입력 장치별 스타일 전환
```

---

## UButton vs UCommonButtonBase

| 기능 | UButton | UCommonButtonBase |
|------|---------|-------------------|
| 마우스 클릭 | ✓ | ✓ |
| 게임패드 선택 | ✗ | ✓ |
| 키보드 선택 | ✗ | ✓ |
| 포커스 상태 스타일 | ✗ | ✓ |
| 입력 장치 변경 감지 | ✗ | ✓ |
| UIAction 연결 | ✗ | ✓ |

게임패드 UI를 지원하려면 반드시 `UCommonButtonBase` (또는 그 자손)를 써야 한다.

---

## ULyraButtonBase

Lyra의 기본 버튼 클래스. `UCommonButtonBase`에서 두 가지를 추가한다.

### 1. 텍스트 오버라이드

```cpp
UPROPERTY(EditAnywhere, Category="Button", meta=(InlineEditConditionToggle))
uint8 bOverride_ButtonText : 1;

UPROPERTY(EditAnywhere, Category="Button", meta=(editcondition="bOverride_ButtonText"))
FText ButtonText;
```

에디터에서 버튼마다 텍스트를 다르게 설정할 수 있다.

### 2. 입력 장치별 스타일 Blueprint 이벤트

```cpp
// UCommonButtonBase 오버라이드
virtual void OnInputMethodChanged(ECommonInputType CurrentInputType) override;
```

내부에서 `UpdateButtonStyle()` Blueprint 이벤트를 호출한다.  
Blueprint에서 `UpdateButtonStyle` 이벤트를 구현해 장치별 비주얼을 변경한다.

---

## ULyraBoundActionButton — 입력 장치별 스타일 에셋

UIAction에 자동으로 연결되는 버튼. 장치가 바뀌면 스타일 에셋 자체를 교체한다.

```cpp
// 에디터에서 설정
UPROPERTY(EditAnywhere, Category = "Styles")
TSubclassOf<UCommonButtonStyle> KeyboardStyle;   // 키보드/마우스일 때

UPROPERTY(EditAnywhere, Category = "Styles")
TSubclassOf<UCommonButtonStyle> GamepadStyle;    // 게임패드일 때

UPROPERTY(EditAnywhere, Category = "Styles")
TSubclassOf<UCommonButtonStyle> TouchStyle;      // 터치일 때
```

### 장치 감지 → 스타일 교체 흐름

```cpp
void ULyraBoundActionButton::NativeConstruct()
{
    Super::NativeConstruct();

    // 입력 서브시스템의 장치 변경 이벤트 구독
    InputSubsystem->OnInputMethodChangedNative.AddUObject(
        this, &ThisClass::HandleInputMethodChanged);

    // 현재 장치 상태 즉시 반영
    HandleInputMethodChanged(InputSubsystem->GetCurrentInputType());
}

void ULyraBoundActionButton::HandleInputMethodChanged(ECommonInputType NewInputMethod)
{
    TSubclassOf<UCommonButtonStyle> NewStyle = nullptr;

    if (NewInputMethod == ECommonInputType::Gamepad)       NewStyle = GamepadStyle;
    else if (NewInputMethod == ECommonInputType::Touch)    NewStyle = TouchStyle;
    else                                                   NewStyle = KeyboardStyle;

    if (NewStyle)
        SetStyle(NewStyle);  // CommonButtonBase API로 스타일 교체
}
```

---

## UCommonButtonStyle

버튼의 각 상태(Normal/Hovered/Focused/Pressed/Disabled)별 비주얼을 정의하는 에셋.

```
UCommonButtonStyle (DataAsset)
    ├─ Normal 상태: 브러시, 텍스트 스타일
    ├─ Hovered 상태: 브러시, 텍스트 스타일
    ├─ Focused 상태: 브러시, 텍스트 스타일  ← 게임패드 포커스 비주얼
    ├─ Pressed 상태: 브러시, 텍스트 스타일
    └─ Disabled 상태: 브러시, 텍스트 스타일
```

`LyraBoundActionButton`은 장치가 바뀔 때 Style 에셋 자체를 교체한다.  
→ 게임패드 연결 시 게임패드 전용 폰트/색상/크기로 완전히 변경 가능.
