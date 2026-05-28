# 04. 설정 레지스트리 — 설정 화면 항목이 어떻게 생기는가

> 출처: `Source/LyraGame/Settings/LyraGameSettingRegistry_MouseAndKeyboard.cpp`,  
>        `Source/LyraGame/Settings/CustomSettings/LyraSettingKeyboardInput.h/cpp`,  
>        `Source/LyraGame/Settings/LyraGameSettingRegistry.h`

---

## 핵심 질문

> "설정 화면을 열었을 때 키 바인딩 목록이 어떻게 동적으로 생성되는가?"

---

## 전체 흐름

```
설정 화면 열림
    └─ ULyraGameSettingRegistry::OnInitialize()
            └─ InitializeMouseAndKeyboardSettings()
                    └─ EnhancedInputUserSettings에서 모든 Profile 순회
                            └─ 각 Profile의 모든 FKeyMappingRow 순회
                                    └─ 각 Row마다 ULyraSettingKeyboardInput 생성
                                            └─ InitializeInputData(Profile, Row, Options)
```

---

## `ULyraGameSettingRegistry` 역할

```cpp
// LyraGameSettingRegistry.h
UCLASS()
class ULyraGameSettingRegistry : public UGameSettingRegistry
{
    static ULyraGameSettingRegistry* Get(ULyraLocalPlayer* InLocalPlayer);
    virtual void SaveChanges() override;
    virtual void OnInitialize(ULocalPlayer* InLocalPlayer) override;

    UGameSettingCollection* InitializeMouseAndKeyboardSettings(ULyraLocalPlayer*);
    UGameSettingCollection* InitializeGamepadSettings(ULyraLocalPlayer*);
    // ... Video, Audio, Gameplay 등
};
```

**역할**: 게임의 모든 설정 항목을 코드로 선언하는 중앙 레지스트리.  
각 `Initialize*` 함수가 하나의 설정 탭(화면)을 구성한다.

**`SaveChanges()`**: 설정 화면에서 "적용" 또는 닫기 시 호출.  
`ULyraSettingsShared::SaveSettings()` + `ULyraSettingsLocal::SaveSettings()`를 트리거한다.

---

## `InitializeMouseAndKeyboardSettings()` 상세 분석

```cpp
// LyraGameSettingRegistry_MouseAndKeyboard.cpp
UGameSettingCollection* ULyraGameSettingRegistry::InitializeMouseAndKeyboardSettings(
    ULyraLocalPlayer* InLocalPlayer)
{
    // 플랫폼이 키보드+마우스를 지원하는지 조건 생성
    const TSharedRef<FWhenCondition> WhenPlatformSupportsMouseAndKeyboard =
        MakeShared<FWhenCondition>([](const ULocalPlayer*, FGameSettingEditableState& State)
        {
            const UCommonInputPlatformSettings* PlatformInput =
                UPlatformSettingsManager::Get().GetSettingsForPlatform<UCommonInputPlatformSettings>();
            if (!PlatformInput->SupportsInputType(ECommonInputType::MouseAndKeyboard))
                State.Kill(TEXT("Platform does not support mouse and keyboard"));
        });

    // [A] 마우스 감도 섹션 (고정 항목들) ...

    // [B] 키 바인딩 섹션 (동적 생성)
    {
        const UEnhancedInputLocalPlayerSubsystem* EISubsystem =
            InLocalPlayer->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
        const UEnhancedInputUserSettings* UserSettings = EISubsystem->GetUserSettings();

        // 카테고리별로 UGameSettingCollection을 동적 생성하는 헬퍼 람다
        TMap<FString, UGameSettingCollection*> CategoryToSettingCollection;
        auto GetOrCreateSettingCollection = [&](FText DisplayCategory) -> UGameSettingCollection*
        {
            // DisplayCategory 텍스트를 키로 컬렉션이 없으면 새로 만들어 Screen에 추가
            // ...
        };

        // 모든 프로필 × 모든 Row 순회
        for (const auto& ProfilePair : UserSettings->GetAllAvailableKeyProfiles())
        {
            const UEnhancedPlayerMappableKeyProfile* Profile = ProfilePair.Value;

            for (const auto& RowPair : Profile->GetPlayerMappingRows())
            {
                if (RowPair.Value.HasAnyMappings())
                {
                    // 키보드 키만 필터링 (W키 기준으로 BasicKeyType 매칭)
                    FPlayerMappableKeyQueryOptions Options = {};
                    Options.KeyToMatch = EKeys::W;
                    Options.bMatchBasicKeyTypes = true;

                    // 카테고리 텍스트로 섹션 구분
                    const FText& Category = RowPair.Value.Mappings.begin()->GetDisplayCategory();
                    UGameSettingCollection* Collection = GetOrCreateSettingCollection(Category);

                    // 액션 1개 = 설정 항목 1개
                    ULyraSettingKeyboardInput* InputBinding = NewObject<ULyraSettingKeyboardInput>();
                    InputBinding->InitializeInputData(Profile, RowPair.Value, Options);
                    InputBinding->AddEditCondition(WhenPlatformSupportsMouseAndKeyboard);

                    Collection->AddSetting(InputBinding);
                }
            }
        }
    }
}
```

**핵심 포인트 3가지**:

1. **동적 생성**: 에디터에서 IMC에 추가한 키 매핑이 자동으로 설정 항목이 된다. 코드 수정 불필요.
2. **카테고리 자동 분류**: `DisplayCategory` 텍스트로 섹션이 자동 생성·분류된다.
3. **플랫폼 필터**: `WhenPlatformSupportsMouseAndKeyboard` 조건으로 모바일 등에서 자동 비활성화.

---

## `FPlayerMappableKeyQueryOptions` — 키보드/게임패드 분리

```cpp
FPlayerMappableKeyQueryOptions Options = {};
Options.KeyToMatch = EKeys::W;       // W키를 기준으로
Options.bMatchBasicKeyTypes = true;  // 같은 "타입"의 키만 매칭
```

`EKeys::W`는 키보드 키다. `bMatchBasicKeyTypes = true`이면  
"W와 같은 타입(키보드)"의 키들만 이 설정 항목에 포함된다.  
게임패드 키(`Gamepad_FaceButton_Bottom` 등)는 다른 탭에서 별도로 처리된다.

**실용적 의미**:  
한 액션이 키보드 Primary + 키보드 Secondary + 게임패드 등 여러 슬롯을 가질 때,  
마우스&키보드 탭에서는 키보드 슬롯만, 게임패드 탭에서는 게임패드 슬롯만 표시한다.

---

## `ULyraSettingKeyboardInput` — 설정 값 어댑터

```cpp
// LyraSettingKeyboardInput.h
UCLASS()
class ULyraSettingKeyboardInput : public UGameSettingValue
{
    // 초기화
    void InitializeInputData(
        const UEnhancedPlayerMappableKeyProfile* KeyProfile,
        const FKeyMappingRow& MappingData,
        const FPlayerMappableKeyQueryOptions& QueryOptions);

    // 현재 키 텍스트 ("E", "SpaceBar" 등)
    FText GetKeyTextFromSlot(EPlayerMappableKeySlot InSlot) const;

    // 키 변경 (메모리만)
    bool ChangeBinding(int32 InKeyBindSlot, FKey NewKey);

    // 특정 키가 이미 어느 액션에 바인딩되어 있는지 조회
    void GetAllMappedActionsFromKey(int32 InKeyBindSlot, FKey Key, TArray<FName>& OutActionNames) const;

    // 커스터마이징 여부 (기본값에서 바뀌었는가)
    bool IsMappingCustomized() const;

    // 기본값으로 리셋
    virtual void ResetToDefault() override;

    // 설정 화면 열 때 초기 상태 저장 (취소용)
    virtual void StoreInitial() override;

    // "취소" — 설정 화면 열기 전 상태로 복원
    virtual void RestoreToInitial() override;
};
```

**`UGameSettingValue`를 상속한 이유**:  
`UGameSettingRegistry`의 `UGameSettingCollection`에 추가하려면 `UGameSetting`의 서브클래스여야 한다.  
`UGameSettingValue`가 "값이 있는 설정 항목"의 기본 클래스다.

**`InitializeInputData()` 동작**:

```cpp
void ULyraSettingKeyboardInput::InitializeInputData(
    const UEnhancedPlayerMappableKeyProfile* KeyProfile,
    const FKeyMappingRow& MappingData,
    const FPlayerMappableKeyQueryOptions& InQueryOptions)
{
    ProfileIdentifier = KeyProfile->GetProfileIdString();
    QueryOptions = InQueryOptions;

    for (const FPlayerKeyMapping& Mapping : MappingData.Mappings)
    {
        if (!KeyProfile->DoesMappingPassQueryOptions(Mapping, QueryOptions))
            continue;  // 키보드/게임패드 필터

        ActionMappingName = Mapping.GetMappingName();
        InitialKeyMappings.Add(Mapping.GetSlot(), Mapping.GetCurrentKey());

        if (!Mapping.GetDisplayName().IsEmpty())
            SetDisplayName(Mapping.GetDisplayName());
    }
}
```

**저장하는 것**:
- `ActionMappingName` — `FName`. `MapPlayerKey()` 호출 시 사용
- `ProfileIdentifier` — 어느 프로필의 설정인지
- `InitialKeyMappings` — `StoreInitial()`/`RestoreToInitial()` 에서 사용

---

## `ChangeBinding()` 상세

```cpp
bool ULyraSettingKeyboardInput::ChangeBinding(int32 InKeyBindSlot, FKey NewKey)
{
    if (!NewKey.IsGamepadKey())  // 키보드 설정 탭에서는 게임패드 키 거부
    {
        FMapPlayerKeyArgs Args = {};
        Args.MappingName = ActionMappingName;
        Args.Slot = (EPlayerMappableKeySlot)(static_cast<uint8>(InKeyBindSlot));
        Args.NewKey = NewKey;
        // Args.ProfileId, Args.HardwareDeviceId — 특정 프로필/기기 한정 가능

        FGameplayTagContainer FailureReason;
        Settings->MapPlayerKey(Args, FailureReason);

        NotifySettingChanged(EGameSettingChangeReason::Change);  // UI 갱신 트리거
        return true;
    }
    return false;
}
```

**`NotifySettingChanged()`**: `UGameSettingValue`의 이벤트. UI 위젯이 구독하여 버튼 텍스트를 갱신한다.

---

## `ResetToDefault()` vs `RestoreToInitial()` 차이

| 함수 | 동작 | 사용 시점 |
|------|------|-----------|
| `ResetToDefault()` | IMC 원래 키(DefaultKey)로 복원 | "기본값으로 리셋" 버튼 |
| `StoreInitial()` | 설정 화면 열기 시점의 키를 저장 | 설정 화면 초기화 시 |
| `RestoreToInitial()` | `StoreInitial()` 시점의 키로 복원 | "취소" 버튼 또는 ESC |

```
설정 화면 열림
    └─ StoreInitial()  ← 현재 상태 스냅샷

키 변경 (여러 번)
    └─ ChangeBinding() × N

"취소" 선택
    └─ RestoreToInitial()  ← 스냅샷으로 되돌림

"기본값 리셋" 선택
    └─ ResetToDefault()  ← IMC 원래 키로 되돌림
```

---

## `GetOrCreateSettingCollection` — 카테고리 자동 분류 구현

```cpp
TMap<FString, UGameSettingCollection*> CategoryToSettingCollection;

auto GetOrCreateSettingCollection = [&](FText DisplayCategory) -> UGameSettingCollection*
{
    if (DisplayCategory.IsEmpty())
        DisplayCategory = NSLOCTEXT("LyraInputSettings", "LyraInputDefaults", "Default Experiences");

    FString Key = DisplayCategory.ToString();

    if (UGameSettingCollection** Existing = CategoryToSettingCollection.Find(Key))
        return *Existing;

    UGameSettingCollection* NewCollection = NewObject<UGameSettingCollection>();
    NewCollection->SetDevName(FName(Key));
    NewCollection->SetDisplayName(DisplayCategory);
    Screen->AddSetting(NewCollection);
    CategoryToSettingCollection.Add(Key, NewCollection);

    return NewCollection;
};
```

**결과**: IMC의 키 매핑에 `DisplayCategory = "이동"`이라고 설정하면  
설정 화면에 "이동" 섹션이 자동으로 생기고 해당 키들이 그 아래에 모인다.

---

## 전체 UI 계층 결과

```
설정 화면 (UGameSettingCollection "Mouse & Keyboard")
├─ Sensitivity 섹션 (고정)
│       ├─ X-Axis Sensitivity
│       ├─ Y-Axis Sensitivity
│       ├─ Targeting Sensitivity
│       ├─ Invert Vertical Axis
│       └─ Invert Horizontal Axis
│
├─ "이동" 섹션 (IMC DisplayCategory 기준 자동 생성)
│       ├─ ULyraSettingKeyboardInput (앞으로)
│       ├─ ULyraSettingKeyboardInput (뒤로)
│       ├─ ULyraSettingKeyboardInput (좌로)
│       └─ ULyraSettingKeyboardInput (우로)
│
└─ "액션" 섹션 (IMC DisplayCategory 기준 자동 생성)
        ├─ ULyraSettingKeyboardInput (점프)
        ├─ ULyraSettingKeyboardInput (상호작용)
        └─ ULyraSettingKeyboardInput (달리기)
```
