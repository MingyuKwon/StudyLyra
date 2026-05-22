# 콘솔 입력 시스템

---

## 왜 게임 입력과 다른가?

한 줄 요약: **게임 입력은 "상태"를 추적하고, 콘솔 입력은 "명령"을 실행한다.**

---

### 게임 입력 (Enhanced Input / PlayerInput)

플레이어가 W키를 누르고 있는 동안 캐릭터가 계속 앞으로 가야 한다.  
이 말은 곧 — **"지금 이 순간에도 W키가 눌려있는가"를 매 틱 확인해야 한다**는 뜻이다.

OS는 키를 처음 눌렀을 때와 뗄 때만 이벤트를 보낸다.  
중간에는 아무 신호도 없다.

그래서 언리얼은 **Accumulator 패턴**을 사용한다:

```
[키 누름 이벤트 — OS 타이밍, 비동기]
    → EventAccumulator에 누적 (아무것도 실행 안 함)

[매 틱 — 게임 루프 타이밍, 동기]
    → Accumulator flush
    → bDown 상태 갱신 (이번 틱 이벤트 없으면 이전 상태 유지)
    → 바인딩된 함수 호출
```

이 구조가 필요한 이유: 게임 로직(물리, 애니메이션, GAS)은 틱 단위로 돌아야 한다.  
OS 이벤트 타이밍은 틱과 맞지 않을 수 있으므로, 이벤트를 모아뒀다가 틱에서 일괄 처리한다.

| 게임 입력의 특성 | 이유 |
|-----------------|------|
| 연속적(Continuous) | 키 홀드 상태를 매 틱 알아야 함 |
| 프레임 동기화 필수 | 게임 로직이 틱 단위로 동작 |
| 아날로그 값 처리 | 스틱 기울기(-1~1), 마우스 델타 등 |
| 플레이어 단위 격리 | 스플릿스크린에서 플레이어마다 독립적 상태 |

---

### 콘솔 입력

개발자가 `~` 키를 눌러 콘솔을 열고 `AbilitySystem.DebugMode 1`을 타이핑한 뒤 Enter를 친다.  
이 명령은 **한 번 실행하면 끝**이다. 다음 틱에 "아직도 명령이 눌려있나?" 를 확인할 필요가 없다.

그래서 콘솔 입력은 **텍스트 파싱 → 즉시 실행** 구조다:

```
[Enter 누름]
    → 입력 문자열을 IConsoleManager에 전달
    → 이름 매칭 (CVar인가? CCmd인가?)
    → 즉시 실행 (틱 대기 없음)
```

| 콘솔 입력의 특성 | 이유 |
|-----------------|------|
| 이산적(Discrete) | 명령 한 번 실행하면 끝 |
| 프레임 무관 | 즉시 실행해도 게임 로직에 문제 없음 |
| 텍스트 기반 | 문자열 이름으로 CVar/CCmd/Exec 매칭 |
| 전역 단위 | CVar는 특정 플레이어가 아닌 전역 상태 |

---

### 두 시스템 비교

| | 게임 입력 | 콘솔 입력 |
|---|---|---|
| **성격** | 연속적 상태 추적 | 이산적 명령 실행 |
| **처리 주기** | 매 틱 무조건 실행 | 명령 입력 시 즉시 |
| **진입점** | OS 키 이벤트 → PlayerInput | 텍스트 Enter → IConsoleManager |
| **데이터 형태** | 키 상태, 아날로그 값 | 문자열 (이름 + 인자) |
| **대상** | 로컬 플레이어 | 전역 또는 특정 World |
| **목적** | 플레이어 조작 | 개발자 디버깅/설정 |
| **핵심 클래스** | `UEnhancedInputComponent`, `UPlayerInput` | `IConsoleManager`, `ProcessConsoleExec` |

---

## 처리 흐름 전체

```
[게임 입력 경로]
OS 키 이벤트
    → UPlayerInput::InputKey() — Accumulator에 누적
    → 매 틱 EvaluateKeyMapState() — flush
    → Enhanced Input 처리
    → InputComponent 콜백 실행

[콘솔 입력 경로]
개발자가 Enter 입력
    → UConsole::ConsoleCommand()
    → APlayerController::ConsoleCommand()
    → IConsoleManager::ProcessUserConsoleInput()
            ├─ CVar 이름 매칭 → 값 읽기/쓰기
            ├─ CCmd 이름 매칭 → 콜백 실행
            └─ 미매칭 → Exec 체인 순회
                    (PC → CheatManager → Pawn → HUD → GameMode → Engine)
```

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. CVar / CCmd 시스템](01_cvar_ccommand.md) | IConsoleManager, TAutoConsoleVariable, FAutoConsoleCommand, SetBy 우선순위 |
| [02. Exec 함수 체계](02_exec_functions.md) | UFUNCTION(Exec), ProcessConsoleExec 라우팅 체인, showdebug 메커니즘 |
| [03. GAS 디버그 명령어](03_gas_debug.md) | showdebug abilitysystem, AbilitySystem.Debug.*, 디버그 타깃 선택 원리 |
