# 00. Enhanced Input UserSettings — 엔진이 제공하는 키 바인딩 시스템

> 출처: `D:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/UserSettings/EnhancedInputUserSettings.h`  
>        `D:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/UserSettings/EnhancedInputUserSettings.cpp`

---

## 왜 이 시스템이 존재하는가

Enhanced Input의 `AddMappingContext(IMC)`는 게임 입력 처리만 담당한다.  
리맵핑 UI를 만들려면 별도로 "어떤 키가 리맵 가능한지", "지금 어떤 키로 바뀌었는지"를 관리하는 계층이 필요하다.  
그게 바로 `UEnhancedInputUserSettings`다.

클래스 헤더 주석에 명시되어 있다:

> "This also provides a Registration point for Input Mapping Contexts (IMC) from **possibly unloaded plugins** (i.e. Game Feature Plugins). You can register your IMC from a Game Feature Action plugin here, and then have access to all the key mappings available. This is very useful for **building settings screens** because you can now access all the mappings in your game, **even if the entire plugin isn't loaded yet**."

즉, 이 시스템은 두 가지를 해결한다:
1. 리맵핑 데이터를 한 곳에서 관리 (누가 어떤 키를 썼는지)
2. Game Feature 플러그인처럼 동적으로 로드/언로드되는 IMC의 키도 설정 화면에서 접근 가능하게 함

---

## 전체 클래스 구조

```
USaveGame
└─ UEnhancedInputUserSettings
        ├─ RegisteredMappingContexts: TSet<UInputMappingContext*>
        │       ← 등록된 IMC 목록 (Transient, 저장 안 됨)
        │
        ├─ CurrentProfileIdentifierString: FString
        │       ← 현재 활성 프로필 ID (SaveGame, 저장됨)
        │
        └─ SavedKeyProfilesMap: TMap<FString, UEnhancedPlayerMappableKeyProfile*>
                ← 모든 프로필 (Transient, 하지만 Serialize()에서 커스텀 직렬화)

UObject
└─ UEnhancedPlayerMappableKeyProfile
        └─ PlayerMappedKeys: TMap<FName, FKeyMappingRow>
                ← 액션 이름 → 키 매핑 행 (Transient, 커스텀 직렬화)

struct FKeyMappingRow
    └─ Mappings: TSet<FPlayerKeyMapping>
            ← 같은 액션의 모든 슬롯

struct FPlayerKeyMapping
    ├─ MappingName: FName        ← 액션 식별자
    ├─ DefaultKey: FKey          ← IMC 원본 키 (Transient)
    ├─ CurrentKey: FKey          ← 사용자가 설정한 키 (저장됨)
    ├─ Slot: EPlayerMappableKeySlot
    ├─ bIsDirty: bool            ← 저장이 필요한 상태인가 (Transient)
    ├─ DisplayName: FText        ← UI 표시 이름 (Transient)
    └─ DisplayCategory: FText    ← UI 카테고리 (Transient)
```

---

## 세 계층의 관계 — Profile / Row / Mapping

구조 트리만 보면 관계가 바로 와닿지 않을 수 있어서 역할을 구분해서 설명한다.

| 계층 | 역할 | 비유 |
|------|------|------|
| `UEnhancedPlayerMappableKeyProfile` | 키 배치 프리셋 1개 전체 | "기본 배치" 설정 파일 한 장 |
| `FKeyMappingRow` | 액션 1개의 모든 슬롯 묶음 | 그 파일에서 "점프" 항목 한 줄 |
| `FPlayerKeyMapping` | 슬롯 1개의 실제 키값 | "점프 Primary: SpaceBar" |

**구체적인 예시로 보면:**

```
Profile "기본 배치"  (UEnhancedPlayerMappableKeyProfile)
│
├─ "IA_Jump" → FKeyMappingRow
│                   ├─ FPlayerKeyMapping { Slot: First,  CurrentKey: SpaceBar, DefaultKey: SpaceBar }
│                   └─ FPlayerKeyMapping { Slot: Second, CurrentKey: F,        DefaultKey: Invalid  }
│                                                                               ↑ 사용자가 직접 추가한 슬롯
│                                                                                 IMC에 없으므로 Default=Invalid
│
└─ "IA_Interact" → FKeyMappingRow
                        └─ FPlayerKeyMapping { Slot: First, CurrentKey: E, DefaultKey: E }
```

**`FKeyMappingRow`가 왜 따로 존재하는가?**

직관적으로 생각하면 `TMap<FName, TSet<FPlayerKeyMapping>>`이면 충분해 보인다.  
그런데 Blueprint는 중첩 컨테이너(`TMap<K, TSet<V>>`)를 지원하지 않는다.  
그래서 `TSet<FPlayerKeyMapping>`을 `FKeyMappingRow` 구조체로 한 번 감싼 것이다.  
헤더 주석에 이유가 직접 명시되어 있다:

> *"Since a single mapping can have multiple bindings to it and this system should be Blueprint friendly, this needs to be a struct (blueprint don't support nested containers)."*

**`Map`의 Key(`FName`)는 어디서 오는가?**

`UPlayerMappableKeySettings`(또는 서브클래스)에서 지정한 `MappingName`이다.  
에디터에서 IMC를 열어 키 매핑에 `PlayerMappableKeySettings`를 붙일 때 설정하는 이름.  
`UInputAction`의 에셋 이름과 다를 수 있고, 같은 `UInputAction`에 대해 여러 IMC에서 각각 다른 이름을 붙일 수도 있다.

---

## `RegisterInputMappingContext()` — 실제 동작

```cpp
bool UEnhancedInputUserSettings::RegisterInputMappingContext(const UInputMappingContext* IMC)
{
    // 이미 등록된 IMC는 중복 등록하지 않음
    if (RegisteredMappingContexts.Contains(IMC))
        return false;

    // [1] IMC를 등록 목록에 추가 (나중에 Serialize 로드 시 재등록에 사용)
    RegisteredMappingContexts.Add(IMC);

    // [2] 실제 프로필에 키 매핑 등록
    return RegisterInputMappingContextInternal(IMC);
}
```

`RegisterInputMappingContextInternal()` 내부:

```cpp
bool UEnhancedInputUserSettings::RegisterInputMappingContextInternal(const UInputMappingContext* IMC)
{
    // IMC가 특정 프로필 전용 키를 가지고 있으면 그 프로필도 생성
    for (const FString& ProfileId : IMC->GetProfilesWithOverridenMappings())
    {
        if (!SavedKeyProfilesMap.Contains(ProfileId))
            CreateNewKeyProfile(...);  // 필요한 프로필 자동 생성
    }

    // 모든 프로필에 이 IMC의 매핑을 등록
    for (auto& Pair : SavedKeyProfilesMap)
    {
        RegisterKeyMappingsToProfile(*Pair.Value, IMC);
    }

    OnMappingContextRegistered.Broadcast(IMC);
    return true;
}
```

`RegisterKeyMappingsToProfile()` — **핵심 로직**:

```cpp
for (const FEnhancedActionKeyMapping& KeyMapping : IMC->GetMappingsForProfile(Profile.GetProfileIdString()))
{
    // PlayerMappableKeySettings가 없으면 건너뜀 (리맵 불가 키)
    if (!KeyMapping.IsPlayerMappable())
        continue;

    const FName MappingName = KeyMapping.GetMappingName();

    // 프로필에 이 액션의 Row가 없으면 생성
    FKeyMappingRow& MappingRow = Profile.PlayerMappedKeys.FindOrAdd(MappingName);

    // 이 슬롯에 이미 사용자가 커스텀한 매핑이 있는가?
    bool bUpdatedExistingMapping = false;
    for (FPlayerKeyMapping& ExistingMapping : MappingRow.Mappings)
    {
        if (ExistingMapping.GetSlot() == MappingSlot)
        {
            // 기존 매핑의 DefaultKey를 IMC 원본으로 업데이트
            ExistingMapping.UpdateDefaultKeyFromActionKeyMapping(KeyMapping);
            // DisplayName, DisplayCategory 등 메타데이터도 최신 IMC 기준으로 갱신
            ExistingMapping.UpdateMetadataFromActionKeyMapping(KeyMapping);
            bUpdatedExistingMapping = true;
        }
    }

    // 기존 커스텀 매핑이 없으면 새로 생성 (DefaultKey = CurrentKey = IMC 원본 키)
    if (!bUpdatedExistingMapping)
    {
        MappingRow.Mappings.Add({ KeyMapping, MappingSlot, MappingDeviceType });
    }

    // 서브클래스 훅
    OnKeyMappingRegisteredToProfile(&Profile, RegisteredMapping, KeyMapping);

    // 슬롯 증가 (같은 액션의 두 번째 키는 Second 슬롯으로)
    MappingSlot = Next(MappingSlot);
}
```

**핵심 포인트**: 사용자가 이미 키를 커스텀한 상태에서 `RegisterInputMappingContext()`가 다시 호출되면  
`CurrentKey`(사용자 설정값)는 **건드리지 않고** `DefaultKey`와 메타데이터만 갱신한다.

---

## `FPlayerKeyMapping` 상세

### `GetCurrentKey()` 의 실제 구현

```cpp
const FKey& FPlayerKeyMapping::GetCurrentKey() const
{
    return IsCustomized() ? CurrentKey : DefaultKey;
}
```

**`CurrentKey`가 항상 사용자 키를 담고 있지 않다.**  
`IsCustomized()`가 false이면 `DefaultKey`를 반환한다.  
→ 기본값 상태에서는 `CurrentKey`가 `EKeys::Invalid`일 수 있다.

### `bIsDirty` vs `IsCustomized()` 차이

```cpp
bool IsCustomized() const { return CurrentKey != DefaultKey; }  // 지금 기본값과 다른가
bool IsDirty() const { return bIsDirty; }                      // 저장이 필요한 상태인가
```

| 상태 | IsCustomized | IsDirty |
|------|-------------|---------|
| 처음 등록 (기본값) | false | false |
| 사용자가 키 변경 | true | true |
| 변경 후 저장 완료 | true | false |
| ResetToDefault() 호출 (변경이 있었으면) | false | true |
| ResetToDefault() 호출 (원래 기본값이었으면) | false | false |

`IsDirty`는 "마지막 저장 이후 변경이 있었는가"를 나타낸다.  
저장 완료 후 `bIsDirty = false`로 초기화된다.

### `TSet`의 해시 기준

```cpp
uint32 GetTypeHash(const FPlayerKeyMapping& InMapping)
{
    Hash = HashCombine(Hash, GetTypeHash(InMapping.MappingName));
    Hash = HashCombine(Hash, GetTypeHash(InMapping.Slot));
    Hash = HashCombine(Hash, GetTypeHash(InMapping.CurrentKey));
    Hash = HashCombine(Hash, GetTypeHash(InMapping.HardwareDeviceId));
    return Hash;
}
```

`FKeyMappingRow.Mappings`는 `TSet<FPlayerKeyMapping>`이다.  
해시가 **MappingName + Slot + CurrentKey + HardwareDeviceId** 조합으로 결정된다.  
같은 액션의 Primary/Secondary 슬롯이 별도 원소로 존재할 수 있는 이유다.

---

## `MapPlayerKey()` 상세

```cpp
void UEnhancedInputUserSettings::MapPlayerKey(const FMapPlayerKeyArgs& InArgs, FGameplayTagContainer& FailureReason)
{
    UEnhancedPlayerMappableKeyProfile* KeyProfile = GetActiveKeyProfile();  // 현재 활성 프로필

    // 케이스 1: 이미 해당 슬롯에 매핑이 있음 → CurrentKey만 변경
    if (FPlayerKeyMapping* FoundMapping = KeyProfile->FindKeyMapping(InArgs))
    {
        FoundMapping->SetCurrentKey(InArgs.NewKey);  // bIsDirty = true 설정됨
        OnKeyMappingUpdated(FoundMapping, InArgs, false);  // 서브클래스 훅
        OnSettingsChanged.Broadcast(this);  // UI 갱신 트리거
    }
    // 케이스 2: 해당 슬롯에 매핑이 없지만 Row는 있음 → 새 슬롯 매핑 생성
    else if (FKeyMappingRow* MappingRow = KeyProfile->FindKeyMappingRowMutable(InArgs.MappingName))
    {
        if (InArgs.bCreateMatchingSlotIfNeeded)
        {
            // 새 FPlayerKeyMapping 생성 (DefaultKey = Invalid, CurrentKey = 새 키)
            FPlayerKeyMapping NewMapping = {};
            NewMapping.MappingName = InArgs.MappingName;
            NewMapping.Slot = InArgs.Slot;
            NewMapping.bIsDirty = true;
            NewMapping.SetCurrentKey(InArgs.NewKey);
            // ...메타데이터는 기존 Row의 다른 매핑에서 복사
            MappingRow->Mappings.Add(NewMapping);
        }
    }
    // 케이스 3: MappingRow 자체가 없음 → 실패 (RegisterInputMappingContext가 안 된 것)
    else
    {
        FailureReason.AddTag(TAG_NoMappingRowFound);
    }
}
```

**케이스 2가 발생하는 상황**: IMC에는 Primary 슬롯만 정의되어 있는데,  
사용자가 Secondary 슬롯에 추가로 키를 바인딩하는 경우.  
이 경우 새로 생성된 매핑의 `DefaultKey`는 `EKeys::Invalid`다.

---

## `ApplySettings()` — 실제 하는 일

```cpp
void UEnhancedInputUserSettings::ApplySettings()
{
    UE_LOG(LogEnhancedInput, Verbose, TEXT("Enhanced Input User Settings applied!"));
    OnSettingsApplied.Broadcast();  // ← 이게 전부
}
```

**`ApplySettings()`는 IMC를 직접 패치하지 않는다.**

실제 게임 입력 반영은 `IEnhancedInputSubsystemInterface::RebuildControlMappings()`에서 일어난다.  
Enhanced Input은 IMC를 게임에 적용(AddMappingContext)할 때마다 내부적으로 `RebuildControlMappings()`를 호출하고,  
그 안에서 `GetPlayerMappedKeysForRebuildControlMappings()`를 통해 `CurrentKey`를 물어본다.

```
RebuildControlMappings() [EnhancedInput 내부, AddMappingContext 시 자동 호출]
    └─ 각 FEnhancedActionKeyMapping에 대해
            └─ Profile->GetPlayerMappedKeysForRebuildControlMappings(DefaultMapping, OutKeys)
                    └─ QueryPlayerMappedKeys() → CurrentKey 목록 반환
            └─ OutKeys가 비어있지 않으면 CurrentKey로 입력 등록
               OutKeys가 비어있으면 DefaultKey(IMC 원본)로 등록
```

즉, 키 변경 후 게임에 반영되는 시점은 `ApplySettings()` 호출이 아니라  
`RebuildControlMappings()`가 트리거되는 시점이다.  
Lyra에서는 `ULyraInputUserSettings::ApplySettings()` → `Super::ApplySettings()` → `OnSettingsApplied` 브로드캐스트 → Lyra가 이를 수신해서 직접 `RebuildControlMappings()` 혹은 subsystem 갱신을 트리거한다.

---

## `Serialize()` — 저장되는 것과 저장 안 되는 것

```cpp
// 저장 시 (IsSaving)
for (auto& ProfilePair : SavedKeyProfilesMap)
{
    for (auto& MappingRow : Profile->PlayerMappedKeys)
    {
        for (FPlayerKeyMapping& Mapping : MappingRow.Value.Mappings)
        {
            // IsDirty OR IsCustomized인 것만 저장
            if (Mapping.IsDirty() || Mapping.IsCustomized())
            {
                Header.DirtyMappings.Push({
                    ActionName = Mapping.MappingName,
                    CurrentKeyName = Mapping.CurrentKey.GetFName(),
                    HardwareDeviceId = Mapping.HardwareDeviceId,
                    Slot = Mapping.Slot
                });
                Mapping.bIsDirty = false;  // 저장 완료 → dirty 해제
            }
        }
    }
}
```

**저장되는 것**: `CurrentKey`, `MappingName`, `Slot`, `HardwareDeviceId`  
**저장 안 되는 것**: `DefaultKey`, `DisplayName`, `DisplayCategory`, `AssociatedInputAction`

→ DefaultKey와 메타데이터는 **Transient**이며 매번 `RegisterInputMappingContext()`로 복원된다.

```cpp
// 로드 시 (IsLoading)
SavedKeyProfilesMap.Empty();

// 저장된 더티 매핑들로 프로필 재구성
for (const FKeyMappingSaveData& SavedKeyData : Header.DirtyMappings)
{
    FPlayerKeyMapping PlayerMapping = {};
    PlayerMapping.MappingName = SavedKeyData.ActionName;
    PlayerMapping.CurrentKey = FKey(SavedKeyData.CurrentKeyName);
    // DefaultKey는 여기서 설정되지 않음! (IMC 재등록 시 채워짐)
    MappingRow.Mappings.Add(PlayerMapping);
}

// 로드 후, 등록된 모든 IMC를 다시 등록해서 DefaultKey/메타데이터 복원
for (const UInputMappingContext* IMC : RegisteredMappingContexts)
{
    RegisterInputMappingContextInternal(IMC);
    // 이 시점에 기존 CurrentKey는 유지되고 DefaultKey만 채워짐
}
```

---

## `UnregisterInputMappingContext()` — 주의사항

```cpp
bool UEnhancedInputUserSettings::UnregisterInputMappingContext(const UInputMappingContext* IMC)
{
    return RegisteredMappingContexts.Remove(IMC) != INDEX_NONE;
    // Profile의 PlayerMappedKeys는 건드리지 않음!
}
```

**IMC를 언등록해도 프로필의 키 매핑은 삭제되지 않는다.**  
`RegisteredMappingContexts`에서만 제거된다.  
→ Game Feature 플러그인이 언로드되어 IMC가 언등록되어도 사용자 설정값은 보존된다.

---

## `FPlayerMappableKeyQueryOptions` 필터 동작

```cpp
bool UEnhancedPlayerMappableKeyProfile::DoesMappingPassQueryOptions(
    const FPlayerKeyMapping& PlayerMapping,
    const FPlayerMappableKeyQueryOptions& Options) const
{
    if (Options.KeyToMatch.IsValid() && Options.bMatchBasicKeyTypes)
    {
        const FKey& A = Options.KeyToMatch;
        const FKey& B = PlayerMapping.GetCurrentKey();

        // 게임패드 여부, 터치 여부, 제스처 여부가 모두 같아야 통과
        bool bKeyTypesMatch =
            A.IsGamepadKey() == B.IsGamepadKey() &&
            A.IsTouch()     == B.IsTouch() &&
            A.IsGesture()   == B.IsGesture();

        if (!bKeyTypesMatch) return false;
    }

    // 슬롯 필터 (Unspecified이면 모든 슬롯 통과)
    if (Options.SlotToMatch != EPlayerMappableKeySlot::Unspecified &&
        Options.SlotToMatch != PlayerMapping.GetSlot())
        return false;

    // 하드웨어 디바이스 타입 필터
    if (Options.RequiredDeviceType != EHardwareDevicePrimaryType::Unspecified &&
        Options.RequiredDeviceType != PlayerMapping.GetHardwareDeviceId().PrimaryDeviceType)
        return false;

    return true;
}
```

**Lyra가 `KeyToMatch = EKeys::W, bMatchBasicKeyTypes = true`로 쓰는 이유**:  
W키는 키보드 키이므로 `IsGamepadKey() == false`.  
이 필터를 통과하면 "키보드 타입 키만" 허용하는 것과 같다.  
게임패드 버튼은 `IsGamepadKey() == true`이므로 필터에서 걸려 마우스&키보드 설정 탭에 표시되지 않는다.

---

## 직렬화 버전 관리

```cpp
struct FPlayerMappableSaveVersion
{
    static constexpr int32 Base = 1;
    static constexpr int32 ConvertProfileIdFromTagToString = 2;  // FGameplayTag → FString 전환
    static constexpr int32 Current = ConvertProfileIdFromTagToString;
};
```

버전 1(UE 5.5 이전): 프로필 ID가 `FGameplayTag`  
버전 2(UE 5.6+): 프로필 ID가 `FString`  
이전 버전 세이브 파일은 로드 시 자동으로 변환된다.

---

## 콘솔 커맨드

디버깅 시 유용한 콘솔 커맨드:

```
EnhancedInput.DumpKeyProfileToLog
    → 현재 프로필의 모든 키 매핑을 로그에 출력

EnhancedInput.SaveKeyProfilesToSlot
    → 현재 설정을 SaveGame 슬롯에 저장

EnhancedInput.SetActiveKeyProfile <ProfileName>
    → 활성 프로필 변경 (예: EnhancedInput.SetActiveKeyProfile PresetA)
```

---

## 전체 흐름 요약

```
[등록]
RegisterInputMappingContext(IMC)
    └─ RegisteredMappingContexts에 IMC 추가
    └─ 모든 Profile에 RegisterKeyMappingsToProfile()
            └─ IMC의 PlayerMappable 키들 → FPlayerKeyMapping 생성/업데이트
                    └─ DefaultKey = IMC 원본키
                       CurrentKey = DefaultKey (신규) 또는 기존 사용자 설정값 유지

[변경]
MapPlayerKey(Args)
    └─ Profile에서 해당 슬롯의 FPlayerKeyMapping 찾기
    └─ CurrentKey 변경 + bIsDirty = true
    └─ OnSettingsChanged 브로드캐스트 (UI 갱신)

[게임 반영]
RebuildControlMappings() [AddMappingContext 시 자동]
    └─ 각 IMC 키 매핑에 대해 Profile->QueryPlayerMappedKeys()
    └─ 반환된 CurrentKey로 게임 입력 등록

[저장]
SaveSettings() / AsyncSaveSettings()
    └─ IsDirty || IsCustomized인 매핑만 직렬화
    └─ .sav 파일에 기록

[로드]
Serialize(Loading)
    └─ 저장된 CurrentKey로 FPlayerKeyMapping 복원 (DefaultKey는 비어있음)
    └─ RegisteredMappingContexts의 모든 IMC 재등록
            └─ RegisterKeyMappingsToProfile() → DefaultKey 채워짐
```
