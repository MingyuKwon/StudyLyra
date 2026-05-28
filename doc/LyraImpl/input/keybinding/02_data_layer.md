# 02. 데이터 계층 — 키 변경 결과가 어디에 저장되는가

> 출처: 엔진 `UserSettings/EnhancedInputUserSettings.h`,  
>        Lyra `Input/LyraInputUserSettings.h/cpp`, `Input/LyraPlayerMappableKeyProfile.h/cpp`

---

## 데이터 구조 전체 트리

```
UEnhancedInputLocalPlayerSubsystem
└─ GetUserSettings()
        └─ ULyraInputUserSettings  (UEnhancedInputUserSettings 상속)
                └─ GetAllAvailableKeyProfiles()
                        └─ TMap<FString, UEnhancedPlayerMappableKeyProfile*>
                                └─ ULyraPlayerMappableKeyProfile  (프로필 1개 = 키 배치 세트)
                                        └─ GetPlayerMappingRows()
                                                └─ TMap<FName, FKeyMappingRow>
                                                        └─ FKeyMappingRow  (액션 1개)
                                                                └─ TSet<FPlayerKeyMapping>  Mappings
                                                                        ├─ Slot: First
                                                                        │       CurrentKey: FKey("E")
                                                                        │       DefaultKey: FKey("E")
                                                                        └─ Slot: Second
                                                                                CurrentKey: FKey("Tab")
                                                                                DefaultKey: FKey("Tab")
```

---

## 각 클래스/구조체 상세

### `ULyraInputUserSettings`

```cpp
// LyraInputUserSettings.h
UCLASS(MinimalAPI)
class ULyraInputUserSettings : public UEnhancedInputUserSettings
{
    virtual void ApplySettings() override;
    // 확장 포인트: 키 설정 적용 시 추가 로직을 넣을 수 있음
};
```

**역할**: 엔진 `UEnhancedInputUserSettings`의 Lyra 버전.  
현재 `ApplySettings()`를 오버라이드하지만 구현은 `Super::ApplySettings()` 호출 하나다.  
주석에 "여기에 브레이크포인트를 걸어라"고 명시되어 있어, **공식 확장 포인트**로 설계된 클래스다.

**어디서 접근하는가**:
```cpp
UEnhancedInputLocalPlayerSubsystem* Subsystem = LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
UEnhancedInputUserSettings* Settings = Subsystem->GetUserSettings();
// Settings를 ULyraInputUserSettings로 캐스팅 가능
```

**저장 연동**: `ULyraSettingsShared::SaveSettings()` 호출 시 함께 직렬화된다.  
`UPROPERTY(SaveGame)`으로 표시된 필드들이 `.sav` 파일에 포함된다.

---

### `ULyraPlayerMappableKeyProfile`

```cpp
// LyraPlayerMappableKeyProfile.h
UCLASS(MinimalAPI)
class ULyraPlayerMappableKeyProfile : public UEnhancedPlayerMappableKeyProfile
{
    virtual void EquipProfile() override;    // 현재 Super만 호출
    virtual void UnEquipProfile() override;  // 현재 Super만 호출
};
```

**역할**: 하나의 "키 배치 세트". 예를 들어 "기본 배치", "왼손잡이 배치"처럼 여러 프로필을 만들 수 있다.

**현재 Lyra 상태**: `EquipProfile()`과 `UnEquipProfile()` 모두 빈 훅.  
코드 주석에 "프로필 교체 시 원하는 동작을 여기에 넣어라"라고 명시.

**프로필 접근**:
```cpp
// 현재 활성 프로필
UEnhancedPlayerMappableKeyProfile* Current = Settings->GetCurrentProfile();

// 모든 프로필 목록
const TMap<FString, TObjectPtr<UEnhancedPlayerMappableKeyProfile>>& All
    = Settings->GetAllAvailableKeyProfiles();
```

**기본 프로필**: Lyra는 기본적으로 프로필 하나만 사용한다.  
여러 프로필 기능을 쓰고 싶으면 `UEnhancedInputUserSettings::CreateNewKeyProfile()`로 추가할 수 있다.

---

### `FKeyMappingRow`

```cpp
// 엔진 EnhancedInputUserSettings.h
struct FKeyMappingRow
{
    TSet<FPlayerKeyMapping> Mappings;  // 같은 액션의 모든 슬롯(First, Second, ...)
    bool HasAnyMappings() const;
};
```

**역할**: 하나의 `InputAction`에 대한 모든 키 슬롯 묶음.  
점프 액션이 "SpaceBar(Primary) + 패드 A버튼(Secondary)"처럼 두 개가 있으면  
`FKeyMappingRow.Mappings`에 두 개의 `FPlayerKeyMapping`이 들어간다.

**Map의 Key**: `FName` — `UInputAction`의 `PlayerMappableKeySettings`에서 설정한 이름.

---

### `FPlayerKeyMapping`

```cpp
// 엔진 EnhancedInputUserSettings.h
struct FPlayerKeyMapping
{
    // 현재 키 (사용자가 변경했으면 변경된 값)
    FKey CurrentKey;
    
    // 기본 키 (IMC에 설정된 원래 키)
    FKey DefaultKey;
    
    // Primary / Secondary 슬롯 구분
    EPlayerMappableKeySlot Slot;
    
    // 디스플레이 이름, 카테고리 (IMC에서 가져옴)
    FText DisplayName;
    FText DisplayCategory;
    
    // 현재 키가 기본값에서 변경되었는가
    bool IsCustomized() const { return CurrentKey != DefaultKey; }
    
    FName GetMappingName() const;
    FKey GetCurrentKey() const;
    FKey GetDefaultKey() const;
    EPlayerMappableKeySlot GetSlot() const;
};
```

**CurrentKey vs DefaultKey 의미**:

| 필드 | 값 | 설명 |
|------|----|----|
| `DefaultKey` | IMC에 설정된 키 | "기본값으로 리셋" 시 이 값으로 복원 |
| `CurrentKey` | 사용자가 바꾼 키 | 실제 게임에 적용되는 키 |
| `IsCustomized()` | `CurrentKey != DefaultKey` | "기본값으로 리셋" 버튼 표시 여부 판단에 사용 |

**`EPlayerMappableKeySlot`**:

```cpp
enum class EPlayerMappableKeySlot : uint8
{
    First  = 0,  // Primary 키
    Second = 1,  // Secondary 키
    Third  = 2,
    // ...
};
```

---

### `ULyraPlayerMappableKeySettings`

```cpp
// LyraInputUserSettings.h
UCLASS(MinimalAPI)
class ULyraPlayerMappableKeySettings : public UPlayerMappableKeySettings
{
    const FText& GetTooltipText() const;

protected:
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Settings")
    FText Tooltip = FText::GetEmpty();
};
```

**역할**: IMC 내 각 키 매핑에 붙이는 메타데이터.  
이것이 IMC에 지정되어 있어야 그 키가 "리맵 가능한 키"로 취급된다.

**에디터 설정 위치**:
```
IMC 에셋 열기
    → Mappings[n]
        → Player Mappable Key Settings
            → Class: LyraPlayerMappableKeySettings (또는 부모 클래스)
            → Display Name: "점프"
            → Display Category: "이동"
            → Tooltip: "캐릭터가 점프합니다"
```

**엔진 `UPlayerMappableKeySettings`가 제공하는 필드**:
- `DisplayName` — 설정 화면에 표시할 이름
- `DisplayCategory` — 설정 화면에서 어느 카테고리 섹션에 넣을지
- `MappingName` — 내부 식별 이름 (`FName`)

---

## 데이터 접근 패턴 예시

### 특정 액션의 Primary 키 가져오기

```cpp
UEnhancedInputUserSettings* Settings = Subsystem->GetUserSettings();
UEnhancedPlayerMappableKeyProfile* Profile = Settings->GetCurrentProfile();

const FKeyMappingRow* Row = Profile->FindKeyMappingRow(FName("IA_Jump"));
if (Row)
{
    for (const FPlayerKeyMapping& Mapping : Row->Mappings)
    {
        if (Mapping.GetSlot() == EPlayerMappableKeySlot::First)
        {
            FKey CurrentKey = Mapping.GetCurrentKey();  // 사용자 설정 키
            break;
        }
    }
}
```

### 특정 키가 어떤 액션에 바인딩되어 있는지 찾기

```cpp
TArray<FName> OutActionNames;
Profile->GetMappingNamesForKey(FKey("E"), OutActionNames);
// OutActionNames에 "E"를 쓰는 모든 액션 이름이 담김
```

### 커스터마이징된 매핑만 찾기

```cpp
for (const FPlayerKeyMapping& Mapping : Row->Mappings)
{
    if (Mapping.IsCustomized())
    {
        // 사용자가 기본값에서 바꾼 키
    }
}
```

---

## 물리 저장 경로

```
ULyraSettingsShared::SaveSettings()
    └─ ULocalPlayerSaveGame::AsyncSave()
            └─ ULyraInputUserSettings::Serialize()  ← UPROPERTY(SaveGame) 필드 직렬화
                    → Saved/SaveGames/<PlayerName>.sav
```

**클라우드 세이브 호환**: `ULocalPlayerSaveGame` 기반이므로 플랫폼 클라우드 저장 시스템과 자동 연동된다.  
다른 기기에서 같은 계정으로 로그인하면 키 바인딩이 복원된다.

**주의**: `ULyraInputUserSettings`에 커스텀 필드를 추가할 때는 반드시 `UPROPERTY(SaveGame)`을  
붙여야 직렬화된다. 없으면 게임 재시작 시 초기화된다.
