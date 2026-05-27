# 게임패드 설정 UI & Input Modifier 연동

> 출처: `Settings/LyraGameSettingRegistry_Gamepad.cpp`,  
>        `Input/LyraInputModifiers.h`, `Input/LyraAimSensitivityData.h`,  
>        `Settings/LyraSettingsShared.h`

---

## 게임패드 설정 화면 항목

`InitializeGamepadSettings()`가 생성하는 `UGameSettingCollection` 트리 구조:

```
Gamepad (탭 루트)
├─ Hardware (하드웨어)
│   ├─ ControllerHardware  — 컨트롤러 종류 선택 (Xbox/PS 등)
│   ├─ GamepadVibration    — 진동 On/Off
│   ├─ InvertVerticalAxis  — 수직 축 반전
│   └─ InvertHorizontalAxis — 수평 축 반전
│
├─ Controls (컨트롤)        ← 키 바인딩 섹션 (현재 비어있음, 향후 확장용)
│
├─ Sensitivity (감도)
│   ├─ LookSensitivityPreset    — 기본 감도 (1~10 단계)
│   └─ LookSensitivityPresetAds — ADS 감도 (1~10 단계)
│
└─ Controller DeadZone (데드존)
    ├─ MoveStickDeadZone  — 좌스틱 데드존 (5%~95%)
    └─ LookStickDeadZone  — 우스틱 데드존 (5%~95%)
```

### 컨트롤러 종류 선택 조건

`UCommonInputPlatformSettings`에서 등록된 `UCommonInputBaseControllerData` 목록을 읽어 드롭다운을 생성한다.  
`CanChangeGamepadType()`이 false이거나 선택지가 1개뿐이면 항목을 숨긴다.

### 감도 프리셋 — ELyraGamepadSensitivity

```cpp
// LyraSettingsShared.h
enum class ELyraGamepadSensitivity : uint8
{
    Slow, SlowPlus, SlowPlusPlus,
    Normal, NormalPlus, NormalPlusPlus,
    Fast, FastPlus, FastPlusPlus,
    Insane       // 총 10단계 (Invalid, MAX 제외)
};
```

저장 위치: `ULyraSettingsShared`  
적용 경로: 아래 Input Modifier에서 float 값으로 변환해 스틱 입력에 곱한다.

---

## Input Modifier 3종 — 설정 → 실제 입력에 반영

게임패드 설정 값은 `UInputAction` 에셋에 붙은 **InputModifier**를 통해 런타임 입력에 실시간 적용된다.

```
게임패드 스틱 입력값
    │
    ├─ ULyraInputModifierDeadZone
    │       SharedSettings.GetGamepadMoveStickDeadZone() or GetGamepadLookStickDeadZone()
    │       → 데드존 영역 내 입력 제거 (Radial 방식)
    │
    ├─ ULyraInputModifierGamepadSensitivity
    │       SharedSettings.GetGamepadLookSensitivityPreset()
    │       → LyraAimSensitivityData.SensitivtyEnumToFloat(preset)
    │       → 결과 float을 입력값에 곱함
    │
    └─ ULyraInputModifierAimInversion
            SharedSettings.GetInvertVerticalAxis() or GetInvertHorizontalAxis()
            → true면 해당 축 값 반전
            → 최종 AddControllerPitchInput / YawInput으로 전달
```

### ULyraInputModifierDeadZone

```cpp
UPROPERTY(EditInstanceOnly)
EDeadzoneStick DeadzoneStick;  // MoveStick=좌스틱, LookStick=우스틱
EDeadZoneType Type = EDeadZoneType::Radial;
float UpperThreshold = 1.0f;
```

`DeadzoneStick` 값에 따라 `SharedSettings`의 좌스틱/우스틱 데드존 값을 자동 선택.

### ULyraInputModifierGamepadSensitivity

```cpp
UPROPERTY(EditAnywhere)
ELyraTargetingType TargetingType;  // Normal=일반 / ADS=조준 중

UPROPERTY(EditAnywhere)
TObjectPtr<const ULyraAimSensitivityData> SensitivityLevelTable;
```

`ULyraAimSensitivityData` — `ELyraGamepadSensitivity → float` 매핑 DataAsset.  
에디터에서 각 단계별 실제 배율값을 지정.

### ULyraSettingBasedScalar (마우스 감도용)

```cpp
UPROPERTY(EditInstanceOnly)
FName XAxisScalarSettingName;  // 예: "MouseSensitivityX"
FName YAxisScalarSettingName;
```

`ULyraSettingsShared`의 프로퍼티 이름(문자열)으로 값을 런타임에 조회.  
리플렉션(FProperty)을 이용해 값을 읽으므로 새 항목을 추가해도 이 Modifier를 재사용할 수 있다.

---

## 플랫폼 Trait Tag

게임패드 기능의 활성화 여부는 **플랫폼 트레잇 태그**로 제어된다.

```
Platform.Trait.Input.SupportsGamepad        ← 게임패드 지원 여부
Platform.Trait.Input.SupportsTriggerHaptics ← 트리거 햅틱 지원 여부
Platform.Trait.Input.HardwareCursor         ← 하드웨어 커서 사용 여부
```

`ICommonUIModule::GetSettings().GetPlatformTraits().HasTag(Tag)` 로 확인.  
`LyraGameViewportClient`가 초기화 시 이 태그로 소프트웨어 커서 사용 여부를 결정한다.
