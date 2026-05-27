# 키 바인딩 변경 (런타임 리맵핑)

> 출처: `Input/LyraInputUserSettings.h`, `Settings/CustomSettings/LyraSettingKeyboardInput.h/cpp`,  
>        `Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.h`,  
>        `Settings/LyraGameSettingRegistry_MouseAndKeyboard.cpp`

---

## 전체 흐름

```
[설정 UI 생성]
InitializeMouseAndKeyboardSettings()
    └─ EnhancedInputUserSettings의 모든 프로필 순회
            └─ 프로필별 FKeyMappingRow 순회
                    └─ ULyraSettingKeyboardInput 생성 (항목 1개 = 액션 1개)

[유저 키 변경]
ULyraSettingsListEntrySetting_KeyboardInput  (위젯)
    └─ Button_PrimaryKey 클릭
            └─ PressAnyKeyPanel 표시 ("키를 누르세요")
            └─ 선택된 키가 이미 사용 중 → KeyAlreadyBoundWarning 표시
            └─ 확정 → ULyraSettingKeyboardInput::ChangeBinding()

[실제 저장]
ULyraSettingKeyboardInput::ChangeBinding()
    └─ UEnhancedInputUserSettings::MapPlayerKey(Args, FailureReason)
            └─ ULyraInputUserSettings::ApplySettings()
                    └─ EnhancedInput 서브시스템에 변경 반영

[취소/복원]
    ├─ RestoreToInitial() → 설정 화면 열었을 때 상태로 롤백
    └─ ResetToDefault()  → 기본값으로 초기화
                            → Settings->ResetAllPlayerKeysInRow()
```

---

## 데이터 계층

```
UEnhancedInputUserSettings (ULyraInputUserSettings)
    └─ TMap<FString, UEnhancedPlayerMappableKeyProfile>  GetAllAvailableKeyProfiles()
            └─ UEnhancedPlayerMappableKeyProfile
                    └─ TMap<FName, FKeyMappingRow>  GetPlayerMappingRows()
                            └─ FKeyMappingRow
                                    └─ TSet<FPlayerKeyMapping>  Mappings
                                            ├─ GetMappingName()    ← 액션 이름
                                            ├─ GetDisplayName()   ← 표시 이름
                                            ├─ GetDisplayCategory() ← 카테고리
                                            ├─ GetSlot()          ← Primary / Secondary
                                            ├─ GetCurrentKey()    ← 현재 할당된 키
                                            └─ IsCustomized()     ← 기본값에서 변경됐는지
```

`UEnhancedPlayerMappableKeyProfile` — 키 프로필 단위 (예: "Default Profile").  
여러 프로필을 정의해 빠른 프리셋 전환을 구현할 수 있다.

---

## ULyraSettingKeyboardInput — 핵심 API

```cpp
// 초기화 — 프로필 + 매핑 행 + 필터 옵션으로 설정 항목 1개 생성
void InitializeInputData(Profile, MappingData, QueryOptions);

// 특정 슬롯의 현재 키 텍스트 반환 (UI 표시용)
FText GetKeyTextFromSlot(EPlayerMappableKeySlot InSlot);

// 키 변경 — 게임패드 키는 이 화면에서 거부 (return false)
bool ChangeBinding(int32 InKeyBindSlot, FKey NewKey);

// 같은 키에 바인딩된 다른 액션 이름들 반환 (중복 경고용)
void GetAllMappedActionsFromKey(int32 InKeyBindSlot, FKey Key, TArray<FName>& Out);

// 기본값에서 변경됐는지 여부 (UI에서 * 표시 등)
bool IsMappingCustomized() const;
```

### ChangeBinding 내부

```cpp
bool ULyraSettingKeyboardInput::ChangeBinding(int32 InKeyBindSlot, FKey NewKey)
{
    // 게임패드 키는 이 화면(KBM)에서 변경 불가
    if (!NewKey.IsGamepadKey())
    {
        FMapPlayerKeyArgs Args = {};
        Args.MappingName = ActionMappingName;
        Args.Slot = (EPlayerMappableKeySlot)(InKeyBindSlot);
        Args.NewKey = NewKey;
        // Args.ProfileId, Args.HardwareDeviceId 로 더 구체적으로 지정도 가능

        FGameplayTagContainer FailureReason;
        Settings->MapPlayerKey(Args, FailureReason);
        NotifySettingChanged(EGameSettingChangeReason::Change);
        return true;
    }
    return false;  // 게임패드 키 → 거부
}
```

---

## 설정 UI 위젯 계층

```
ULyraSettingsListEntrySetting_KeyboardInput  (항목 위젯, Blueprint에서 상속)
    ├─ Button_PrimaryKey   — 첫 번째 키 버튼
    ├─ Button_SecondaryKey — 두 번째 키 버튼
    ├─ Button_Clear        — 현재 키 지우기
    └─ Button_ResetToDefault — 기본값 복원
```

버튼 클릭 흐름:

```
Button_PrimaryKey 클릭
    └─ HandlePrimaryKeyClicked()
            └─ PressAnyKeyPanel 생성 & 표시 ("키를 누르세요")
            └─ 키 선택됨 → HandlePrimaryKeySelected(Key, Panel)
                    ├─ 중복 확인: GetAllMappedActionsFromKey()
                    │   └─ 중복 있음 → KeyAlreadyBoundWarning 표시
                    │           └─ 확인 클릭 → HandlePrimaryDuplicateKeySelected()
                    └─ 중복 없음 → ChangeBinding(Slot, Key)
```

---

## 키 바인딩 등록 조건 — KBM 전용 필터

설정 화면 생성 시 키보드 키만 표시하도록 필터를 걸어 `Options.KeyToMatch = EKeys::W`로 기준 키를 지정한다.  
`bMatchBasicKeyTypes = true` → W와 같은 "기본 키" 타입만 통과.

```cpp
// LyraGameSettingRegistry_MouseAndKeyboard.cpp
FPlayerMappableKeyQueryOptions Options = {};
Options.KeyToMatch = EKeys::W;      // 키보드 키 기준
Options.bMatchBasicKeyTypes = true; // 같은 종류(키보드)만 매칭
```

게임패드 키 바인딩을 별도 화면에서 처리하려면 `EKeys::Gamepad_LeftX` 등으로 기준을 바꾸면 된다.

---

## ULyraPlayerMappableKeySettings — 액션별 메타데이터

```cpp
UCLASS()
class ULyraPlayerMappableKeySettings : public UPlayerMappableKeySettings
{
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Settings")
    FText Tooltip = FText::GetEmpty();  // 설정 화면 툴팁

    const FText& GetTooltipText() const;
};
```

`InputAction` 에셋의 `PlayerMappableKeySettings` 프로퍼티에 `ULyraPlayerMappableKeySettings` 클래스를 지정해 액션별 툴팁을 정의한다.
