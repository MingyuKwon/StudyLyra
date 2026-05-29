# 07. 키 바인딩 전용 위젯 — PressAnyKey / KeyAlreadyBoundWarning

> 출처: `Plugins/GameSettings/Source/Public/Widgets/Misc/GameSettingPressAnyKey.h`  
>        `Plugins/GameSettings/Source/Public/Widgets/Misc/KeyAlreadyBoundWarning.h`

---

## 위치와 역할

일반 설정 위젯과 달리 이 두 위젯은 **모달**이다.  
CommonUI의 Modal Layer에 쌓여 설정 목록 위를 덮는다.

```
[UI.Layer.Modal]
    UGameSettingPressAnyKey      ← "키를 누르세요" 대기 화면
        └─ UKeyAlreadyBoundWarning  ← "이 키는 이미 X에 할당되어 있습니다. 교체하겠습니까?"
```

Lyra 위젯(`ULyraSettingsListEntrySetting_KeyboardInput`)이 이 모달들을 띄우고 결과를 받아 `MapPlayerKey()`를 호출한다.

---

## `UGameSettingPressAnyKey` — 키 캡처 모달

```cpp
class UGameSettingPressAnyKey : public UCommonActivatableWidget
{
    FOnKeySelected OnKeySelected;              // 키 선택 완료 이벤트
    FOnKeySelectionCanceled OnKeySelectionCanceled;  // 취소 이벤트
};
```

### `FSettingsPressAnyKeyInputPreProcessor` — 핵심 메커니즘

모달이 활성화되면 슬레이트 `IInputProcessor`를 등록한다:

```
NativeOnActivated()
    └─ InputProcessor = MakeShared<FSettingsPressAnyKeyInputPreProcessor>()
    └─ FSlateApplication::Get().RegisterInputPreProcessor(InputProcessor)
            ← 슬레이트 레벨에서 모든 키 입력을 가장 먼저 가로챔
            ← Enhanced Input, InputComponent 바인딩보다 먼저 실행됨
```

왜 `IInputProcessor`를 쓰는가:
- 현재 IMC에 등록되지 않은 키도 감지해야 한다 (리맵 대상 키가 아직 바인딩 안 됐을 수 있음)
- Enhanced Input의 `AbilityInputTag` 바인딩이 모달 뒤에서 잘못 발동되면 안 된다
- `IInputProcessor`는 Enhanced Input보다 먼저 실행되어 입력을 소비(`Handled = true`)할 수 있다

```
키 입력 발생
    └─ FSettingsPressAnyKeyInputPreProcessor::HandleKeyDownEvent()
            └─ HandleKeySelected(InKey) 호출
                    └─ OnKeySelected.Broadcast(InKey)
                    └─ Dismiss()
                            └─ InputPreProcessor 해제
                            └─ DeactivateWidget()  ← 모달 닫기
```

### 취소

ESC 키 또는 게임패드 B 버튼:

```
HandleKeySelectionCanceled()
    └─ OnKeySelectionCanceled.Broadcast()
    └─ Dismiss()
```

`bKeySelected` 플래그로 Dismiss가 "선택 후 닫힘"인지 "취소로 닫힘"인지 구분한다.

### `NativeOnDeactivated()` — 정리

```
NativeOnDeactivated()
    └─ FSlateApplication::Get().UnregisterInputPreProcessor(InputProcessor)
    └─ InputProcessor.Reset()
```

위젯이 비활성화될 때 반드시 InputPreProcessor를 해제한다.  
해제하지 않으면 모달이 닫힌 후에도 모든 키 입력이 가로막힌다.

---

## `UKeyAlreadyBoundWarning` — 중복 경고 모달

`UGameSettingPressAnyKey`의 서브클래스다. 키 캡처 기능은 동일하고, 경고 텍스트 블록이 추가된다.

```cpp
class UKeyAlreadyBoundWarning : public UGameSettingPressAnyKey
{
    void SetWarningText(const FText& InText);  // BindWidget: UTextBlock* WarningText
    void SetCancelText(const FText& InText);   // BindWidget: UTextBlock* CancelText
};
```

### Lyra에서 띄우는 시점

```
ULyraSettingsListEntrySetting_KeyboardInput::ChangeBinding(SlotIndex)
    └─ PressAnyKey 모달 열기
            └─ OnKeySelected: 선택된 키가 다른 액션에 이미 바인딩되어 있는가 확인
                    └─ 없음 → MapPlayerKey() 즉시 호출
                    └─ 있음 → PressAnyKey 모달 닫고 KeyAlreadyBoundWarning 모달 열기
                            └─ SetWarningText("이 키는 이미 'X'에 할당되어 있습니다")
                            └─ SetCancelText("그래도 변경하려면 키를 누르세요 / 취소")
                                    └─ OnKeySelected (같은 키를 다시 누름)
                                            └─ 기존 바인딩 해제 + 새 키로 MapPlayerKey()
                                    └─ OnKeySelectionCanceled → 변경 취소
```

### 왜 `UKeyAlreadyBoundWarning`이 `UGameSettingPressAnyKey`를 상속하는가

"교체하겠습니까?" 화면도 결국 다시 키를 누르는 것으로 확인한다.  
"교체" = 같은 키를 한 번 더 누름 → `OnKeySelected` 발동.  
"취소" = ESC 또는 B 버튼 → `OnKeySelectionCanceled` 발동.

동일한 키 캡처 메커니즘을 재사용할 수 있으므로 상속 구조가 자연스럽다.

---

## 요약 — 두 위젯의 차이

| | `UGameSettingPressAnyKey` | `UKeyAlreadyBoundWarning` |
|--|--|--|
| 역할 | 키 캡처 | 중복 경고 + 재확인 |
| 추가 UI | 없음 (Abstract, BP에서 구현) | `WarningText`, `CancelText` TextBlock |
| 이벤트 | `OnKeySelected`, `OnKeySelectionCanceled` | 동일 (상속) |
| 활성화 시점 | 바인딩 버튼 클릭 | 중복 키 감지 후 |
