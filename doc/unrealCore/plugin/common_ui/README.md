# CommonUI

> 플러그인 경로: `Engine/Plugins/Runtime/CommonUI/`  
> Lyra 관련 소스: `Source/LyraGame/UI/`

---

## 개요

CommonUI는 **멀티 플랫폼 UI 프레임워크**다.  
일반 UMG가 "위젯을 배치하는 것"에 집중한다면, CommonUI는 **위젯 간의 관계, 입력 흐름, 플랫폼 대응**까지 담당한다.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 위젯 스택](01_widget_stack.md) | UCommonActivatableWidget, 레이어 구조, push/pop, 활성화 흐름 |
| [02. 입력 모드](02_input_mode.md) | FUIInputConfig, 입력 모드 스택, Game/Menu/GameAndMenu |
| [03. 게임패드 포커스](03_gamepad_focus.md) | GetDesiredFocusTarget, 포커스 이동, 자동 순회 |
| [04. 버튼](04_button.md) | UCommonButtonBase, ULyraButtonBase, BoundActionButton, 스타일 자동 전환 |
| [05. UIAction 바인딩](05_ui_action.md) | RegisterUIActionBinding, UIAction 태그, ESC/뒤로가기 처리 |
| [06. 입력 장치 감지](06_input_subsystem.md) | UCommonInputSubsystem, 장치 전환 감지, 아이콘 자동 갱신 |

---

게임패드 UI 조작을 위해 CommonUI가 해결하는 문제:

| 문제 | CommonUI 해법 |
|------|--------------|
| 팝업이 열렸을 때 게임 입력이 살아있음 | 입력 모드 스택으로 자동 차단 |
| 게임패드로 어느 버튼부터 선택해야 하나 | `GetDesiredFocusTarget()`으로 진입점 지정 |
| 팝업을 닫으면 포커스가 사라짐 | 스택에서 pop 되면 아래 위젯으로 자동 복귀 |
| 입력 장치 바꿀 때마다 버튼 아이콘 수동 갱신 | `CommonInputSubsystem`이 장치 변경 감지해 자동 갱신 |
| ESC/B버튼 처리를 화면마다 직접 바인딩 | UIAction 태그 기반 바인딩으로 통합 |
