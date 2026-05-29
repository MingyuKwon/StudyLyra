# 07. GameSettings 플러그인 기반 — 설정 화면 MVC 프레임워크

> 출처: `Plugins/GameSettings/Source/Public/GameSetting.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingValue.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingRegistry.h`  
>        `Plugins/GameSettings/Source/Public/GameSettingCollection.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/GameSettingListEntry.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/Misc/GameSettingPressAnyKey.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/Misc/KeyAlreadyBoundWarning.h`

---

## 왜 이 플러그인이 존재하는가

설정 화면을 날 것으로 만들면 두 가지 문제가 생긴다:

1. **값 관리 중복**: "열었을 때 스냅샷 저장 → 취소 시 복원"을 각 위젯이 각자 구현
2. **UI와 데이터 결합**: 위젯이 실제 설정 값을 직접 들고 있어서 교체가 어려움

GameSettings 플러그인은 이 두 문제를 MVC 구조로 해결한다:

```
Model  : UGameSetting / UGameSettingValue (설정 값과 상태)
View   : UGameSettingListEntry* (위젯, Model을 표시)
Control: UGameSettingRegistry (설정 항목 목록 관리, SaveChanges)
```

---

## 전체 클래스 계층

```
UObject
└─ UGameSetting                       ← 모든 설정 항목의 base
        ├─ DevName: FName              ← 코드에서 찾을 때 쓰는 고유 식별자
        ├─ DisplayName: FText          ← UI 표시 이름
        ├─ Tags: FGameplayTagContainer ← UI 분기에 쓰는 태그 (플랫폼별 숨김 등)
        ├─ EditConditions              ← 비활성/숨김 조건
        │
        ├─ UGameSettingCollection      ← 설정 항목 묶음 (탭, 섹션)
        │       └─ UGameSettingCollectionPage  ← 하위 페이지로 이동하는 항목
        │
        └─ UGameSettingValue           ← 값을 가지며 변경/취소가 가능한 설정
                ├─ StoreInitial()      ← 화면 열 때 현재 값 스냅샷
                ├─ ResetToDefault()    ← 기본값으로 초기화
                ├─ RestoreToInitial()  ← StoreInitial() 시점 값으로 복원 (취소)
                │
                ├─ UGameSettingValueDiscrete   ← 선택지 목록 (해상도, 품질 등)
                │       └─ GetDiscreteOptions() / SetDiscreteOptionByIndex()
                │
                └─ UGameSettingValueScalar     ← 0.0~1.0 슬라이더 (감도 등)

UObject
└─ UGameSettingRegistry               ← 최상위 설정 관리자
        ├─ Initialize(LocalPlayer)     ← OnInitialize() 가상 함수 호출
        ├─ SaveChanges()               ← 모든 설정 저장
        ├─ RegisterSetting()           ← 설정 항목 등록
        ├─ FindSettingByDevName()      ← 코드에서 특정 설정 항목 조회
        ├─ TopLevelSettings[]          ← 최상위 항목 목록
        └─ RegisteredSettings[]        ← 검색용 전체 플랫 목록
```

---

## `UGameSetting` — 설정 항목 base

### EditCondition — 비활성/숨김 제어

```cpp
// 플랫폼이 특정 기능을 지원할 때만 표시
Setting->AddEditCondition(FWhenPlatformHasTrait::KillIfMissing(TAG_Platform_Trait_Input_HardwareCursor));

// 조건을 계산할 때 다른 설정의 현재 값을 참조해야 하면
Setting->AddEditDependency(OtherSetting);  // OtherSetting이 바뀌면 재평가
```

EditCondition은 두 가지 결과를 만든다:
- **Invisible**: 항목이 목록에서 안 보임
- **Disabled**: 항목이 보이지만 회색으로 비활성화됨

### Tags — UI 분기

```cpp
Setting->AddTag(TAG_Setting_RequireRestart);  // "재시작 필요" 배지 표시
```

---

## `UGameSettingValue` — 취소 가능한 값

`StoreInitial` / `RestoreToInitial` 패턴이 핵심이다.

```
설정 화면 열기
    └─ Registry->Initialize() 내부에서 모든 Setting->StoreInitial() 호출
            └─ 현재 값을 InitialValue로 기록

사용자가 값을 변경
    └─ Setting 내부 값만 바뀜 (게임에 즉시 반영 여부는 Setting마다 다름)

취소 (ESC)
    └─ 각 Setting->RestoreToInitial() 호출
            └─ InitialValue로 되돌림

확인/적용
    └─ Registry->SaveChanges()
            └─ 각 Setting의 변경된 값을 실제로 저장
            └─ StoreInitial() 재호출 → 새 초기값으로 갱신
```

---

## 위젯 계층 — View

```
UCommonUserWidget
└─ UGameSettingListEntryBase          ← 모든 설정 위젯의 base
        ├─ SetSetting(UGameSetting*)  ← Model 연결
        ├─ OnSettingChanged()         ← Model 변경 시 UI 갱신
        └─ RefreshEditableState()     ← 비활성/숨김 상태 반영
                │
                ├─ UGameSettingListEntry_Setting       ← 이름 표시 (Text_SettingName)
                │       ├─ UGameSettingListEntrySetting_Discrete  ← 좌우 버튼으로 선택
                │       ├─ UGameSettingListEntrySetting_Scalar    ← 슬라이더
                │       ├─ UGameSettingListEntrySetting_Action    ← 버튼 클릭 동작
                │       └─ UGameSettingListEntrySetting_Navigation ← 하위 페이지 이동
                │
                └─ (Lyra 확장)
                        └─ ULyraSettingsListEntrySetting_KeyboardInput
                                ← 키 바인딩 전용 위젯 (05 문서 참고)
```

위젯은 `IUserObjectListEntry`를 구현한다 → `UListView`에 데이터 오브젝트로 바인딩 가능.  
`SetSetting()`이 호출되면 위젯이 Model을 구독하고 변경 시 자동으로 갱신된다.

---

## 키 바인딩 전용 위젯 — `UGameSettingPressAnyKey`

키 캡처 모달 위젯이다. `UCommonActivatableWidget` 기반.

```cpp
UCLASS(Abstract)
class UGameSettingPressAnyKey : public UCommonActivatableWidget
{
    FOnKeySelected OnKeySelected;          // 키 선택 완료 이벤트
    FOnKeySelectionCanceled OnKeySelectionCanceled;  // 취소 이벤트
};
```

### 동작 원리

```
위젯 활성화 (NativeOnActivated)
    └─ FSettingsPressAnyKeyInputPreProcessor 등록
            └─ 모든 키 입력을 가로채서 HandleKeySelected(FKey) 호출
               (일반 Enhanced Input 경로를 우회)

키 선택
    └─ HandleKeySelected(InKey)
            └─ OnKeySelected.Broadcast(InKey)
            └─ Dismiss() → 위젯 비활성화 + InputPreProcessor 해제

취소
    └─ HandleKeySelectionCanceled()
            └─ OnKeySelectionCanceled.Broadcast()
            └─ Dismiss()

위젯 비활성화 (NativeOnDeactivated)
    └─ InputPreProcessor 해제 (키 가로채기 중단)
```

**`FSettingsPressAnyKeyInputPreProcessor`**: `IInputProcessor` 구현체.  
Enhanced Input을 거치지 않고 슬레이트 레벨에서 원시 키 입력을 직접 수신한다.  
이 덕분에 현재 IMC에 없는 키도 감지할 수 있다.

### `UKeyAlreadyBoundWarning` — 중복 경고 모달

`UGameSettingPressAnyKey`의 서브클래스. 구조는 동일하되 경고 텍스트 블록이 추가된다.

```cpp
class UKeyAlreadyBoundWarning : public UGameSettingPressAnyKey
{
    void SetWarningText(const FText& InText);  // "이 키는 이미 X에 바인딩되어 있습니다"
    void SetCancelText(const FText& InText);   // "그래도 변경하려면 키를 누르세요"
};
```

Lyra에서 이 위젯을 띄우는 시점: 사용자가 선택한 키가 이미 다른 액션에 할당된 경우.  
"교체"를 선택하면 기존 바인딩을 해제하고 새 키를 등록한다.

---

## Lyra와의 연결 지점

| GameSettings 플러그인 | Lyra 서브클래스 |
|----------------------|----------------|
| `UGameSettingRegistry` | `ULyraGameSettingRegistry` (04 문서) |
| `UGameSettingValue` | `ULyraSettingKeyboardInput` (04 문서) |
| `UGameSettingListEntryBase` | `ULyraSettingsListEntrySetting_KeyboardInput` (05 문서) |
| `UGameSettingPressAnyKey` | 그대로 사용 (서브클래싱 없음) |
| `UKeyAlreadyBoundWarning` | 그대로 사용 (서브클래싱 없음) |

키 캡처 모달과 중복 경고 모달은 플러그인 클래스를 그대로 쓴다.  
Lyra가 서브클래싱하는 것은 데이터 모델(`Value`)과 위젯(`ListEntry`) 쪽이다.
