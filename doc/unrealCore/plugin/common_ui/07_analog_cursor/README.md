# 07. AnalogCursor / CommonAnalogCursor

> 소스 경로  
> - `Engine/Source/Runtime/Slate/Public/Framework/Application/AnalogCursor.h`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/AnalogCursor.cpp`  
> - `Engine/Source/Runtime/Slate/Public/Framework/Application/NavigationConfig.h`  
> - `Engine/Source/Runtime/Slate/Private/Framework/Application/NavigationConfig.cpp`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Public/Input/CommonAnalogCursor.h`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/Input/CommonAnalogCursor.cpp`

---

## 목차

| 파일 | 내용 |
|------|------|
| [01_fanalogcursor.md](01_fanalogcursor.md) | FAnalogCursor — Slate 기반 구현 |
| [02_focus_linked_mode.md](02_focus_linked_mode.md) | 포커스 연동 모드 — Slate 네비게이션 시스템 연동 |
| [03_scroll_and_input.md](03_scroll_and_input.md) | 스크롤 · 입력 처리 · 커서 가시성 |

---

## 클래스 계층

```
IInputProcessor
└── FAnalogCursor          ← Slate 기반 구현 (Runtime/Slate)
    └── FCommonAnalogCursor ← CommonUI 확장 (CommonUI Plugin)
```

## FCommonAnalogCursor 개요

기존 `FAnalogCursor`에 CommonUI가 추가한 핵심 차이:

| 기존 FAnalogCursor | FCommonAnalogCursor |
|-------------------|---------------------|
| 스틱 → 커서 이동 (항상) | **포커스 연동 모드** (기본) vs 아날로그 이동 모드 |
| 커서 항상 표시 | 게임패드 사용 시 커서 숨김 |
| 입력 항상 처리 | 게임 뷰포트가 포커스 경로에 있을 때만 처리 |
| 오른쪽 스틱 미사용 | 오른쪽 스틱 → 스크롤 위젯 ScrollWheel 이벤트 |

## 두 가지 동작 모드

`bIsAnalogMovementEnabled` 플래그로 구분된다.

| 모드 | 조건 | 핵심 역할 |
|------|------|-----------|
| **포커스 연동 모드** | `== false` (기본) | Slate가 포커스를 이동, 커서는 포커스를 추종 |
| **아날로그 이동 모드** | `== true` | 스틱으로 커서를 직접 이동 (마우스처럼) |

개발 빌드(`!UE_BUILD_SHIPPING`)에서 L/R 숄더 + L/R 트리거 동시 누름으로 토글된다.

## 생성 및 초기화

```cpp
// UCommonUIActionRouterBase가 소유 — 플레이어 1명당 1개
TSharedRef<FCommonAnalogCursor> Cursor =
    FCommonAnalogCursor::CreateAnalogCursor(ActionRouter);

void FCommonAnalogCursor::Initialize()
{
    RefreshCursorSettings();  // UCommonUIInputSettings에서 파라미터 로드
    InputSubsystem.OnInputMethodChangedNative.AddSP(
        this, &FCommonAnalogCursor::HandleInputMethodChanged);
}
```

`ActionRouter`를 멤버 참조로 보관. `FCommonAnalogCursor`의 수명은 `ActionRouter`에 종속된다.

---

## 전체 흐름 요약 (포커스 연동 모드)

```
[게임패드 D-pad 누름 / 왼쪽 스틱 기울기]
        │
        ▼
FCommonAnalogCursor
  ├─ 왼쪽 스틱 analog axis → 부모에서 캐싱 후 false 반환 (소비 안 함)
  ├─ 왼쪽 스틱 디지털 이벤트 → FAnalogCursor가 소비 (네비게이션 관여 안 함)
  └─ D-Pad Key → 소비하지 않고 통과
        │
        ▼ (소비되지 않은 이벤트)
FSlateApplication → FNavigationConfig
  ├─ D-Pad → KeyEventRules → EUINavigation::Up/Down/Left/Right
  └─ 왼쪽 스틱 axis → |value| > 0.5 임계값 → EUINavigation 생성
        │
        ▼
FSlateApplication::Navigate()
  └─ SWidget::OnNavigation() → FNavigationReply
        └─ 위젯 트리 탐색 → 다음 포커서블 위젯 → 포커스 이동
              │
              ▼
FCommonAnalogCursor::Tick()
  └─ GetFocusedWidget() 변화 감지
        └─ 커서 텔레포트 → 포커스 위젯 중앙 (커서 불가시)

[A버튼 / Virtual_Gamepad_Accept]
  ├─ UIAction 바인딩 있으면 → ActionRouter.ProcessInput()
  └─ 없으면 → FPointerEvent(LeftMouseButton) → 커서 위치 클릭
        └─ 커서가 포커스 위젯 중앙에 있으므로 히트 테스트 성공
```

---

## 설계 포인트

**커서가 보이지 않아도 클릭이 동작하는 이유**  
포커스 연동 모드에서 커서는 항상 포커스된 위젯 중앙에 위치해 있다.  
A 버튼을 누르면 좌클릭으로 변환되고, Slate 히트 테스트가 그 좌표에서 위젯을 찾아 이벤트를 전달한다.  
커서가 숨겨진 것은 표시 여부일 뿐, 논리적 위치는 유효하다.

**`IsGameViewportInFocusPathWithoutCapture()` 의 "sweet spot"**  
헤더 주석에 직접 언급된 설계 의도: 뷰포트가 포커스 경로에 **있으면서** 커서를 **독점 캡처하지 않는** 상태.  
게임 플레이 중(마우스 캡처 상태)에는 UI가 입력을 가로채지 않고, UI 모드(캡처 해제)에서만 동작한다.
