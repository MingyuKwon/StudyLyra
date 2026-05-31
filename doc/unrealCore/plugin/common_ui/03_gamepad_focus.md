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

## 포커스 이동 — 동작 원리

포커스 이동은 "다음 위젯 포인터를 미리 지정해둔다"가 아니다.  
**Slate가 화면 좌표 기반으로 런타임에 공간 탐색**을 수행한다.

### 전체 흐름

```
[1] 방향키/스틱 입력
        └─ FSlateApplication이 EUINavigation::Down (또는 Up/Left/Right) 이벤트 생성

[2] 후보 수집
        └─ 위젯 트리 전체 순회
        └─ SupportsKeyboardFocus() == true 인 위젯만 후보로 수집

[3] 방향 필터링
        └─ 현재 포커스 위젯의 화면상 Bounding Box 기준
        └─ Down이면 → 현재 위젯 중심 Y보다 아래에 있는 후보만 남김

[4] 최적 후보 선택
        └─ 남은 후보들에 Navigation Score 계산 (거리 + 정렬 보정값)
        └─ 가장 낮은 Score의 위젯으로 포커스 이동
```

### UMG 배치 순서와 일치하는 이유

트리 순서를 보는 것이 아니라 **실제 화면 픽셀 좌표**를 보기 때문이다.  
Vertical Box에 버튼을 위→아래로 쌓으면 화면 Y 좌표도 위→아래가 되어 결과가 일치할 뿐이다.

```
[수직 Box]
  Button_A  (Y: 100)  ← 현재 포커스
  Button_B  (Y: 150)
  Button_C  (Y: 200)

스틱 아래 → Y > 100 후보 수집 → Button_B(50 차이), Button_C(100 차이)
         → Score 최소값 = Button_B → 포커스 이동
```

### SupportsKeyboardFocus() — 후보 수집의 핵심

> 이름이 Keyboard인 이유: 게임패드 지원 이전, Slate 포커스는 키보드 전용이었다.  
> 게임패드가 추가될 때 별도 시스템을 만들지 않고 같은 포커스 시스템을 재활용했기 때문에 이름이 그대로 남았다.  
> 실제 의미는 "방향 네비게이션(키보드·게임패드 무관)의 후보가 될 수 있는가"다.

```cpp
// SButton (UMG 기본 버튼)
virtual bool SupportsKeyboardFocus() const override { return false; }  // 후보에서 제외

// SCommonButton (CommonUI 버튼)
virtual bool SupportsKeyboardFocus() const override { return bIsFocusable; }  // 후보 포함
```

`UButton`으로 만든 버튼은 후보 수집 단계에서 아예 제외되어 방향키로 이동이 불가능하다.

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
