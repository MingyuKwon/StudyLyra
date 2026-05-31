# 새 UI 화면 만들기 — Lyra 패턴

> Lyra 방식으로 새 화면을 만들 때 따라야 할 체크리스트.

---

## 1단계 — Blueprint 위젯 클래스 생성

```
부모 클래스: ULyraActivatableWidget
```

**디테일 패널 설정:**

| 프로퍼티 | 설정값 | 이유 |
|----------|--------|------|
| Input Config | Menu | 화면이 열리면 게임 입력 차단 |
| Game Mouse Capture Mode | No Capture | 마우스가 자유롭게 움직여야 함 |

---

## 2단계 — GetDesiredFocusTarget 구현

```
이벤트 그래프 → 함수 오버라이드 → GetDesiredFocusTarget

Return Value: 화면에서 처음 포커스를 받을 버튼 (첫 번째 버튼 권장)
```

구현하지 않으면 게임패드로 이 화면을 조작할 수 없다.

---

## 3단계 — 버튼 만들기

**일반 클릭 버튼:**
```
부모 클래스: ULyraButtonBase
→ UpdateButtonStyle 이벤트 구현: 게임패드/키보드 전환 시 비주얼 변경
→ UpdateButtonText 이벤트 구현: 텍스트 변경 처리
```

**UIAction 연결 버튼 (뒤로가기, 확인 등):**
```
부모 클래스: ULyraBoundActionButton
→ 에디터에서 TriggeringInputAction 설정
→ KeyboardStyle / GamepadStyle / TouchStyle 에셋 지정
```

---

## 4단계 — 닫기 처리

**뒤로가기 / B버튼:**
```cpp
// NativeOnInitialized에서 UIAction 바인딩
RegisterUIActionBinding(FBindUIActionArgs(
    FUIActionTag::ConvertChecked(TAG_UI_ACTION_BACK),  // "UI.Action.Back"
    true,                                               // 힌트 바에 "B: 뒤로" 표시
    FSimpleDelegate::CreateUObject(this, &ThisClass::HandleBackAction)
));

void HandleBackAction()
{
    DeactivateWidget();  // 스택에서 pop. 아래 위젯으로 포커스 자동 복귀.
}
```

**닫기 버튼 클릭:**
```
버튼 OnClicked → DeactivateWidget() 호출
```

`SetVisibility(Hidden)`으로 숨기면 안 된다. 반드시 `DeactivateWidget()`을 써야 입력 모드가 복구된다.

---

## 5단계 — 화면 열기

```cpp
// C++에서 열기
UCommonUIExtensions::PushContentToLayer_ForPlayer(
    LocalPlayer,
    TAG_UI_LAYER_MENU,   // 레이어 선택
    MyScreenClass        // 위젯 클래스
);

// 소프트 레퍼런스(비동기 로드)로 열기
UCommonUIExtensions::PushStreamedContentToLayer_ForPlayer(
    LocalPlayer,
    TAG_UI_LAYER_MENU,
    SoftMyScreenClass
);
```

| 레이어 | 용도 |
|--------|------|
| `UI.Layer.Game` | HUD, 항상 보이는 오버레이 |
| `UI.Layer.Menu` | ESC 메뉴, 설정, 인벤토리 |
| `UI.Layer.Modal` | 확인창, 경고창 |

---

## 6단계 — 버튼 아이콘 표시 (선택)

버튼 옆에 "현재 이 액션에 매핑된 키의 아이콘"을 표시하려면:

```
ULyraActionWidget 추가
→ AssociatedInputAction: 연결할 UInputAction 에셋 지정
→ 자동으로 현재 플랫폼 + 리맵핑 반영해서 아이콘 표시
```

---

## 체크리스트 요약

```
□ 부모 클래스: ULyraActivatableWidget
□ Input Config: Menu  (디테일 패널)
□ GetDesiredFocusTarget 구현 (첫 포커스 버튼 반환)
□ 버튼: ULyraButtonBase 또는 ULyraBoundActionButton 사용
□ 닫기: DeactivateWidget() 사용 (SetVisibility 금지)
□ 뒤로가기: RegisterUIActionBinding("UI.Action.Back") 바인딩
□ 열기: PushContentToLayer_ForPlayer()로 올바른 레이어에 push
```

---

## 흔한 실수

| 증상 | 원인 | 해결 |
|------|------|------|
| 게임패드로 버튼 선택 안 됨 | `GetDesiredFocusTarget` 미구현 | 첫 버튼 반환하도록 구현 |
| 화면 닫아도 게임 입력 안 됨 | `SetVisibility`로 숨김 | `DeactivateWidget()` 사용 |
| B버튼이 아무 반응 없음 | UIAction 바인딩 안 함 | `RegisterUIActionBinding` 추가 |
| 게임패드 아이콘 안 바뀜 | `UButton` 사용 중 | `ULyraButtonBase`로 교체 |
| 화면 열어도 포커스 어디에도 없음 | `GetDesiredFocusTarget` 미구현 | 구현 필요 |
