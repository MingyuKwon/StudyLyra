# 01. 전체 아키텍처 — 왜 이렇게 설계했는가

> 출처: 엔진 `UserSettings/EnhancedInputUserSettings.h`, Lyra `Input/LyraInputUserSettings.h`,  
>        `Character/LyraHeroComponent.cpp`, `Settings/LyraGameSettingRegistry_MouseAndKeyboard.cpp`

---

## 한 줄 요약

Lyra의 키 바인딩 시스템은 **"어디에 저장하냐", "어떻게 보여주냐", "어떻게 반영하냐"**를  
각각 독립된 계층으로 분리한 3-레이어 설계다.

---

## 계층 분리 설계 의도

### 왜 3계층으로 나눴는가

| 계층 | 담당 | 분리 이유 |
|------|------|-----------|
| **데이터 계층** (EnhancedInputUserSettings) | 키 값 보관·직렬화 | 게임 로직과 UI에 독립적으로 저장 |
| **설정 레지스트리** (GameSettingRegistry) | UI 항목 생성 | 설정 화면의 구성을 코드로 선언 |
| **적용 계층** (ApplySettings) | IMC 런타임 패치 | 변경이 즉시 반영되는 시점을 명시적으로 제어 |

이 분리 덕분에:
- 키를 바꿔도 `ApplySettings()` 전까지 게임에 영향 없음 → **취소 가능한 편집**
- 저장은 `SaveSettings()` 시점에만 디스크에 씀 → **명시적 커밋**
- UI 위젯은 `UGameSettingValue` 프레임워크에만 의존 → **설정 화면 독립성**

---

## 전체 데이터 흐름

```
[① 설계 단계 — 에디터]
IMC (InputMappingContext)
    └─ FEnhancedActionKeyMapping
            ├─ Action: UInputAction (IA_Jump)
            ├─ Key: FKey("SpaceBar")
            └─ Settings: ULyraPlayerMappableKeySettings  ← 이게 있어야 리맵 가능
                    └─ Tooltip: "캐릭터가 점프합니다"

ULyraPawnData
    └─ DefaultMappingContexts[]
            └─ IMC_ShooterGame_KBM (bRegisterWithSettings = true)

[② 런타임 등록 — 캐릭터 스폰 시]
ULyraHeroComponent::InitializePlayerInput()
    └─ Settings->RegisterInputMappingContext(IMC)
            └─ IMC의 모든 PlayerMappable 키가 Profile에 FPlayerKeyMapping으로 등록됨

[③ 설정 화면 열기 — UI 초기화 시]
ULyraGameSettingRegistry::InitializeMouseAndKeyboardSettings()
    └─ Profile의 모든 FKeyMappingRow를 순회
            └─ 각 Row마다 ULyraSettingKeyboardInput 생성

[④ 사용자 키 변경 — 런타임]
버튼 클릭 → PressAnyKey 모달 → 키 캡처
    └─ ULyraSettingKeyboardInput::ChangeBinding()
            └─ Settings->MapPlayerKey()  [메모리만 변경]

[⑤ 적용]
ApplySettings()  [메모리 → EnhancedInput 런타임 오버라이드]

[⑥ 저장]
SaveSettings()  [메모리 → Saved/SaveGames/*.sav]

[⑦ 복원 — 다음 게임 시작]
ULyraLocalPlayer가 SharedSettings 로드
    └─ ULyraInputUserSettings::Serialize() 역직렬화
            └─ 저장된 CurrentKey들이 복원됨
```

---

## 클래스 계층도 (상속 관계)

```
UObject
└─ UEnhancedInputUserSettings      [엔진] 키 프로필 전체 관리, MapPlayerKey, ApplySettings
    └─ ULyraInputUserSettings       [Lyra] ApplySettings 오버라이드, 저장 직렬화 진입점

UObject
└─ UEnhancedPlayerMappableKeyProfile  [엔진] FKeyMappingRow 컨테이너, GetMappingNamesForKey
    └─ ULyraPlayerMappableKeyProfile   [Lyra] EquipProfile/UnEquipProfile 훅

UObject
└─ UPlayerMappableKeySettings       [엔진] 리맵 가능 키의 메타데이터 베이스
    └─ ULyraPlayerMappableKeySettings [Lyra] Tooltip 필드 추가

UGameSettingValue                   [GameSettings 플러그인] 설정 값 베이스
└─ ULyraSettingKeyboardInput        [Lyra] 액션 1개의 키 바인딩 설정

UGameSettingListEntry_Setting       [GameSettings 플러그인] 리스트 UI 항목 베이스
└─ ULyraSettingsListEntrySetting_KeyboardInput  [Lyra] 키 바인딩 UI 항목
```

---

## 엔진이 제공하는 것 vs Lyra가 추가한 것

### 엔진 제공 (`EnhancedInput` 플러그인)

- `UEnhancedInputUserSettings` — 키 프로필 CRUD, `MapPlayerKey()`, `ApplySettings()`
- `UEnhancedPlayerMappableKeyProfile` — 프로필별 `FKeyMappingRow` 관리
- `FKeyMappingRow`, `FPlayerKeyMapping` — 데이터 구조
- `FPlayerMappableKeyQueryOptions` — 키 필터링 (Keyboard/Gamepad 분리 등)

### Lyra 추가

- `ULyraInputUserSettings` — `ApplySettings()` 훅 (확장 포인트), SaveGame 직렬화 연결
- `ULyraPlayerMappableKeyProfile` — `EquipProfile()`/`UnEquipProfile()` 훅 (현재 비어있음)
- `ULyraPlayerMappableKeySettings` — `Tooltip` 필드 (설정 화면 툴팁 표시)
- `ULyraSettingKeyboardInput` — `UGameSettingValue` 어댑터 (ChangeBinding, ResetToDefault 등)
- `ULyraSettingsListEntrySetting_KeyboardInput` — 실제 UI 위젯 (버튼 4개 + 모달 연동)
- `ULyraGameSettingRegistry::InitializeMouseAndKeyboardSettings()` — UI 항목 자동 생성 로직

---

## "리맵 가능한 키"가 되는 조건

IMC 안의 키 매핑 하나가 설정 화면에 나타나려면 두 가지가 필요하다.

```
조건 1. IMC의 FEnhancedActionKeyMapping.Settings에
        UPlayerMappableKeySettings (또는 그 서브클래스) 가 지정되어 있어야 함
        → 이 필드가 없으면 RegisterInputMappingContext()가 이 키를 무시함

조건 2. ULyraHeroComponent::InitializePlayerInput()에서
        FInputMappingContextAndPriority.bRegisterWithSettings == true 인 IMC여야 함
        → false이면 게임에는 적용되지만 설정 화면에 나타나지 않음
```

에디터에서 IMC를 열어보면 각 키 매핑에 "Player Mappable Key Settings" 칸이 있다.  
거기에 `ULyraPlayerMappableKeySettings`를 지정하고 DisplayName/Category/Tooltip을 채우면  
해당 키가 설정 화면에 항목으로 등록된다.

---

## 관련 파일 경로

| 파일 | 역할 |
|------|------|
| `Source/LyraGame/Input/LyraInputUserSettings.h/cpp` | 저장 계층 진입점 |
| `Source/LyraGame/Input/LyraPlayerMappableKeyProfile.h/cpp` | 키 프로필 |
| `Source/LyraGame/Character/LyraHeroComponent.cpp` | IMC 등록 (`InitializePlayerInput`) |
| `Source/LyraGame/Settings/CustomSettings/LyraSettingKeyboardInput.h/cpp` | 설정 값 어댑터 |
| `Source/LyraGame/Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.h/cpp` | UI 위젯 |
| `Source/LyraGame/Settings/LyraGameSettingRegistry_MouseAndKeyboard.cpp` | 레지스트리 초기화 |
