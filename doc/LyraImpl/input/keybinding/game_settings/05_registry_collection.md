# 05. Registry & Collection — 설정 항목 구조화

> 출처: `Plugins/GameSettings/Source/Public/GameSettingRegistry.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingCollection.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingRegistryChangeTracker.h`

---

## `UGameSettingRegistry` — 설정 목록 최상위 관리자

```cpp
UCLASS(Abstract)
class UGameSettingRegistry : public UObject
{
protected:
    virtual void OnInitialize(ULocalPlayer* InLocalPlayer) PURE_VIRTUAL(,)  // 서브클래스 구현

public:
    void Initialize(ULocalPlayer* InLocalPlayer);  // OnInitialize() 호출
    virtual void SaveChanges();                    // 모든 설정 저장
    virtual void Regenerate();                     // 설정 목록 재생성

    UGameSetting* FindSettingByDevName(const FName& SettingDevName);

    TArray<TObjectPtr<UGameSetting>> TopLevelSettings;   // 최상위 항목
    TArray<TObjectPtr<UGameSetting>> RegisteredSettings; // 검색용 플랫 목록 (전체)
};
```

### `OnInitialize()` 구현 패턴

```cpp
void ULyraGameSettingRegistry::OnInitialize(ULocalPlayer* InLocalPlayer)
{
    // 최상위 컬렉션 생성
    auto* VideoSection = NewObject<UGameSettingCollection>();
    VideoSection->SetDevName(TEXT("VideoSection"));
    VideoSection->SetDisplayName(LOCTEXT("Video", "비디오"));

    // 하위 항목 추가
    VideoSection->AddSetting(CreateResolutionSetting(InLocalPlayer));
    VideoSection->AddSetting(CreateVSyncSetting(InLocalPlayer));

    RegisterSetting(VideoSection);  // Registry에 등록 (전체 재귀 등록)

    // 마우스·키보드 키 바인딩 섹션
    InitializeMouseAndKeyboardSettings(InLocalPlayer);
}
```

`RegisterSetting()`은 `UGameSettingCollection`의 경우 하위 항목까지 재귀적으로 `RegisteredSettings`에 추가한다. `FindSettingByDevName()`은 이 플랫 목록에서 선형 검색한다.

### `SaveChanges()`

플러그인 기본 구현은 비어 있다. Lyra에서 오버라이드해서:

```cpp
void ULyraGameSettingRegistry::SaveChanges()
{
    Super::SaveChanges();
    // 공유 설정 저장 (감도, 자막, 언어 등)
    ULyraSettingsShared* SharedSettings = ...;
    SharedSettings->ApplySettings();
    SharedSettings->SaveSettings();
    // 키 바인딩 저장
    InputUserSettings->ApplySettings();  // RebuildControlMappings 트리거
    InputUserSettings->AsyncSaveSettings();
}
```

### `Regenerate()`

동적으로 설정 목록이 바뀌어야 하는 경우 (게임 패드 연결/해제, DLC 활성화 등) 호출한다.  
`OnInitialize()`를 다시 실행하는 것과 같다.

---

## `UGameSettingCollection` — 설정 그룹 컨테이너

```cpp
class UGameSettingCollection : public UGameSetting
{
    void AddSetting(UGameSetting* Setting);
    TArray<UGameSettingCollection*> GetChildCollections() const;
    virtual TArray<UGameSetting*> GetChildSettings() override { return Settings; }
    virtual bool IsSelectable() const { return false; }  // 컨테이너는 선택 불가

protected:
    TArray<TObjectPtr<UGameSetting>> Settings;
};
```

`UGameSetting`을 상속하기 때문에 `EditCondition`도 붙일 수 있다.  
섹션 전체를 특정 플랫폼에서 숨기려면 Collection에 `AddEditCondition`을 추가하면 된다.

### 계층 구성 예시

```
UGameSettingRegistry
    └─ UGameSettingCollection "InputSection"
            ├─ UGameSettingCollection "MouseAndKeyboard"  (탭)
            │       ├─ ULyraSettingKeyboardInput "IA_Jump"
            │       ├─ ULyraSettingKeyboardInput "IA_Move"
            │       └─ ...
            └─ UGameSettingCollection "Gamepad"  (탭)
                    ├─ UGameSettingValueScalar "LookSensitivity"
                    └─ ...
```

---

## `UGameSettingCollectionPage` — 하위 페이지 이동 항목

```cpp
class UGameSettingCollectionPage : public UGameSettingCollection
{
    FText GetNavigationText() const;      // ">" 버튼에 표시되는 텍스트
    void ExecuteNavigation();             // 하위 페이지로 이동 트리거
    virtual bool IsSelectable() const override { return true; }
};
```

일반 `UGameSettingCollection`은 그 자체가 선택되지 않고 하위 항목을 직접 표시한다.  
`UGameSettingCollectionPage`는 선택하면 하위 페이지로 **이동**한다.

```
"입력 설정" CollectionPage  ← 목록에 항목으로 표시, 클릭 시 다음 화면으로
    └─ "키보드 바인딩" Collection
    └─ "게임패드 바인딩" Collection
```

---

## `FGameSettingRegistryChangeTracker` — Dirty 상태 추적

설정 화면에서 "저장이 필요한 변경이 있는가"를 추적한다.  
**"적용" 버튼 활성화 여부**를 이것으로 결정한다.

```cpp
class FGameSettingRegistryChangeTracker
{
    void WatchRegistry(UGameSettingRegistry* InRegistry);  // Registry 이벤트 구독
    void StopWatchingRegistry();

    bool HaveSettingsBeenChanged() const { return bSettingsChanged; }  // "저장 필요 상태"

    void ApplyChanges();        // 모든 Dirty 설정 적용
    void RestoreToInitial();    // 모든 변경 취소
    void ClearDirtyState();     // Dirty 플래그 초기화 (저장 완료 후 호출)
};
```

### `UGameSettingScreen`과의 연결

```cpp
// UGameSettingScreen 내부
FGameSettingRegistryChangeTracker ChangeTracker;

void NativeOnActivated() override
{
    ChangeTracker.WatchRegistry(GetOrCreateRegistry());
}

void ApplyChanges() override
{
    GetRegistry()->SaveChanges();
    ChangeTracker.ClearDirtyState();
    OnSettingsDirtyStateChanged(false);  // BP 이벤트: "적용" 버튼 비활성화
}

void CancelChanges() override
{
    ChangeTracker.RestoreToInitial();
    ChangeTracker.ClearDirtyState();
}
```

`HaveSettingsBeenChanged()`가 `true`일 때 화면 닫기를 시도하면 "저장하지 않고 닫겠습니까?" 다이얼로그를 띄우는 것도 이 값을 기반으로 한다.

### Dirty 추적에서 제외되는 것

`UGameSettingAction`의 경우 기본값이 `bDirtyAction = false`이므로 Tracker에 잡히지 않는다.  
되돌릴 수 없는 동작(로그아웃, 데이터 삭제 등)은 Dirty 처리하지 않는 것이 기본 설계 의도다.
