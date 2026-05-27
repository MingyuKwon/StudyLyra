# 설정 시스템 아키텍처

> 출처: `Settings/LyraSettingsLocal.h`, `Settings/LyraSettingsShared.h`,  
>        `Input/LyraInputUserSettings.h`, `Settings/LyraGameSettingRegistry.h`

---

## 세 가지 설정 클래스

Lyra의 입력 관련 설정은 목적에 따라 세 클래스로 분리된다.

```
UGameUserSettings (엔진)
    └─ ULyraSettingsLocal          ← 머신 종속 설정 (ini 파일 저장)

ULocalPlayerSaveGame (엔진)
    └─ ULyraSettingsShared         ← 플레이어별 클라우드 설정 (SaveGame 시스템)

UEnhancedInputUserSettings (엔진)
    └─ ULyraInputUserSettings      ← 키 리맵핑 전용
```

### ULyraSettingsLocal

`UGameUserSettings`를 상속. 머신 종속적이라 클라우드에 올리지 않는 설정을 저장한다.

```
입력 관련 항목:
- GetControllerPlatform() / SetControllerPlatform()  ← 컨트롤러 종류 (Xbox/PS 등)
```

싱글톤처럼 `ULyraSettingsLocal::Get()`으로 전역 접근 가능.

### ULyraSettingsShared

`ULocalPlayerSaveGame`을 상속. 플레이어별로 저장되며 클라우드 세이브가 가능하다.  
멀티 유저 환경에서 "유저 A의 설정"이 "유저 B의 설정"에 영향을 주지 않도록 분리.

```
입력 관련 항목:
- 진동 (bForceFeedbackEnabled)
- 트리거 햅틱 (bTriggerHapticsEnabled, TriggerHapticStrength, ...)
- 게임패드 감도 프리셋 (ELyraGamepadSensitivity)
- 게임패드 데드존 (GamepadMoveStickDeadZone, GamepadLookStickDeadZone)
- 축 반전 (InvertVerticalAxis, InvertHorizontalAxis)
- 마우스 감도 (MouseSensitivityX, MouseSensitivityY)
- 조준 배율 (TargetingMultiplier)
```

`AsyncLoadOrCreateSettings()` → 비동기 로드, `SaveSettings()` → 저장.

### ULyraInputUserSettings

`UEnhancedInputUserSettings`를 상속. 키 리맵핑 데이터를 보관한다.  
`ULyraSettingsShared`와 동시에 직렬화되어 클라우드 세이브 호환.

```
역할:
- 플레이어가 바꾼 키 바인딩 저장/복원
- ApplySettings() 오버라이드 → 실제 EnhancedInput에 적용
```

`ULyraPlayerMappableKeySettings` — 액션별 메타데이터(툴팁 텍스트)를 보관.  
InputAction 에셋의 `PlayerMappableKeySettings` 프로퍼티에 연결.

---

## 설정 UI 등록 — ULyraGameSettingRegistry

설정 화면의 항목들은 코드로 직접 생성된다.  
`ULyraGameSettingRegistry`가 탭별로 `UGameSettingCollection` 트리를 만들어 반환한다.

```
ULyraGameSettingRegistry
    ├─ InitializeGamepadSettings()          → 게임패드 탭
    ├─ InitializeMouseAndKeyboardSettings() → 마우스/키보드 탭
    ├─ InitializeAudioSettings()            → 오디오 탭
    └─ InitializeVideoSettings()            → 비디오 탭
```

### 설정 값 타입

| 타입 | 용도 |
|------|------|
| `UGameSettingValueDiscreteDynamic` | 드롭다운 (Bool/Enum/일반) |
| `UGameSettingValueScalarDynamic` | 슬라이더 |
| `ULyraSettingKeyboardInput` | 키 바인딩 (커스텀) |

### GET_SHARED_SETTINGS_FUNCTION_PATH / GET_LOCAL_SETTINGS_FUNCTION_PATH

`DynamicGetter` / `DynamicSetter` 지정 매크로. 설정 값과 `SettingsShared` / `SettingsLocal`의 함수를 연결한다.

```cpp
// 예: 게임패드 진동 설정
Setting->SetDynamicGetter(GET_SHARED_SETTINGS_FUNCTION_PATH(GetForceFeedbackEnabled));
Setting->SetDynamicSetter(GET_SHARED_SETTINGS_FUNCTION_PATH(SetForceFeedbackEnabled));
```

---

## 설정 클래스 접근 경로

```
ULyraLocalPlayer
    ├─ GetSubsystem<UEnhancedInputLocalPlayerSubsystem>()
    │       └─ GetUserSettings()  →  ULyraInputUserSettings (키 리맵핑)
    └─ (SaveGame 로드)            →  ULyraSettingsShared     (감도/데드존/진동)

GetDefault<ULyraSettingsLocal>()  →  ULyraSettingsLocal      (컨트롤러 종류)
```
