# 06. 적용 & 저장 — 변경한 키가 언제 실제 게임에 반영되는가

> 출처: Lyra `Input/LyraInputUserSettings.cpp`, `Settings/LyraSettingsShared.h/cpp`,  
>        `Settings/LyraGameSettingRegistry.h`,  
>        엔진 `UserSettings/EnhancedInputUserSettings.h`

---

## 핵심 3단계

| 단계 | 함수 | 효과 |
|------|------|------|
| **1. 메모리 변경** | `MapPlayerKey()` | `FPlayerKeyMapping.CurrentKey` 업데이트. 게임에 반영 안 됨 |
| **2. 게임 반영** | `ApplySettings()` | IMC 런타임 오버라이드. 즉시 새 키로 게임 동작 |
| **3. 영구 저장** | `SaveSettings()` | `.sav` 파일에 직렬화. 재시작 후에도 유지 |

이 세 단계가 분리되어 있기 때문에 **취소가 가능한 편집**이 성립한다.

---

## 1단계: `MapPlayerKey()` — 메모리만 변경

```cpp
// ULyraSettingKeyboardInput::ChangeBinding()에서 호출
FMapPlayerKeyArgs Args = {};
Args.MappingName = ActionMappingName;     // "IA_Jump"
Args.Slot = EPlayerMappableKeySlot::First;
Args.NewKey = FKey("F");

FGameplayTagContainer FailureReason;
Settings->MapPlayerKey(Args, FailureReason);  // 엔진 API
```

**`FMapPlayerKeyArgs` 옵션 필드**:

```cpp
struct FMapPlayerKeyArgs
{
    FName MappingName;                   // 변경할 액션 이름 (필수)
    EPlayerMappableKeySlot Slot;         // 어느 슬롯 (First/Second/...)
    FKey NewKey;                         // 새 키
    FString ProfileId;                   // 특정 프로필만 변경 (비어있으면 현재 프로필)
    FKey HardwareDeviceId;              // 특정 하드웨어 기기만 변경 (비어있으면 전체)
};
```

**엔진 내부 동작**:
```
MapPlayerKey(Args, FailureReason)
    └─ 현재 프로필에서 Args.MappingName + Args.Slot으로 FPlayerKeyMapping 찾기
            └─ 찾음 → Mapping.CurrentKey = Args.NewKey  (메모리만 변경)
            └─ 못 찾음 → FailureReason에 실패 태그 추가
```

**주의**: `MapPlayerKey()` 후에는 게임 내 동작이 아직 바뀌지 않는다.  
EnhancedInput 서브시스템이 아직 새 키를 모른다.

---

## 2단계: `ApplySettings()` — 게임 반영

### Lyra 오버라이드

```cpp
// LyraInputUserSettings.cpp
void ULyraInputUserSettings::ApplySettings()
{
    Super::ApplySettings();

    // 여기에 추가 로직 삽입 가능 (디버그 브레이크포인트 권장 위치)
}
```

### 엔진 `Super::ApplySettings()` 동작

```
UEnhancedInputUserSettings::ApplySettings()
    └─ UEnhancedInputLocalPlayerSubsystem 가져오기
            └─ 현재 등록된 모든 IMC에서
                    └─ 각 FEnhancedActionKeyMapping에 대해
                            └─ UserSettings에서 CurrentKey 조회
                                    └─ 엔진 내부 오버라이드 맵에 적용
                                            → 이 순간부터 새 키로 입력 처리됨
```

**IMC 에셋 자체는 변경되지 않는다**:
```
원본 IMC:  IA_Jump ← SpaceBar
적용 후:   IA_Jump ← F (플레이어별 오버레이, 메모리만)

원본 IMC 에셋 파일: 변경 없음
다른 플레이어:       여전히 SpaceBar로 동작
```

### 호출 시점

`ApplySettings()`는 Lyra에서 두 경로로 호출된다:

**경로 1 — 설정 화면 닫기/적용**:
```
ULyraGameSettingRegistry::SaveChanges()
    └─ ULyraSettingsShared::ApplySettings()
            └─ ... (감도, 색맹 모드 등 적용)
    └─ ULyraInputUserSettings::ApplySettings()  ← 여기
```

**경로 2 — 게임 시작 시 저장된 설정 복원**:
```
ULyraLocalPlayer가 SharedSettings 로드 완료
    └─ SharedSettings->ApplySettings()
            └─ InputUserSettings->ApplySettings()
```

---

## 3단계: `SaveSettings()` — 영구 저장

### 저장 트리거

```cpp
// ULyraGameSettingRegistry::SaveChanges() 에서 호출됨
void ULyraSettingsShared::SaveSettings()
{
    // ULocalPlayerSaveGame의 비동기 저장
    ULocalPlayerSaveGame::AsyncSaveGameToSlot(this, SlotName, UserIndex, ...);
}
```

**`AsyncSaveGameToSlot`** 내부에서 `ULyraInputUserSettings::Serialize()`가 호출된다.  
`UPROPERTY(SaveGame)`으로 마크된 모든 필드가 직렬화된다.

### 저장 파일 경로

```
Saved/SaveGames/<PlayerName>.sav
```

내용에 `ULyraInputUserSettings`의 직렬화 데이터가 포함된다.

### 클라우드 저장

`ULocalPlayerSaveGame` 기반이므로 플랫폼 클라우드 저장 시스템을 통해  
다른 기기에서 로그인해도 키 바인딩이 복원된다.

---

## 취소 (RestoreToInitial) 흐름

```
설정 화면 열림 시
    └─ 각 ULyraSettingKeyboardInput::StoreInitial() 호출
            └─ InitialKeyMappings[Slot] = CurrentKey  ← 현재 상태 스냅샷

사용자가 키를 여러 번 변경
    └─ MapPlayerKey() × N  (메모리만 변경)

취소 선택 (ESC 또는 취소 버튼)
    └─ ULyraSettingKeyboardInput::RestoreToInitial()
            └─ for (각 InitialKeyMappings 항목):
                    ChangeBinding(Slot, InitialKey)
                    └─ MapPlayerKey(InitialKey)  ← 스냅샷 값으로 복원
```

취소 시 `ApplySettings()`는 호출되지 않는다.  
→ 메모리 내 `CurrentKey`만 원래대로 돌아가고, 게임 반영도 없고, 저장도 없다.

---

## IMC 런타임 패치 동작 원리

EnhancedInput은 `UEnhancedInputLocalPlayerSubsystem` 내부에  
플레이어별 **키 오버라이드 맵**을 유지한다.

```
기본 상태:
    EnhancedInput이 "SpaceBar 누름" 감지
        → IA_Jump 액션 트리거

ApplySettings() 후:
    EnhancedInput 내부 오버라이드 맵: IA_Jump@First → F
    EnhancedInput이 "F 누름" 감지
        → IA_Jump 액션 트리거  (SpaceBar는 더 이상 반응 안 함)
```

원본 IMC 에셋의 키 정보는 `DefaultKey`로만 참조되고,  
실제 입력 처리는 오버라이드 맵의 `CurrentKey`를 기준으로 한다.

---

## `ULyraSettingsShared::ApplySettings()` 전체

```cpp
// LyraSettingsShared.cpp
void ULyraSettingsShared::ApplySettings()
{
    ApplySubtitleOptions();        // 자막 설정
    ApplyBackgroundAudioSettings(); // 백그라운드 오디오
    ApplyCultureSettings();        // 언어/문화권
    ApplyInputSensitivity();       // 마우스 감도 → EnhancedInput Modifier에 적용

    // 색맹 모드
    UGameUserSettings* GameSettings = UGameUserSettings::GetGameUserSettings();
    // ...

    // InputUserSettings도 여기서 적용됨 (별도 코드 경로)
}
```

`ApplyInputSensitivity()`는 감도 값을 `ULyraInputModifiers`의 파라미터로 전달한다.  
키 리맵핑 적용과는 별개의 경로다.

---

## 설정 변경 → 저장 전체 시퀀스 다이어그램

```
[설정 화면 열기]
ULyraGameSettingRegistry::OnInitialize()
    └─ 각 ULyraSettingKeyboardInput::StoreInitial()  ← 스냅샷

[사용자 키 변경]
Button 클릭 → PressAnyKey → 키 선택
    └─ ULyraSettingKeyboardInput::ChangeBinding()
            └─ UEnhancedInputUserSettings::MapPlayerKey()  ← 메모리만

[설정 화면에서 "적용" 클릭 or 닫기]
ULyraGameSettingRegistry::SaveChanges()
    ├─ ULyraSettingsShared::ApplySettings()    ← 감도/언어 등 즉시 반영
    ├─ ULyraInputUserSettings::ApplySettings() ← IMC 런타임 오버라이드 (이 순간부터 새 키)
    └─ ULyraSettingsShared::SaveSettings()     ← .sav 파일에 직렬화

[게임 재시작]
ULyraLocalPlayer 초기화
    └─ ULyraSettingsShared::AsyncLoadOrCreateSettings()
            └─ .sav 파일 역직렬화
                    └─ ULyraInputUserSettings 복원 (CurrentKey 포함)
            └─ SharedSettings->ApplySettings()
                    └─ ULyraInputUserSettings::ApplySettings()
                            └─ 저장된 키 바인딩이 다시 적용됨
```
