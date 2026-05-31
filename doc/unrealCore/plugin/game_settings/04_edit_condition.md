# 04. EditCondition 시스템 — 비활성/숨김 제어

> 출처: `Plugins/GameSettings/Source/Public/GameSettingFilterState.h`  
>        `Plugins/GameSettings/Source/Public/EditCondition/WhenCondition.h`  
>        `Plugins/GameSettings/Source/Public/EditCondition/WhenPlatformHasTrait.h`  
>        `Plugins/GameSettings/Source/Public/EditCondition/WhenPlayingAsPrimaryPlayer.h`

---

## 전체 구조

```
UGameSetting
    └─ EditConditions: TArray<TSharedRef<FGameSettingEditCondition>>

FGameSettingEditCondition (base)           ← 조건 평가 인터페이스
    ├─ FWhenCondition                       ← 인라인 람다
    ├─ FWhenPlatformHasTrait               ← CommonUI 플랫폼 태그 확인
    └─ FWhenPlayingAsPrimaryPlayer         ← 1P 플레이어 확인

FGameSettingEditableState                  ← 평가 결과 (visible/enabled/resetable)
FGameSettingFilterState                    ← 검색·필터 (Registry/Panel이 목록 표시에 사용)
```

---

## `FGameSettingEditCondition` — 조건 base

```cpp
class FGameSettingEditCondition
{
    // 초기화 시 한 번 호출
    virtual void Initialize(const ULocalPlayer* InLocalPlayer) { }

    // 설정 항목이 Apply()될 때
    virtual void SettingApplied(const ULocalPlayer* LP, UGameSetting* Setting) const { }

    // 설정 값이 바뀔 때 (의존 Setting 변경 포함)
    virtual void SettingChanged(const ULocalPlayer* LP, UGameSetting* Setting, ...) const { }

    // 상태 재평가 — InOutEditState를 수정해서 결과를 전달
    virtual void GatherEditState(const ULocalPlayer* LP, FGameSettingEditableState& InOutEditState) const { }

    // 조건 자체가 외부 상태 변화로 바뀌었을 때 브로드캐스트
    FOnEditConditionChanged OnEditConditionChangedEvent;
};
```

여러 조건이 추가되면 **모두 순서대로 `GatherEditState()`가 호출**된다.  
한 조건이 `State.Hide()`를 호출하면 이후 조건도 계속 실행되지만 결과가 이미 Hidden이다.

---

## `FGameSettingEditableState` — 평가 결과

```cpp
class FGameSettingEditableState
{
    // 결과 읽기
    bool IsVisible() const;   // false → 목록에서 안 보임
    bool IsEnabled() const;   // false → 회색, 비활성
    bool IsResetable() const; // false → "기본값으로" 버튼에서 제외

    // 상태 변경
    void Hide(const FString& DevReason);         // 숨김 (개발자용 이유만 필요)
    void Disable(const FText& Reason);           // 비활성 (유저에게 이유 표시)
    void UnableToReset();                        // 리셋 불가
    void Kill(const FString& DevReason);         // Hide + HideFromAnalytics + UnableToReset
    void DisableOption(const FString& Option);   // Discrete 선택지 중 특정 항목만 비활성
};
```

`Hide`와 `Disable`의 차이:
- `Hide`: 항목이 아예 안 보임. 유저가 이유를 알 필요 없음.
- `Disable`: 항목은 보이지만 회색. `Reason` 텍스트가 툴팁/설명으로 표시됨.

`Kill`은 플랫폼에서 아예 지원 안 하는 기능에 쓴다 — 숨기고, 분석에서도 제외하고, 리셋 대상도 아님.

---

## `FWhenCondition` — 인라인 람다 조건

```cpp
Setting->AddEditCondition(MakeShared<FWhenCondition>(
    [](const ULocalPlayer* LP, FGameSettingEditableState& State)
    {
        if (LP->GetGameInstance()->IsDedicatedServerInstance())
            State.Kill(TEXT("Not available on dedicated server"));

        if (!SomeFeatureIsUnlocked(LP))
            State.Disable(LOCTEXT("Locked", "이 기능은 잠겨 있습니다"));
    }));
```

가장 유연하다. 어떤 조건이든 람다 안에서 자유롭게 구현할 수 있다.  
외부 상태가 변해서 조건이 바뀌어야 하면 `BroadcastEditConditionChanged()`를 호출한다.

---

## `FWhenPlatformHasTrait` — 플랫폼 기능 태그

CommonUI의 `UCommonUIHacksTrait` / 플랫폼 태그 시스템을 사용한다.

```cpp
// 태그가 없으면 항목 자체를 Kill (모바일에서 마우스 감도 숨기기 등)
Setting->AddEditCondition(
    FWhenPlatformHasTrait::KillIfMissing(TAG_Platform_Trait_Input_HardwareCursor, TEXT("No hardware cursor")));

// 태그가 있으면 비활성
Setting->AddEditCondition(
    FWhenPlatformHasTrait::DisableIfPresent(TAG_Platform_Trait_ConsoleUI, LOCTEXT("Console", "콘솔에서는 변경 불가")));
```

네 가지 팩토리 메서드:
- `KillIfMissing(Tag, DevReason)` — 태그 없으면 Kill
- `DisableIfMissing(Tag, Reason)` — 태그 없으면 Disable
- `KillIfPresent(Tag, DevReason)` — 태그 있으면 Kill
- `DisableIfPresent(Tag, Reason)` — 태그 있으면 Disable

---

## `FWhenPlayingAsPrimaryPlayer` — 1P 확인

```cpp
Setting->AddEditCondition(MakeShared<FWhenPlayingAsPrimaryPlayer>());
```

분할화면에서 2P 이상의 로컬 플레이어가 이 설정을 열면 비활성화한다.  
"언어 변경"이나 "전체 설정 초기화"처럼 1P만 건드려야 하는 설정에 붙인다.

---

## `AddEditDependency` — 조건 재평가 트리거

```cpp
// VSync 설정이 켜지면 프레임 제한 설정을 비활성화
FrameRateSetting->AddEditCondition(MakeShared<FWhenCondition>(
    [VSyncSetting](const ULocalPlayer* LP, FGameSettingEditableState& State)
    {
        if (VSyncSetting->GetCurrentValue())
            State.Disable(LOCTEXT("VSync", "VSync 활성화 시 사용 불가"));
    }));

FrameRateSetting->AddEditDependency(VSyncSetting);
// VSyncSetting이 바뀔 때마다 FrameRateSetting의 EditCondition 전체 재평가
```

`AddEditDependency`는 단독으로 쓸 수 없다. `AddEditCondition`과 함께 써야 의미가 있다.

---

## `FGameSettingFilterState` — 목록 필터

Registry나 Panel이 어떤 항목을 표시할지 결정할 때 쓰는 필터 오브젝트.

```cpp
FGameSettingFilterState Filter;
Filter.bIncludeDisabled = true;    // 비활성 항목 포함 (기본 true)
Filter.bIncludeHidden = false;     // 숨겨진 항목 제외 (기본 false)
Filter.bIncludeResetable = true;   // 리셋 가능 항목만 포함
Filter.bIncludeNestedPages = false;// 하위 페이지는 제외

Filter.SetSearchText(TEXT("감도"));  // 검색어 (FText 필터링)

// 특정 항목만 허용 (AllowList가 비어있으면 모든 항목 허용)
Filter.AddSettingToAllowList(SpecificSetting);

Panel->SetFilterState(Filter);
```

검색어가 설정되면 `DevName`, `DisplayName`, `DescriptionRichText`의 평문 텍스트에서 검색한다.  
`DynamicDetails`는 검색 대상이 아니다.

### `EGameSettingChangeReason` — 변경 이유

```cpp
enum class EGameSettingChangeReason : uint8
{
    Change,            // 사용자 직접 변경
    DependencyChanged, // 의존 설정 변경으로 인한 재평가
    ResetToDefault,    // "기본값으로" 버튼
    RestoreToInitial,  // 취소 (StoreInitial 시점으로)
};
```

서브클래스에서 `OnSettingChanged(EGameSettingChangeReason Reason)`를 오버라이드해 이유에 따라 다른 처리를 할 수 있다.
