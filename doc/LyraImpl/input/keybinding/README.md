# Lyra 키 바인딩 시스템

> 사용자가 게임 내에서 키를 직접 바꿀 수 있는 **런타임 리맵핑(Runtime Remapping)** 전체 구현 분석.  
> Enhanced Input의 `UEnhancedInputUserSettings` 위에 Lyra가 어떤 레이어를 얹었는지를 계층별로 정리한다.

---

## 시스템 전체 계층 구조

```
┌─────────────────────────────────────────────────────────────────┐
│  [① IMC 등록 계층]                                               │
│  ULyraHeroComponent::InitializePlayerInput()                    │
│      └─ IMC를 Settings에 RegisterInputMappingContext()           │
│         → 리맵 가능한 키 목록을 Settings에 노출                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  [② 데이터 계층]                                                  │
│  UEnhancedInputLocalPlayerSubsystem                             │
│      └─ GetUserSettings() → ULyraInputUserSettings              │
│              └─ GetAllAvailableKeyProfiles()                     │
│                      └─ ULyraPlayerMappableKeyProfile            │
│                              └─ GetPlayerMappingRows()           │
│                                      └─ FKeyMappingRow           │
│                                              └─ FPlayerKeyMapping│
│                                                 .CurrentKey      │
│                                                 .DefaultKey      │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  [③ 설정 레지스트리 계층]                                          │
│  ULyraGameSettingRegistry::InitializeMouseAndKeyboardSettings() │
│      └─ 모든 Profile × MappingRow 순회                           │
│              └─ ULyraSettingKeyboardInput 생성 (액션 1개 = 1개)  │
│                   (UGameSettingValue 상속)                       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  [④ UI 위젯 계층]                                                 │
│  ULyraSettingsListEntrySetting_KeyboardInput                    │
│      ├─ Button_PrimaryKey    → PressAnyKey 모달                  │
│      ├─ Button_SecondaryKey  → PressAnyKey 모달                  │
│      ├─ Button_Clear         → Invalid 키로 즉시 변경             │
│      └─ Button_ResetToDefault → ResetAllPlayerKeysInRow()        │
│                                                                  │
│  UGameSettingPressAnyKey  ← 키 누름 캡처 모달                    │
│  UKeyAlreadyBoundWarning  ← 중복 경고 모달                       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  [⑤ 적용·저장 계층]                                               │
│  MapPlayerKey()     → 메모리 내 CurrentKey 갱신                  │
│  ApplySettings()    → EnhancedInput IMC 런타임 오버라이드        │
│  SaveSettings()     → Saved/SaveGames/*.sav 직렬화               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 문서 목록

| 번호 | 문서 | 핵심 질문 |
|------|------|-----------|
| [00](00_enhanced_input_foundation.md) | Enhanced Input 엔진 기반 | 엔진이 제공하는 것 — RegisterInputMappingContext 실제 동작, 직렬화, MapPlayerKey 상세 |
| [07](game_settings/README.md) | GameSettings 플러그인 기반 | 플러그인이 제공하는 것 — MVC 구조, Value 타입, EditCondition, Registry, 위젯 계층 |
| [01](01_architecture.md) | 전체 아키텍처 | "왜 이렇게 설계했는가?" — 각 계층의 존재 이유 |
| [02](02_data_layer.md) | 데이터 계층 | "키 변경 결과가 어디에 저장되는가?" |
| [03](03_imc_registration.md) | IMC 등록 | "어떤 키가 리맵 가능한가? 어떻게 등록되는가?" |
| [04](04_settings_registry.md) | 설정 레지스트리 | "설정 UI에 항목이 어떻게 생기는가?" |
| [05](05_ui_widget.md) | UI 위젯 계층 | "'키를 누르세요' 감지는 어떻게 동작하는가?" |
| [06](06_apply_and_save.md) | 적용 & 저장 | "변경한 키가 언제 실제 게임에 반영되는가?" |

---

## 핵심 클래스 한눈에 보기

| 클래스 | 역할 | 소속 |
|--------|------|------|
| `ULyraInputUserSettings` | EnhancedInputUserSettings 확장. 직렬화·저장 진입점 | Lyra |
| `ULyraPlayerMappableKeySettings` | 액션별 메타데이터(툴팁). IMC 키 매핑에 부착 | Lyra |
| `ULyraPlayerMappableKeyProfile` | 키 프로필(키 배치 세트). Equip/Unequip 훅 | Lyra |
| `ULyraSettingKeyboardInput` | 액션 1개의 바인딩 설정 값. ChangeBinding 담당 | Lyra |
| `ULyraSettingsListEntrySetting_KeyboardInput` | 설정 화면의 UI 항목 위젯 | Lyra |
| `UEnhancedInputUserSettings` | 키 프로필 관리, MapPlayerKey, ApplySettings | 엔진 |
| `UEnhancedPlayerMappableKeyProfile` | FKeyMappingRow 컨테이너 | 엔진 |
| `FKeyMappingRow` | 액션 1개의 모든 슬롯 매핑 묶음 | 엔진 |
| `FPlayerKeyMapping` | 슬롯 1개의 CurrentKey/DefaultKey | 엔진 |
| `UGameSettingRegistry` | 설정 항목 목록 관리, SaveChanges 진입점 | GameSettings 플러그인 |
| `UGameSettingValue` | 취소 가능한 설정 값 base (StoreInitial/Restore) | GameSettings 플러그인 |
| `UGameSettingListEntryBase` | 설정 항목 위젯 base (IUserObjectListEntry) | GameSettings 플러그인 |
| `UGameSettingPressAnyKey` | 키 캡처 모달 (InputPreProcessor로 원시 키 수신) | GameSettings 플러그인 |
| `UKeyAlreadyBoundWarning` | 중복 경고 모달 (PressAnyKey 서브클래스) | GameSettings 플러그인 |
