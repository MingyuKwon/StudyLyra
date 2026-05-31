# 입력 장치 감지 — UCommonInputSubsystem

> 관련 소스: `UI/Common/LyraBoundActionButton.cpp`,  
>             `UI/Foundation/LyraActionWidget.h/cpp`,  
>             `UI/LyraGameViewportClient.cpp`

---

## UCommonInputSubsystem

현재 플레이어가 어떤 입력 장치를 사용하고 있는지 추적하는 서브시스템.  
`LocalPlayer` 서브시스템이므로 플레이어별로 독립적으로 존재한다.

```cpp
UCommonInputSubsystem* InputSubsystem = GetInputSubsystem();  // UWidget에서 접근 가능

// 현재 입력 장치 종류
ECommonInputType Type = InputSubsystem->GetCurrentInputType();
// → ECommonInputType::MouseAndKeyboard
// → ECommonInputType::Gamepad
// → ECommonInputType::Touch

// 현재 게임패드 이름 (장치 식별용)
FName GamepadName = InputSubsystem->GetCurrentGamepadName();
// → "Generic", "XboxOne", "PS4" 등
```

---

## 장치 변경 감지

```cpp
// 장치 변경 이벤트 구독 (C++)
InputSubsystem->OnInputMethodChangedNative.AddUObject(
    this, &ThisClass::HandleInputMethodChanged);

// 콜백
void HandleInputMethodChanged(ECommonInputType NewInputType)
{
    if (NewInputType == ECommonInputType::Gamepad)
    {
        // 게임패드 UI로 전환
    }
    else
    {
        // 키보드/마우스 UI로 전환
    }
}
```

이 이벤트를 이용해 `ULyraBoundActionButton`이 버튼 스타일을 자동 교체하고,  
`ULyraActionWidget`이 버튼 아이콘을 자동 갱신한다.

---

## ULyraActionWidget — 버튼 아이콘 자동 갱신

```cpp
// LyraActionWidget.cpp
FSlateBrush ULyraActionWidget::GetIcon() const
{
    if (AssociatedInputAction)
    {
        // 1. 이 InputAction에 현재 매핑된 키 목록 조회 (리맵핑 반영)
        TArray<FKey> BoundKeys =
            EnhancedInputSubsystem->QueryKeysMappedToAction(AssociatedInputAction);

        // 2. 현재 입력 장치 + 게임패드 종류에 맞는 아이콘 브러시 획득
        FSlateBrush Brush;
        if (!BoundKeys.IsEmpty() &&
            UCommonInputPlatformSettings::Get()->TryGetInputBrush(
                Brush,
                BoundKeys[0],
                CommonInputSubsystem->GetCurrentInputType(),
                CommonInputSubsystem->GetCurrentGamepadName()))
        {
            return Brush;
        }
    }

    return Super::GetIcon();  // 못 찾으면 DataTable 기본값 반환
}
```

### 아이콘 자동 갱신이 처리하는 두 가지 상황

| 상황 | 결과 |
|------|------|
| 게임패드 연결 | 키보드 키 이미지 → 게임패드 버튼 이미지로 자동 교체 |
| 플레이어가 키 리맵핑 | 기본 키 이미지 → 변경된 키 이미지로 자동 반영 |

---

## UCommonInputPlatformSettings — 플랫폼별 아이콘 에셋

장치 종류 + 게임패드 이름 + 키 → 아이콘 브러시 를 매핑하는 설정.  
프로젝트 세팅 → Common Input Settings → Controller Data에서 등록한다.

```
UCommonInputBaseControllerData (각 컨트롤러 종류별)
    ├─ InputType: Gamepad
    ├─ GamepadName: "XboxOne"
    ├─ ControllerButtonMappingTable  ← 키 → 아이콘 텍스처 매핑 DataTable
    └─ GamepadDisplayName: "Xbox"
```

`TryGetInputBrush()`는 이 DataTable을 조회해서 해당 키의 아이콘을 반환한다.

---

## ULyraGameViewportClient — 커서 처리

플랫폼 트레잇 태그로 소프트웨어 커서 사용 여부를 결정한다.

```cpp
void ULyraGameViewportClient::Init(...)
{
    Super::Init(...);

    // "Platform.Trait.Input.HardwareCursor" 태그가 있으면 OS 커서 사용
    const bool UseHardwareCursor =
        ICommonUIModule::GetSettings().GetPlatformTraits()
            .HasTag(TAG_Platform_Trait_Input_HardwareCursor);

    // false면 UMG 소프트웨어 커서 위젯 사용 (콘솔/모바일)
    SetUseSoftwareCursorWidgets(!UseHardwareCursor);
}
```

| 플랫폼 | HardwareCursor 태그 | 결과 |
|--------|---------------------|------|
| PC | 있음 | OS 하드웨어 커서 |
| 콘솔 | 없음 | UMG 소프트웨어 커서 위젯 |
| 모바일 | 없음 | UMG 소프트웨어 커서 위젯 |

---

## 전체 장치 감지 흐름

```
플레이어가 게임패드 스틱을 움직임
    └─ CommonUI가 입력 감지
            └─ UCommonInputSubsystem::CurrentInputType 갱신
            └─ OnInputMethodChangedNative 브로드캐스트

    구독 중인 위젯들이 각자 반응:
    ├─ ULyraBoundActionButton → 스타일 에셋 교체
    ├─ ULyraButtonBase       → UpdateButtonStyle() BP 이벤트 호출
    └─ ULyraActionWidget     → GetIcon() 재호출 → 게임패드 아이콘 반환
```
