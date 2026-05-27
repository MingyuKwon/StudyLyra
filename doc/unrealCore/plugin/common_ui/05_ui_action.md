# UIAction 바인딩 — 태그 기반 입력 처리

> 관련 소스: `UI/LyraHUDLayout.h/cpp`

---

## 개념

CommonUI의 UIAction은 **"어떤 키인지"가 아니라 "어떤 의도인지"를 태그로 바인딩**하는 시스템이다.

```
일반 방식:  버튼 클릭 → OnClicked → 직접 처리
UIAction:  "UI.Action.Escape" 태그 발생 → 콜백 → 처리
           "UI.Action.Escape" ← ESC키, B버튼 등 어디서든 발생 가능
```

실제 키(ESC, B버튼)와 태그(`UI.Action.Escape`)의 연결은 `CommonUIInputData` DataAsset에서 설정한다.  
코드에서는 태그만 사용하므로 키 변경 없이 플랫폼별로 다른 키를 매핑할 수 있다.

---

## RegisterUIActionBinding() 사용법

```cpp
// LyraHUDLayout.cpp
void ULyraHUDLayout::NativeOnInitialized()
{
    Super::NativeOnInitialized();

    // "UI.Action.Escape" 태그가 발생하면 HandleEscapeAction() 호출
    RegisterUIActionBinding(FBindUIActionArgs(
        FUIActionTag::ConvertChecked(TAG_UI_ACTION_ESCAPE),  // 태그
        false,                                                // bDisplayInActionBar
        FSimpleDelegate::CreateUObject(this, &ThisClass::HandleEscapeAction)  // 콜백
    ));
}
```

`bDisplayInActionBar = true`로 설정하면 화면 하단의 "버튼 힌트 바"에 자동으로 표시된다.

---

## CommonUIInputData — 태그 ↔ 키 매핑

DataAsset으로 설정한다. 프로젝트 세팅 → Common Input Settings에서 지정.

```
CommonUIInputData
    └─ Actions
            ├─ ActionTag: "UI.Action.Back"
            │   ├─ Keys: [Gamepad_FaceButton_Right]  (B버튼)
            │   └─ Keys: [Escape]
            │
            ├─ ActionTag: "UI.Action.Escape"
            │   └─ Keys: [Escape], [Gamepad_Special_Left] (메뉴 버튼)
            │
            └─ ActionTag: "UI.Action.Confirm"
                ├─ Keys: [Enter]
                └─ Keys: [Gamepad_FaceButton_Bottom]  (A버튼)
```

코드에서는 이 DataAsset을 직접 건드리지 않고, 태그만 참조한다.

---

## UCommonBoundActionButton — 버튼에 UIAction 자동 연결

`ULyraBoundActionButton`의 부모 클래스.  
버튼에 UIAction 태그를 지정하면:
1. 해당 키를 누를 때 버튼이 자동으로 클릭됨
2. 버튼 위에 현재 플랫폼에 맞는 키 아이콘이 자동 표시됨

```
에디터에서 설정:
ULyraBoundActionButton → TriggeringInputAction: "UI.Action.Confirm"

→ A버튼(게임패드) 또는 Enter(키보드)를 누르면 이 버튼이 클릭됨
→ 버튼 위에 A버튼 아이콘 또는 Enter 키 이미지 자동 표시
```

---

## 버튼 힌트 바 — ActionBar

화면 하단에 "A: 확인  B: 취소  Y: 초기화" 처럼 표시되는 UI.  
`RegisterUIActionBinding()`에서 `bDisplayInActionBar = true`로 등록한 액션들이 자동으로 여기 표시된다.

```
[화면 하단]
🅐 확인  🅑 취소  🟡 설정 초기화

위젯이 pop 되면 → 해당 위젯이 등록한 액션들이 자동으로 사라짐
다른 위젯이 push 되면 → 그 위젯의 액션들이 자동으로 표시됨
```

힌트 바 위젯은 `UCommonActionBar` (또는 프로젝트별 커스텀)로 구현한다.

---

## 내부 파이프라인 — 입력이 어떻게 바인딩에 도달하는가

CommonUI는 `UCommonGameViewportClient`를 필수로 사용한다 (없으면 에러 로그 출력).  
입력이 Slate Tunnel/Bubble을 통과한 뒤 GameViewportClient에 도달하는 시점에 가로챈다.

```
물리 입력
    │
    ▼
FSlateApplication → Tunnel → Bubble (Slate 위젯)
    │ Slate가 소비 못하면
    ▼
UCommonGameViewportClient::InputKey()
    ├─ [1] CommonUI ActionRouter->ProcessInput()   ← 등록된 UIAction 바인딩 탐색
    │       ├─ Handled        → return true  (Enhanced Input 못 받음)
    │       ├─ BlockGameInput → return true  (게임 입력 차단)
    │       └─ Unhandled      ↓
    └─ [2] Super::InputKey()  → PlayerController → UEnhancedPlayerInput
```

소스 주석 원문: `"The input is fair game for handling - the UI gets first dibs"`

`ActionRouter->ProcessInput()`는 현재 활성화된 위젯 스택을 순회하며 등록된 바인딩 중 이 키에 반응하는 것을 찾는다. 찾으면 콜백을 실행하고 `Handled`를 반환해 게임 입력을 막는다.

### Slate와 ActionRouter의 역할 분담

ActionRouter는 Slate가 소비하지 않은 입력만 받는다. 따라서 두 시스템이 담당하는 입력이 명확히 나뉜다.

| 시스템 | 담당 입력 | 예시 |
|--------|----------|------|
| Slate Navigation | 방향키/스틱 → 포커스 이동 | 스틱 아래 → 다음 버튼으로 이동 |
| Slate OnKeyDown | 포커스된 위젯의 확인 입력 | A버튼 → 포커스된 버튼 클릭 |
| CommonUI ActionRouter | 컨텍스트 전체 바인딩 | ESC → 메뉴 닫기 (포커스 위치 무관) |

```
A버튼 (버튼이 포커스된 상태)
    Slate Bubble → SCommonButton::OnKeyDown(A) → Handled()
    → GameViewportClient까지 내려오지 않음 → ActionRouter 못 봄

ESC키 (어떤 위젯도 ESC를 처리 안 할 때)
    Slate Bubble → Unhandled() → UCommonGameViewportClient::InputKey()
    → ActionRouter → "UI.Action.Escape" 바인딩 → HandleEscapeAction()
```

Slate 포커스 시스템은 ActionRouter와 별개로 완전히 유효하다.  
포커스 이동과 포커스된 버튼 클릭은 Slate가 처리하고, ActionRouter는 거기서 걸러지고 남은 입력만 받는다.

### Enhanced Input과의 연동

`UCommonUIInputData`에 `UInputAction` 에셋을 지정하면, ActionRouter가 현재 활성 IMC를 조회해서 "이 IA에 어떤 키가 매핑되어 있는가"를 읽어온다.  
Enhanced Input 파이프라인을 직접 타지 않고 IMC 매핑 테이블만 참조하는 방식이다.

```
EnhancedInputClickAction = IA_Confirm

ActionRouter가 키 입력 수신 시:
  현재 IMC 조회 → "IA_Confirm = Gamepad_FaceButton_Bottom (A버튼)"
  → A버튼 입력 → UI Click 처리 (Enhanced Input까지 안 내려감)
```

게임의 `IA_Confirm`과 UI의 확인 버튼이 **같은 UInputAction 에셋을 참조**하기 때문에,  
키 매핑을 한 곳에서만 관리해도 게임과 UI 양쪽에 자동으로 반영된다.

> **Lyra는 Enhanced Input UI 연동을 쓰지 않는다.**  
> `Config/DefaultGame.ini`에 `IsEnhancedInputSupportEnabled` 설정이 없고,  
> `B_CommonInputData.uasset` (구형 DataTable 기반)을 사용한다.  
> `LyraHUDLayout`의 `RegisterUIActionBinding`도 태그 기반 구형 방식이다.

---

## 주의: 위젯이 활성화 중일 때만 바인딩 유효

`RegisterUIActionBinding()`으로 등록한 바인딩은 해당 위젯이 **활성화 상태일 때만** 유효하다.

```
위젯 A (Menu 화면) → "UI.Action.Escape" 바인딩 등록
    위젯 B (Modal) push → B가 활성화됨
    B가 활성화된 동안 ESC를 누르면 → A의 바인딩이 아닌 B의 바인딩이 실행됨
    B가 pop 되면 → A의 바인딩이 다시 유효해짐
```

이 우선순위 처리를 CommonUI가 스택 기반으로 자동 관리한다.
