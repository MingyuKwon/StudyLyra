# 03. 포커스 시스템

> CommonUI의 게임패드 UI 조작은 포커스 시스템을 기반으로 동작한다.  
> 포커스는 Slate 코어 개념이고, CommonUI는 그 위에 레이어 격리와 자동 관리를 추가했다.

---

## 목차

| 파일 | 내용 |
|------|------|
| [Slate 포커스 시스템](../../../slate/06_focus.md) | FNavigationReply · EFocusCause · Navigate() 흐름 (Slate 코어) |
| [02_commonui_focus.md](02_commonui_focus.md) | CommonUI 포커스 처리 — 초기화·격리·복귀·시각 피드백 |

---

## 두 층의 책임

```
┌─────────────────────────────────────────────────┐
│                  CommonUI 레이어                  │
│  GetDesiredFocusTarget   레이어 격리(Activatable) │
│  포커스 자동 복귀         UCommonButtonBase 시각  │
├─────────────────────────────────────────────────┤
│                  Slate 코어 레이어                │
│  FocusPath   SupportsKeyboardFocus()             │
│  FNavigationReply   OnFocusReceived/Lost         │
│  FNavigationConfig  (D-pad/스틱 → 방향 매핑)    │
└─────────────────────────────────────────────────┘
```

Slate는 "포커스를 어떻게 이동시키는가"를 담당한다.  
CommonUI는 "어디서 시작하고, 어느 범위 안에서 움직이고, 끝나면 어떻게 되는가"를 담당한다.
