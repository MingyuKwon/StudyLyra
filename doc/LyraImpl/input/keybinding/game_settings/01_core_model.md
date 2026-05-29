# 01. UGameSetting — 설정 항목 base

> 출처: `Plugins/GameSettings/Source/Public/GameSetting.h`

---

## 역할

모든 설정 항목의 공통 base. 값을 갖지 않아도 되는 것들(컨테이너, 버튼 동작 등)까지 포함한다.  
값 변경과 취소가 필요한 항목은 `UGameSettingValue`로 서브클래싱한다.

---

## 핵심 필드

```cpp
FName DevName;                       // 코드에서 항목을 찾는 고유 식별자
FText DisplayName;                   // UI 표시 이름
FText DescriptionRichText;           // 설명 패널에 표시되는 리치 텍스트
FText WarningRichText;               // 경고 메시지 (선택)
FGameplayTagContainer Tags;          // UI 분기에 쓰는 임의 태그
```

### DevName

```cpp
Setting->SetDevName(TEXT("KeyboardInput.IA_Jump"));
Registry->FindSettingByDevName(TEXT("KeyboardInput.IA_Jump"));  // 코드에서 조회
```

Registry 내에서 유일해야 한다. 이 이름으로 설정 화면 포커스 이동(`NavigateToSetting`)에도 쓰인다.

### Tags

```cpp
Setting->AddTag(TAG_Setting_RequireRestart);   // 재시작 필요 배지 표시
Setting->AddTag(TAG_Setting_Mobile_Unsupported);
```

플러그인 자체는 태그 의미를 강제하지 않는다. UI가 태그를 보고 배지나 경고를 추가로 그린다.

---

## 초기화 lifecycle

```
Registry->Initialize(LocalPlayer)
    └─ OnInitialize() [서브클래스 구현]
            └─ 각 UGameSetting 생성 및 구성
                    └─ RegisterSetting(Setting)
                            └─ Setting->Initialize(LocalPlayer)
                                    └─ Startup()       ← 비동기 준비 작업
                                    └─ StartupComplete()
                                    └─ OnInitialized() ← 서브클래스 훅
                                    └─ StoreInitial()  ← (UGameSettingValue인 경우)
```

`Startup()`은 비동기가 필요한 경우를 위해 존재한다. 완료되면 `StartupComplete()`를 호출해 `bReady = true`로 전환한다. Registry는 모든 Setting이 Ready 상태가 될 때까지 UI를 보여주지 않는다.

---

## EditCondition 연결

```cpp
// 비활성/숨김 조건 추가
Setting->AddEditCondition(MakeShared<FWhenCondition>(
    [](const ULocalPlayer* LP, FGameSettingEditableState& State)
    {
        if (!LP->IsLocalPlayerController())
            State.Disable(LOCTEXT("OnlyForLocalPlayer", "로컬 플레이어만 변경 가능"));
    }));

// 다른 Setting이 바뀌면 이 Setting의 조건도 재평가
Setting->AddEditDependency(OtherSetting);
```

`AddEditCondition`과 `AddEditDependency`는 독립적으로 쓸 수도 있고 함께 쓸 수도 있다.  
`AddEditDependency`만 추가하면 `OtherSetting`이 변경될 때 이 Setting의 모든 `EditCondition`이 재평가된다.  
자세한 내용은 [04_edit_condition.md](04_edit_condition.md) 참고.

---

## `Apply()` — 즉시 반영 vs 지연 반영

대부분의 설정은 값이 바뀌는 즉시 게임에 반영된다.  
하지만 **해상도 변경**처럼 "확인 누르기 전까지는 적용하지 말아야 하는" 설정이 있다.  
이 경우 `Setting->Apply()`를 명시적으로 호출할 때만 실제 반영한다:

```
// Apply()가 호출되면 내부적으로 OnApply()가 실행됨
UGameSetting::Apply()
    └─ OnApply()  ← 서브클래스 구현
    └─ OnSettingAppliedEvent.Broadcast()
    └─ Registry->OnSettingApplied() 알림
```

일반 설정은 `OnApply()`를 오버라이드하지 않아도 된다. 값 변경 즉시 반영이 기본 동작이다.

---

## `GetChildSettings()` — 계층 구조

```cpp
virtual TArray<UGameSetting*> GetChildSettings() { return TArray<UGameSetting*>(); }
```

`UGameSettingCollection`이 이를 오버라이드해서 하위 항목 목록을 반환한다.  
중첩 컨테이너나 내부에만 존재하는 설정(직접 목록에 안 보이는 것)을 계층적으로 구성할 때 쓴다.

---

## `DynamicDetails` — 동적 설명 텍스트

```cpp
Setting->SetDynamicDetails(FGetGameSettingsDetails::CreateLambda(
    [](ULocalPlayer& LP) -> FText
    {
        // 런타임에 계산되는 텍스트 (예: 계정 정보, 남은 리펀드 횟수 등)
        return FText::Format(LOCTEXT("Fmt", "현재 감도: {0}"), CurrentSensitivity);
    }));
```

`DescriptionRichText`는 정적 텍스트, `DynamicDetails`는 런타임에 매번 계산된다.  
검색 인덱스에는 포함되지 않는다.
