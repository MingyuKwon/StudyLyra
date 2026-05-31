# 02. Value 타입 계층 — 변경 가능한 설정 값

> 출처: `Plugins/GameSettings/Source/Public/GameSettingValue.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingValueDiscrete.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingValueScalar.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingAction.h`

---

## 계층 구조

```
UGameSetting
    ├─ UGameSettingValue          ← 취소 가능한 값의 base
    │       ├─ UGameSettingValueDiscrete   ← 선택지 목록 (해상도, 품질 등)
    │       │       └─ UGameSettingValueDiscreteDynamic  (→ 03 문서)
    │       └─ UGameSettingValueScalar    ← 슬라이더 (0.0 ~ 1.0)
    └─ UGameSettingAction         ← 버튼 클릭 동작 (값 없음)
```

---

## `UGameSettingValue` — 취소 가능한 값 base

세 가지 순수 가상 함수가 핵심이다:

```cpp
virtual void StoreInitial()     PURE_VIRTUAL(,);  // 설정 화면 열 때: 현재 값 기록
virtual void ResetToDefault()   PURE_VIRTUAL(,);  // "기본값으로" 버튼: 기본값으로 복원
virtual void RestoreToInitial() PURE_VIRTUAL(,);  // "취소" 버튼: StoreInitial 시점으로 복원
```

### 취소 흐름

```
Registry->Initialize() 완료
    └─ 모든 UGameSettingValue->StoreInitial()  ← "화면 열기 직전 값" 기록

사용자가 여러 값 변경 (즉시 메모리에 반영)

사용자가 "취소" 선택
    └─ ChangeTracker->RestoreToInitial()
            └─ 변경된 모든 Setting->RestoreToInitial()

사용자가 "적용/저장" 선택
    └─ Registry->SaveChanges()
            └─ ChangeTracker->StoreInitial() 재호출  ← 새 기준점 갱신
```

`EGameSettingChangeReason::RestoreToInitial`이 이유로 전달되므로 서브클래스에서 구분 가능하다.

---

## `UGameSettingValueDiscrete` — 선택지 목록

```cpp
// 순수 가상 함수들
virtual void SetDiscreteOptionByIndex(int32 Index) PURE_VIRTUAL(,);
virtual int32 GetDiscreteOptionIndex() const PURE_VIRTUAL(, return INDEX_NONE;);
virtual TArray<FText> GetDiscreteOptions() const PURE_VIRTUAL(, return {};);

// 선택 (구현 선택)
virtual int32 GetDiscreteOptionDefaultIndex() const { return INDEX_NONE; }
```

위젯(`UGameSettingListEntrySetting_Discrete`)이 `GetDiscreteOptions()`로 선택지를 가져와 Rotator에 표시하고, 좌/우 버튼 클릭 시 `SetDiscreteOptionByIndex()`를 호출한다.

**서브클래싱 방법:**

```cpp
class UMyResolutionSetting : public UGameSettingValueDiscrete
{
    TArray<FIntPoint> Resolutions;
    int32 CurrentIndex = 0;

    virtual void StoreInitial() override    { InitialIndex = CurrentIndex; }
    virtual void ResetToDefault() override  { CurrentIndex = DefaultIndex; Apply(); }
    virtual void RestoreToInitial() override{ CurrentIndex = InitialIndex; Apply(); }

    virtual TArray<FText> GetDiscreteOptions() const override
    {
        TArray<FText> Options;
        for (auto& R : Resolutions)
            Options.Add(FText::Format(INVTEXT("{0}x{1}"), R.X, R.Y));
        return Options;
    }

    virtual void SetDiscreteOptionByIndex(int32 Index) override
    {
        CurrentIndex = Index;
        GEngine->GameUserSettings->SetScreenResolution(Resolutions[Index]);
        NotifySettingChanged(EGameSettingChangeReason::Change);
    }
};
```

---

## `UGameSettingValueScalar` — 슬라이더

```cpp
virtual void SetValue(double Value, ...) PURE_VIRTUAL(,);
virtual double GetValue() const PURE_VIRTUAL(, return 0;);
virtual TRange<double> GetSourceRange() const PURE_VIRTUAL(, return {};);  // 실제 값 범위
virtual double GetSourceStep() const PURE_VIRTUAL(, return 0.01;);        // 스텝 단위
virtual FText GetFormattedText() const PURE_VIRTUAL(, return {};);         // "75%" 같은 표시 텍스트

// 정규화 (0.0 ~ 1.0) ↔ 실제 값 변환은 플러그인이 자동 처리
void SetValueNormalized(double NormalizedValue);
double GetValueNormalized() const;
```

위젯(`UGameSettingListEntrySetting_Scalar`)은 `SetValueNormalized()`/`GetValueNormalized()`로만 통신한다.  
실제 값 범위(`SourceRange`)와 표시 방식은 서브클래스가 정의한다.

---

## `UGameSettingAction` — 버튼 클릭 동작

값이 없다. 클릭하면 무언가를 실행한다.

```cpp
// 방법 1: 커스텀 람다
Setting->SetCustomAction(TFunction<void(ULocalPlayer*)>([](ULocalPlayer* LP)
{
    // 로그아웃, 초기화, 화면 이동 등
}));

// 방법 2: GameplayTag 기반 Named Action
Setting->SetNamedAction(TAG_GameSettings_Action_ResetAllBindings);
// Registry->OnSettingNamedActionEvent에서 태그를 처리
```

`bDirtyAction = true`로 설정하면 이 Action이 실행될 때 `SaveChanges()` 필요 상태가 된다.  
대부분의 Action은 되돌릴 수 없으므로 기본값이 `false`다.

---

## `ULyraSettingKeyboardInput` — Lyra 키 바인딩 구현

`UGameSettingValue`를 직접 상속한다 (`UGameSettingValueDiscrete`가 아님).  
선택지 목록 방식이 아니라 "키를 누르세요" 모달로 키를 받기 때문이다.

```cpp
// StoreInitial: 현재 Primary/Secondary CurrentKey 기록
void StoreInitial() override
{
    for (각 슬롯) InitialKeyMappings[Slot] = Profile->GetCurrentKey(MappingName, Slot);
}

// RestoreToInitial: 기록한 키로 MapPlayerKey 재호출
void RestoreToInitial() override
{
    for (각 슬롯) Settings->MapPlayerKey({MappingName, Slot, InitialKey}, ...);
}
```

자세한 내용은 [keybinding/04_settings_registry.md](../04_settings_registry.md) 참고.
