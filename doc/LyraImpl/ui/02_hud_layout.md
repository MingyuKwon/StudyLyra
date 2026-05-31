# HUD 레이아웃 — ULyraHUDLayout

> 출처: `UI/LyraHUDLayout.h/cpp`

---

## 역할

`ULyraHUDLayout`은 인게임 HUD의 **루트 위젯**이다.  
Experience가 로드될 때 GameFeature의 `AddWidget` 액션이 이 위젯을 `UI.Layer.Game` 레이어에 올린다.

두 가지 핵심 책임:
1. **ESC 액션** → 일시정지 메뉴 push
2. **컨트롤러 연결 끊김 감지** → 연결 끊김 화면 push/pop

---

## UI 레이어 태그

Lyra에서 사용하는 레이어 태그:

```
UI.Layer.Game    ← HUD, 크로스헤어, 체력바 등 항상 떠 있는 오버레이
UI.Layer.Menu    ← ESC 메뉴, 설정 화면, 컨트롤러 연결 끊김 화면
UI.Layer.Modal   ← 확인 다이얼로그 (Blueprint에서 정의)
```

레이어는 숫자가 높을수록 위에 쌓인다. `Game < Menu < Modal` 순.  
게임패드는 항상 가장 위 레이어만 조작한다.

---

## 1. ESC 액션 바인딩

```cpp
// LyraHUDLayout.cpp — NativeOnInitialized()
RegisterUIActionBinding(FBindUIActionArgs(
    FUIActionTag::ConvertChecked(TAG_UI_ACTION_ESCAPE),   // "UI.Action.Escape"
    false,                                                 // 힌트 바에 표시 안 함
    FSimpleDelegate::CreateUObject(this, &ThisClass::HandleEscapeAction)
));
```

```cpp
void ULyraHUDLayout::HandleEscapeAction()
{
    // EscapeMenuClass는 에디터에서 지정 (일시정지 메뉴 위젯 클래스)
    UCommonUIExtensions::PushStreamedContentToLayer_ForPlayer(
        GetOwningLocalPlayer(),
        TAG_UI_LAYER_MENU,     // "UI.Layer.Menu" 레이어에 push
        EscapeMenuClass        // 소프트 레퍼런스 → 비동기 로드 후 push
    );
}
```

`PushStreamedContentToLayer_ForPlayer` — 소프트 클래스 레퍼런스를 비동기 로드 후 push.  
`PushContentToLayer_ForPlayer` — 이미 로드된 클래스를 즉시 push.

---

## 2. 컨트롤러 연결 끊김 처리

콘솔처럼 컨트롤러가 필수인 플랫폼(`Platform.Trait.Input.PrimarlyController` 태그)에서만 동작한다.

### 활성화 조건 확인

```cpp
bool ULyraHUDLayout::ShouldPlatformDisplayControllerDisconnectScreen() const
{
    // PlatformRequiresControllerDisconnectScreen 태그 컨테이너에 있는 태그들을
    // 현재 플랫폼 트레잇이 모두 가지고 있어야 함
    return ICommonUIModule::GetSettings().GetPlatformTraits()
        .HasAll(PlatformRequiresControllerDisconnectScreen);
    // 기본값: PlatformRequiresControllerDisconnectScreen = {"Platform.Trait.Input.PrimarlyController"}
}
```

PC는 이 태그가 없으므로 연결 끊김 화면이 뜨지 않는다.

### 이벤트 구독 → 감지 → 화면 표시 흐름

```
NativeOnInitialized()
    └─ ShouldPlatformDisplayControllerDisconnectScreen() == true이면
            └─ IPlatformInputDeviceMapper::GetOnInputDeviceConnectionChange() 구독
            └─ IPlatformInputDeviceMapper::GetOnInputDevicePairingChange()    구독

[컨트롤러 연결 상태 변경 이벤트 발생]
HandleInputDeviceConnectionChanged(NewState, PlatformUserId, DeviceId)
    └─ 내 플레이어의 이벤트인지 확인 (PlatformUserId 비교)
    └─ NotifyControllerStateChangeForDisconnectScreen()

NotifyControllerStateChangeForDisconnectScreen()
    └─ 이미 처리 예약됐으면 스킵 (중복 방지)
    └─ FTSTicker로 다음 틱에 ProcessControllerDevicesHavingChangedForDisconnectScreen() 예약
           ↑ 같은 프레임에 여러 이벤트가 와도 한 번만 처리하는 디바운스 패턴

ProcessControllerDevicesHavingChangedForDisconnectScreen()
    └─ 내 PlatformUser에 매핑된 모든 InputDevice 조회
    └─ 그 중 Connected 상태인 Gamepad가 있는지 확인
    ├─ 없음 → DisplayControllerDisconnectedMenu()   ← 연결 끊김 화면 push
    └─ 있음 → HideControllerDisconnectedMenu()      ← 연결 끊김 화면 pop (이미 있으면)
```

### 화면 push/pop

```cpp
// push
void ULyraHUDLayout::DisplayControllerDisconnectedMenu_Implementation()
{
    SpawnedControllerDisconnectScreen = UCommonUIExtensions::PushContentToLayer_ForPlayer(
        GetOwningLocalPlayer(),
        TAG_UI_LAYER_MENU,
        ControllerDisconnectedScreen   // ULyraControllerDisconnectedScreen 클래스
    );
}

// pop
void ULyraHUDLayout::HideControllerDisconnectedMenu_Implementation()
{
    UCommonUIExtensions::PopContentFromLayer(SpawnedControllerDisconnectScreen);
    SpawnedControllerDisconnectScreen = nullptr;
}
```

`DisplayControllerDisconnectedMenu`와 `HideControllerDisconnectedMenu`는 `BlueprintNativeEvent`다.  
Blueprint에서 오버라이드해서 커스텀 연출(페이드 등)을 추가할 수 있다.

---

## 구조 요약

```
ULyraHUDLayout (UI.Layer.Game)
    │
    ├─ [초기화]
    │   ├─ RegisterUIActionBinding("UI.Action.Escape") → HandleEscapeAction
    │   └─ 컨트롤러 이벤트 구독 (플랫폼 조건 충족 시)
    │
    ├─ [ESC 입력]
    │   └─ HandleEscapeAction()
    │           └─ PushStreamedContentToLayer(UI.Layer.Menu, EscapeMenuClass)
    │
    └─ [컨트롤러 연결 끊김]
            └─ HandleInputDeviceConnectionChanged()
                    └─ (다음 틱) ProcessControllerDevicesHavingChangedForDisconnectScreen()
                            ├─ 게임패드 없음 → PushContentToLayer(UI.Layer.Menu, DisconnectScreen)
                            └─ 게임패드 있음 → PopContentFromLayer(DisconnectScreen)
```
