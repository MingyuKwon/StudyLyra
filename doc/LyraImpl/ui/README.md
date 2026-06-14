# Lyra UI 시스템

> 출처: `Source/LyraGame/UI/`  
> 엔진 기반: [`doc/unrealCore/plugin/common_ui/`](../../unrealCore/plugin/common_ui/README.md)

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 클래스 계층](01_class_hierarchy.md) | Lyra UI 클래스 전체 계층도, 각 클래스 역할과 사용 시점 |
| [02. HUD 레이아웃](02_hud_layout.md) | LyraHUDLayout 구현 — UI 레이어 태그, ESC 액션, 컨트롤러 연결 끊김 처리 |
| [03. 새 화면 만들기](03_new_screen_pattern.md) | Lyra 패턴으로 새 UI 화면을 만드는 실용 가이드 |
| [04. 설정 화면 포커스 분석](04_settings_screen.md) | LyraSettingScreen 구조 — 탭 전환·포커스 재씨딩 실제 구현 |

---

## 개요

Lyra의 UI는 CommonUI 플러그인 위에 구축된다.  
CommonUI의 위젯 스택, 입력 모드, 게임패드 포커스 시스템을 그대로 사용하고,  
Lyra는 그 위에 **게임 전용 클래스 계층**과 **HUD 레이아웃 패턴**을 얹는다.

CommonUI 기초 개념은 [`doc/unrealCore/plugin/common_ui/`](../../unrealCore/plugin/common_ui/README.md)를 먼저 참고.
