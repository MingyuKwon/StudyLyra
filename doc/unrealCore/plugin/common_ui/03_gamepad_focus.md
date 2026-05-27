# 게임패드 포커스

> 관련 소스: `UI/LyraActivatableWidget.cpp`

---

## 포커스란

게임패드로 UI를 조작할 때 "현재 선택된 위젯"이 포커스를 가진다.  
방향키/스틱으로 포커스를 이동하고, A버튼(확인)으로 클릭한다.

CommonUI는 포커스를 **자동 관리**한다:
- 위젯이 활성화될 때 → 첫 포커스 위치 자동 설정
- 방향키 입력 → 다음 위젯으로 자동 이동
- 위젯이 비활성화될 때 → 아래 위젯의 마지막 포커스 위치로 복귀

---

## GetDesiredFocusTarget() — 반드시 구현해야 하는 함수

위젯이 활성화될 때 CommonUI가 호출하는 함수.  
"게임패드 커서를 이 화면에서 처음에 어디에 놓을까?"를 반환한다.

```cpp
// C++에서 선언 (BP 구현용)
virtual UWidget* NativeGetDesiredFocusTarget() const override;

// Blueprint 이름: GetDesiredFocusTarget
// 반환 타입: Widget Reference (포커스를 받을 위젯)
```

### Blueprint 구현 예시

```
GetDesiredFocusTarget 이벤트
    └─ Return: Button_FirstOption   ← 화면의 첫 번째 버튼 반환
```

구현하지 않으면:
- 게임패드로 아무 버튼도 선택되지 않음
- 에디터 컴파일 경고 출력:

```
"GetDesiredFocusTarget wasn't implemented,
 you're going to have trouble using gamepads on this screen."
```

---

## 포커스 이동 자동 순회

방향키/스틱으로 포커스를 이동할 때 CommonUI가 Widget Tree를 자동 순회한다.  
별도 코드 없이 **UMG 위젯 배치 순서(위→아래, 좌→우)** 대로 이동한다.

```
[수직 Box]
  Button_A  ← 현재 포커스
  Button_B
  Button_C

스틱 아래 → Button_B로 이동
스틱 아래 → Button_C로 이동
스틱 아래 → (끝) → 아무 일도 일어나지 않음 (또는 루프, 설정에 따라 다름)
```

### 포커스 이동이 안 되는 경우

| 원인 | 해결 |
|------|------|
| `UButton` 사용 | `UCommonButtonBase` (또는 `ULyraButtonBase`)로 교체 |
| `IsFocusable = false` | 버튼 디테일에서 `Is Focusable = true` 설정 |
| 위젯이 Disabled 상태 | Enable 처리 확인 |
| Visibility가 HitTestInvisible | SelfHitTestInvisible 또는 Visible로 변경 |

---

## 포커스 복귀 — 스택 pop 시 동작

```
[스택]
  Modal (포커스: Button_OK)
  Menu  (포커스: 마지막으로 Button_Settings를 선택했었음)

Modal을 DeactivateWidget()으로 닫으면
    → CommonUI가 Menu의 마지막 포커스 위치(Button_Settings)를 자동 복원
```

CommonUI가 각 위젯의 **마지막 포커스 위치를 기억**하기 때문에 자연스러운 탐색이 가능하다.

---

## 게임패드 전용 포커스 시각 피드백

`UCommonButtonBase`는 포커스 상태에 따라 자동으로 스타일을 바꾼다.

```
Hovered  → 마우스 올려놓은 상태
Focused  → 게임패드가 선택한 상태
Selected → 선택 완료 상태
Disabled → 비활성화 상태
```

각 상태별 브러시/색상을 `UCommonButtonStyle`에 정의하고,  
버튼이 상태 전환 시 자동으로 적용된다.
