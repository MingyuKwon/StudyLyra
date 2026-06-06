# Change Tracking — 변경 감지 & 취소/적용 패턴

> 소스:
> - `Plugins/GameSettings/Source/Public/GameSettingRegistryChangeTracker.h`
> - `Plugins/GameSettings/Source/Private/Registry/GameSettingRegistryChangeTracker.cpp`
> - `Plugins/GameSettings/Source/Public/Widgets/GameSettingScreen.h`
> - `Plugins/GameSettings/Source/Private/Widgets/GameSettingScreen.cpp`
> - `Source/LyraGame/UI/LyraSettingScreen.h/.cpp`

설정 화면에서 "무언가 바뀌었는가"를 추적하고, 적용(Apply) 또는 취소(Cancel)하는 전체 흐름.

---

## 전체 구조 개요

```
UGameSettingScreen
  ├─ FGameSettingRegistryChangeTracker   ← dirty 상태 추적기 (값 오브젝트)
  │     ├─ bSettingsChanged              ← "하나라도 바뀌었나?" 플래그
  │     └─ DirtySettings                ← 바뀐 설정 목록 (FObjectKey → UGameSetting*)
  └─ UGameSettingRegistry               ← 설정 항목 소유자, SaveChanges() 담당

ULyraSettingScreen  (UGameSettingScreen 서브클래스)
  ├─ HandleBackAction()    ← 뒤로가기
  ├─ HandleApplyAction()   ← 적용 버튼
  └─ HandleCancelChangesAction()  ← 취소 버튼
```

---

## FGameSettingRegistryChangeTracker — dirty 추적기

### 핵심 멤버

```cpp
bool bSettingsChanged = false;
bool bRestoringSettings = false;
TWeakObjectPtr<UGameSettingRegistry> Registry;
TMap<FObjectKey, TWeakObjectPtr<UGameSetting>> DirtySettings;
```

- `bSettingsChanged` — "하나라도 변경됐나" 플래그. UI가 이걸로 Apply/Cancel 버튼 표시 여부를 결정한다.
- `DirtySettings` — 변경된 설정 인스턴스 목록. Apply/RestoreToInitial 때 이 목록을 순회한다.
- `bRestoringSettings` — RestoreToInitial 진행 중 재진입 방지 플래그.

### WatchRegistry — 감시 시작

```cpp
void FGameSettingRegistryChangeTracker::WatchRegistry(UGameSettingRegistry* InRegistry)
{
    ClearDirtyState();
    StopWatchingRegistry();
    Registry = InRegistry;
    InRegistry->OnSettingChangedEvent.AddRaw(this, &FGameSettingRegistryChangeTracker::HandleSettingChanged);
}
```

Registry의 `OnSettingChangedEvent`에 구독한다.
`UGameSettingScreen::NativeOnActivated()`에서 호출되므로 화면이 활성화될 때마다 새로 연결된다.

### HandleSettingChanged — 이벤트 수신

```cpp
void FGameSettingRegistryChangeTracker::HandleSettingChanged(UGameSetting* Setting, EGameSettingChangeReason Reason)
{
    if (bRestoringSettings) return;  // 복원 중이면 무시

    bSettingsChanged = true;
    DirtySettings.Add(FObjectKey(Setting), Setting);
}
```

설정 하나가 바뀔 때마다 호출된다.
복원(Restore) 중에 발생하는 변경은 무시해 재귀 루프를 막는다.

---

## Apply / Cancel / ClearDirty — 세 가지 결말

### ApplyChanges

```cpp
void FGameSettingRegistryChangeTracker::ApplyChanges()
{
    for (auto Entry : DirtySettings)
    {
        if (UGameSettingValue* SettingValue = Cast<UGameSettingValue>(Entry.Value))
        {
            SettingValue->Apply();       // 특수 설정 반영 (예: 해상도 변경 확정)
            SettingValue->StoreInitial(); // "초기값" 기준을 현재 값으로 갱신
        }
    }
    ClearDirtyState();
}
```

`Apply()`는 대부분의 설정에서 no-op에 가깝다.
DiscreteDynamic처럼 DataSource를 쓰는 설정은 값을 이미 실시간으로 적용했기 때문이다.
`StoreInitial()`이 더 중요한데, 다음 번 Cancel 시 복원 기준점을 현재 값으로 옮긴다.

`UGameSettingScreen::ApplyChanges()`는 Tracker 완료 후 `Registry->SaveChanges()`도 호출해 디스크에 영구 저장한다.

```cpp
void UGameSettingScreen::ApplyChanges()
{
    if (ChangeTracker.HaveSettingsBeenChanged())
    {
        ChangeTracker.ApplyChanges();
        ClearDirtyState();
        Registry->SaveChanges();   // 디스크 저장
    }
}
```

### RestoreToInitial (Cancel)

```cpp
void FGameSettingRegistryChangeTracker::RestoreToInitial()
{
    TGuardValue<bool> LocalGuard(bRestoringSettings, true);  // 재진입 차단
    for (auto Entry : DirtySettings)
    {
        if (UGameSettingValue* SettingValue = Cast<UGameSettingValue>(Entry.Value))
        {
            SettingValue->RestoreToInitial();  // 화면 열기 당시 값으로 되돌림
        }
    }
    ClearDirtyState();
}
```

`TGuardValue`로 `bRestoringSettings = true`를 설정해, Restore 중 발생하는 `OnSettingChangedEvent`가 DirtySettings에 다시 쌓이지 않게 막는다.

### StoreInitial / RestoreToInitial — 값 레벨에서의 스냅샷

```cpp
// UGameSettingValueDiscreteDynamic

void StoreInitial()
{
    InitialValue = GetValueAsString();  // 현재 값을 "초기값"으로 기억
}

void RestoreToInitial()
{
    SetValueFromString(InitialValue, EGameSettingChangeReason::RestoreToInitial);
}
```

- `StoreInitial()`은 두 시점에 호출된다.
  1. `UGameSettingValue::OnInitialized()` — 화면 최초 초기화 시
  2. `ChangeTracker::ApplyChanges()` — Apply 완료 후 (다음 Cancel 기준 갱신)
- `RestoreToInitial()`은 항상 "이 화면을 열었을 때"(또는 마지막 Apply 시점)의 값으로 돌아간다.

---

## UGameSettingScreen — Screen 레벨 조율

```cpp
void UGameSettingScreen::NativeOnActivated()
{
    Super::NativeOnActivated();
    ChangeTracker.WatchRegistry(Registry);          // 감시 시작
    OnSettingsDirtyStateChanged(HaveSettingsBeenChanged());  // 초기 UI 상태 반영
}

void UGameSettingScreen::HandleSettingChanged(UGameSetting* Setting, EGameSettingChangeReason Reason)
{
    OnSettingsDirtyStateChanged(true);  // UI에 "dirty됨" 알림
}
```

`OnSettingsDirtyStateChanged(bool bSettingsDirty)`는 BlueprintNativeEvent다.
서브클래스가 이걸 오버라이드해서 UI를 제어한다.

---

## ULyraSettingScreen — Lyra의 구체 구현

### 버튼 바인딩 제어

```cpp
void ULyraSettingScreen::OnSettingsDirtyStateChanged_Implementation(bool bSettingsDirty)
{
    if (bSettingsDirty)
    {
        // 변경 있음 → Apply·Cancel 버튼 활성화
        if (!GetActionBindings().Contains(ApplyHandle))  AddActionBinding(ApplyHandle);
        if (!GetActionBindings().Contains(CancelChangesHandle)) AddActionBinding(CancelChangesHandle);
    }
    else
    {
        // 변경 없음 → 버튼 제거
        RemoveActionBinding(ApplyHandle);
        RemoveActionBinding(CancelChangesHandle);
    }
}
```

"변경이 없을 때 팝업"이 아니라, 변경이 **있을 때 버튼을 추가**하고 없을 때 **버튼을 제거**하는 방식이다.
팝업 UI가 아닌 버튼 가시성으로 상태를 표현한다.

### 뒤로가기 — 팝업 없이 즉시 Apply

```cpp
void ULyraSettingScreen::HandleBackAction()
{
    if (AttemptToPopNavigation())  // 하위 페이지가 있으면 뒤로
        return;

    ApplyChanges();       // 변경 사항 자동 적용 (확인 팝업 없음)
    DeactivateWidget();   // 화면 닫기
}
```

> **참고**  
> Lyra는 Back 버튼에 "변경이 있는데 나가시겠습니까?" 팝업을 띄우지 않는다.
> 뒤로가면 무조건 적용된다.
> 취소하려면 반드시 Cancel 버튼을 명시적으로 눌러야 한다.

---

## 전체 이벤트 흐름 요약

```
[유저가 설정 값 변경]
  │
  ▼
UGameSettingValueDiscreteDynamic::SetDiscreteOptionByIndex()
  → NotifySettingChanged(EGameSettingChangeReason::Change)
  → UGameSetting::OnSettingChangedEvent 발동

  │  (Registry가 구독 중)
  ▼
UGameSettingRegistry::HandleSettingChanged()
  → Registry::OnSettingChangedEvent 발동

  │  (ChangeTracker + Screen 둘 다 구독)
  ▼
FGameSettingRegistryChangeTracker::HandleSettingChanged()
  → bSettingsChanged = true
  → DirtySettings에 추가

UGameSettingScreen::HandleSettingChanged()
  → OnSettingsDirtyStateChanged(true)
  → (Lyra) Apply·Cancel 버튼 AddActionBinding

---

[Apply 버튼 또는 Back 버튼]
  ▼
UGameSettingScreen::ApplyChanges()
  → ChangeTracker.ApplyChanges()
       → 각 dirty setting: Apply() + StoreInitial()
  → ClearDirtyState() → OnSettingsDirtyStateChanged(false) → 버튼 제거
  → Registry->SaveChanges() → 디스크 저장

---

[Cancel 버튼]
  ▼
UGameSettingScreen::CancelChanges()
  → ChangeTracker.RestoreToInitial()
       → 각 dirty setting: RestoreToInitial() (InitialValue로 복원)
  → ClearDirtyState() → OnSettingsDirtyStateChanged(false) → 버튼 제거
```

---

## 팝업("변경 사항 저장하시겠습니까?") 직접 구현하는 방법

Lyra 기본 구현에는 이 팝업이 없다.
추가하려면 `HandleBackAction()`을 오버라이드해 `HaveSettingsBeenChanged()`를 체크한 뒤 CommonUI 다이얼로그를 띄우면 된다.

```cpp
void UMySettingScreen::HandleBackAction()
{
    if (AttemptToPopNavigation()) return;

    if (HaveSettingsBeenChanged())
    {
        // CommonUI 확인 다이얼로그 띄우기
        // 확인 → ApplyChanges() → DeactivateWidget()
        // 취소 → CancelChanges() → DeactivateWidget()
        ShowUnsavedChangesDialog();
        return;
    }

    DeactivateWidget();
}
```

---

## 내 노트

- `ChangeTracker`가 `UGameSettingScreen`의 멤버(값 오브젝트)라서 Screen 생명주기와 완전히 일치한다. 별도 관리가 필요 없다.
- `DirtySettings`는 `TWeakObjectPtr`로 들고 있어서, 설정이 GC되더라도 크래시가 나지 않는다.
- `RestoreToInitial` 중 `bRestoringSettings` 가드가 없으면, 각 설정값이 복원될 때 다시 `OnSettingChangedEvent`를 발동해 ChangeTracker가 그것들을 다시 DirtySettings에 추가하는 무한루프가 생긴다.
- Apply 후 `StoreInitial()`을 호출해 기준점을 갱신하기 때문에, Apply → 재변경 → Cancel을 해도 Apply 직후 값으로 돌아간다 (화면 최초 열기 시점이 아닌).
