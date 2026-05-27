# 키 바인딩 변경 (런타임 리맵핑)

> 출처: `Input/LyraInputUserSettings.h/cpp`, `Input/LyraPlayerMappableKeyProfile.h/cpp`,  
>        `Settings/CustomSettings/LyraSettingKeyboardInput.cpp`,  
>        `Settings/Widgets/LyraSettingsListEntrySetting_KeyboardInput.cpp`

---

## 핵심 질문 3가지

1. **바인딩한 결과가 어디에 저장되는가?**
2. **저장된 결과가 어떻게 EnhancedInput에 반영되는가?**
3. **"키를 누르세요" 감지는 어떻게 동작하는가?**

---

## 1. 저장 위치 — 데이터 계층

```
UEnhancedInputLocalPlayerSubsystem
    └─ GetUserSettings()
            └─ ULyraInputUserSettings  (UEnhancedInputUserSettings 상속)
                    └─ GetAllAvailableKeyProfiles()
                            └─ ULyraPlayerMappableKeyProfile  (프로필 1개 = 키 배치 세트)
                                    └─ GetPlayerMappingRows()
                                            └─ FKeyMappingRow  (액션 1개)
                                                    └─ TSet<FPlayerKeyMapping>  Mappings
                                                            ├─ Slot: First  → CurrentKey: FKey("E")
                                                            └─ Slot: Second → CurrentKey: FKey("Tab")
```

`FPlayerKeyMapping.CurrentKey` — 사용자가 변경한 현재 키.  
`FPlayerKeyMapping.DefaultKey` — 변경 전 원래 키 (ResetToDefault 시 여기로 복원).  
`IsCustomized()` — `CurrentKey != DefaultKey`이면 true.

### 물리 저장

`ULyraInputUserSettings`는 `ULyraSettingsShared`와 함께 **SaveGame 시스템**으로 직렬화된다.

```
ULyraSettingsShared::SaveSettings()
    └─ ULocalPlayerSaveGame::AsyncSave()
            └─ ULyraInputUserSettings::Serialize()  ← 키 바인딩 데이터 포함
                    → Saved/SaveGames/<PlayerName>.sav
```

클라우드 세이브 호환 형식이므로 다른 기기에서 로그인하면 바인딩이 복원된다.

---

## 2. 저장 → EnhancedInput 반영 흐름

`MapPlayerKey()`만 호출하면 메모리 내 값만 바뀐다.  
**반드시 `ApplySettings()`까지 호출해야** 실제 게임 입력에 반영된다.

```
[1단계] 설정 값 변경 — 메모리
ULyraSettingKeyboardInput::ChangeBinding(Slot, NewKey)
    └─ FMapPlayerKeyArgs Args = { MappingName, Slot, NewKey }
    └─ UEnhancedInputUserSettings::MapPlayerKey(Args, FailureReason)
            └─ 프로필 내 FPlayerKeyMapping.CurrentKey = NewKey  (메모리만 변경)
            └─ NotifySettingChanged() → UI 갱신 이벤트 (버튼 텍스트 갱신)

[2단계] EnhancedInput에 적용
ULyraInputUserSettings::ApplySettings()
    └─ Super::ApplySettings()  (UEnhancedInputUserSettings)
            └─ UEnhancedInputLocalPlayerSubsystem을 통해
               현재 활성화된 모든 IMC의 키 매핑을 CurrentKey로 덮어씀
            └─ 이 순간부터 게임 내에서 새 키로 입력이 들어옴
```

### IMC 런타임 패치 원리

EnhancedInput은 `FPlayerKeyMapping.CurrentKey`를 보고 해당 `UInputAction`에 연결된  
**IMC 내 키를 런타임으로 오버라이드**한다.  
원본 IMC 에셋 자체는 건드리지 않고, 플레이어별 오버레이 형태로 덮어쓴다.

```
원본 IMC:   "점프" InputAction ← E키
적용 후:   "점프" InputAction ← F키  (플레이어 오버레이)

원본 IMC 에셋은 변경 없음. 이 플레이어에게만 F로 동작.
```

`ApplySettings()` 호출 시점:
- 설정 화면에서 "적용" 또는 "확인" 버튼을 누를 때
- 설정 화면을 닫을 때 (GameSettingRegistry의 Apply 정책에 따라 다름)

---

## 3. "키를 누르세요" 감지 — PressAnyKey 위젯

버튼 클릭 → `UGameSettingPressAnyKey` 위젯이 `UI.Layer.Modal`에 push.  
이 위젯이 Slate 레벨에서 키 입력을 직접 캡처한다.

### 작동 원리

```
Button_PrimaryKey 클릭
    └─ PushContentToLayer_ForPlayer(UI.Layer.Modal, PressAnyKeyPanelClass)
            └─ UGameSettingPressAnyKey 위젯 생성 & 활성화
                    ├─ Modal 레이어 → 게임 입력 차단, UI 입력만 수신
                    ├─ NativeOnActivated() → FlushPressedKeys()  ← 현재 눌린 키 초기화
                    └─ Slate OnKeyDown 이벤트 캡처 시작

[사용자가 F키 누름]
    └─ OnKeyDown(F) 수신
            ├─ 무시할 키 필터링 (순수 한정자 키 Ctrl/Shift/Alt 단독 → 무시)
            ├─ ESC → 취소로 처리 (OnKeySelectionCanceled 브로드캐스트)
            └─ 그 외 → OnKeySelected.Broadcast(FKey("F"))
```

### 키 선택 후 처리

```
HandlePrimaryKeySelected(FKey("F"), PressAnyKeyPanel)
    ├─ PressAnyKeyPanel 이벤트 구독 해제
    ├─ PressAnyKeyPanel DeactivateWidget()  ← Modal 자동 닫힘
    └─ ChangeBinding(Slot=0, FKey("F")) 호출
```

### 중복 키 경고 흐름

```
ChangeBinding(Slot, FKey("F"))
    └─ GetAllMappedActionsFromKey(Slot, FKey("F"), OutActions)
            └─ Profile->GetMappingNamesForKey(FKey("F"), OutActionNames)

    ├─ OutActions 비어있음 → KeyboardInputSetting->ChangeBinding() 바로 호출

    └─ OutActions 있음 (중복)
            └─ UKeyAlreadyBoundWarning 위젯 push (UI.Layer.Modal)
                    경고: "F는 이미 [달리기]에 바인딩되어 있습니다. 재바인딩하시겠습니까?"
                    안내: "ESC로 취소하거나, F를 다시 누르면 재바인딩됩니다."

                [F 다시 누름 - 확인]
                    HandlePrimaryDuplicateKeySelected()
                        └─ KeyboardInputSetting->ChangeBinding(0, OriginalKeyToBind)

                [ESC 누름 - 취소]
                    HandleKeySelectionCanceled()
                        └─ 아무것도 변경하지 않음
```

ESC 자체는 `UGameSettingPressAnyKey`에서 "취소" 신호로 예약되어 있어  
ESC 키를 새 바인딩으로 지정하는 것은 불가능하다.

---

## 전체 흐름 요약

```
[① 키 입력 캡처]
Button 클릭 → PressAnyKey 위젯 push (Modal)
    → Slate OnKeyDown으로 키 감지
    → OnKeySelected 이벤트 발생

[② 중복 확인]
중복 없음 → 바로 MapPlayerKey()
중복 있음 → 경고 위젯 → 확인 시 MapPlayerKey()

[③ 메모리 반영]
MapPlayerKey()
    → FPlayerKeyMapping.CurrentKey 업데이트
    → UI 버튼 텍스트 갱신

[④ EnhancedInput 적용]
ApplySettings()
    → IMC 런타임 오버라이드
    → 즉시 게임 내에서 새 키로 동작

[⑤ 영구 저장]
ULyraSettingsShared::SaveSettings()
    → ULyraInputUserSettings 직렬화 포함
    → Saved/SaveGames/ 에 기록
```
