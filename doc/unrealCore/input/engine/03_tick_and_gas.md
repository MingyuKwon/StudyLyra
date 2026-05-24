# 틱 처리 — PostProcessInput과 GAS 연결

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `Source/LyraGame/Player/LyraPlayerController.cpp`

---

이 문서는 **GAS Ability 입력이 매 틱 처리되는 경로**를 다룬다.

---

## Enhanced Input 관점의 틱 흐름

```
[Slate Tick — 입력 수집]
    FSlateApplication::Tick()
        PlatformApplication->Tick()          ← 패드 폴링
        InputPreProcessors.Tick()            ← FEnhancedInputWorldProcessor (WorldSubsystem용 마우스 누적)
        위젯 라우팅 (키/패드 이벤트 발생 시)
            SViewport → UGameViewportClient
                → UEnhancedPlayerInput::InputKey()   ← KeyStateMap 갱신

[PlayerController Tick — 콜백 발화]
    APlayerController::PlayerTick()
        ProcessInputStack()
            EvaluateKeyMapState()        ← bDown 상태 갱신
            EvaluateInputDelegates()     ← Input_Move() 등 Enhanced 콜백 실행 ★
                                         ← AbilityInputTagPressed() 호출 → handles 적재
            PostProcessInput()  ★       ← Lyra: ProcessAbilityInput → TryActivateAbility
    ↓
GAS Ability 활성화/해제
```

Native 입력(`Input_Move` 등)과 GAS Ability 입력 모두 **PlayerController 틱**에서 처리된다.

| 경로 | 처리 위치 | 담당 |
|---|---|---|
| Native (`Input_Move` 등) | `EvaluateInputDelegates` — UEnhancedPlayerInput | Enhanced Input |
| GAS Ability 활성화 | `PostProcessInput` | ProcessAbilityInput |

---

## PostProcessInput → ProcessAbilityInput

```cpp
// LyraPlayerController.cpp:376
void ALyraPlayerController::PostProcessInput(const float DeltaTime, const bool bGamePaused)
{
    if (ULyraAbilitySystemComponent* LyraASC = GetLyraAbilitySystemComponent())
    {
        LyraASC->ProcessAbilityInput(DeltaTime, bGamePaused);
    }
    Super::PostProcessInput(DeltaTime, bGamePaused);
}
```

`PostProcessInput`은 `ProcessInputStack()` 안에서 **매 틱 무조건 호출**된다. 입력 이벤트가 없는 틱에도 실행된다.

`ProcessAbilityInput` 내부에서 일어나는 일 → [lyra/03_ability_input.md](../lyra/03_ability_input.md)

---

## 왜 매 틱 실행해야 하는가

```cpp
// PlayerInput.cpp:1239
void UPlayerInput::ProcessInputStack(...)
{
    PC->PreProcessInput(...);
    EvaluateKeyMapState(...);      // bDown 상태 갱신 — 항상 실행
    EvaluateInputDelegates(...);   // 레거시 콜백 — 항상 실행
    PC->PostProcessInput(...);     // ★ 항상 실행
    FinishProcessingPlayerInput();
}
```

입력 이벤트가 없어도 파이프라인이 도는 이유:

- **`bDown` 상태 유지** — 키를 누르고 있으면 OS Repeat 이벤트 없이도 매 틱 `bDown == true`가 유지된다
- **`WhileInputActive` 정책** — GA는 `bDown == true`인 동안 매 틱 활성화를 시도한다
- 이벤트가 없는 틱에 파이프라인이 멈추면 홀드 동작이 끊긴다

---

## bDown이 유지되는 원리 (요약)

```
키 누름 → EventAccumulator[IE_Pressed] 추가
    ↓
EvaluateKeyMapState() → ProcessNonAxesKeys()
    PressDelta > 0 → bDown = true
    ↓
FinishProcessingPlayerInput()
    bDownPrevious = bDown
    ↓
다음 틱 — 이벤트 없음
    PressDelta == 0 → bDown = bDownPrevious (true 유지)
```

상세 구현 → [background/03_legacy_tick_detail.md](background/03_legacy_tick_detail.md)

---

## BuildInputStack — UEnhancedInputComponent 위치

```cpp
// PlayerController.cpp:2694
void APlayerController::BuildInputStack(TArray<UInputComponent*>& InputStack)
```

매 틱 InputComponent를 스택에 쌓는다. **위에 있을수록 우선순위 높음.**

| 순서 (낮음 → 높음) | 대상 |
|---|---|
| 1 | Pawn의 `InputComponent` (`UEnhancedInputComponent` 포함) |
| 2 | Pawn에 붙은 다른 UInputComponent 파생 컴포넌트 |
| 3 | `LevelScriptActor`의 InputComponent |
| 4 | `PlayerController`의 InputComponent |
| 5 | `PushInputComponent()`로 수동 추가된 컴포넌트 (최우선) |

Enhanced Input에서 `UEnhancedInputComponent`는 Pawn에 붙어 스택 하단에 위치한다.  
`UEnhancedPlayerInput::EvaluateInputDelegates()`가 스택을 순회하며 `UEnhancedInputComponent`를 찾아 콜백을 발화한다.

---

## 왜 여러 InputComponent + 스택인가 — IMC 교체로 충분하지 않은가

> InputComponent 개념과 기본 생성 위치 → [00_input_component.md](00_input_component.md)

IMC 교체와 InputComponent 스택은 **해결하는 문제가 다르다.**

**IMC 교체** — 같은 Actor 안에서 "어떤 키가 어떤 Action인가"를 바꾼다.

```
전투 IMC: W → IA_Move
메뉴 IMC: W → IA_MenuUp
```

처리 주체는 바뀌지 않는다. 같은 Pawn의 같은 InputComponent가 처리한다.

**InputComponent 스택** — **서로 다른 Actor/시스템** 중 누가 처리할지를 결정한다.

```
예: 차량 탑승
    Pawn->InputComponent: 탑승/하차 키 바인딩
    차량->InputComponent: 가속/조향 바인딩 (PushInputComponent로 추가)
    → 두 시스템이 동시에 독립적으로 입력을 처리
```

상위 InputComponent가 입력을 **소비(consume)** 하면 하위에 전달되지 않는다.  
PlayerController의 InputComponent가 상위에 있으므로, PC가 처리한 키는 Pawn에 내려가지 않는다.

```
스택 처리 순서 (위 → 아래)
    [5] PushInputComponent 추가분     ← 먼저 처리, 소비하면 아래 안 내려감
    [4] PlayerController->InputComponent
    [3] LevelScriptActor->InputComponent
    [1] Pawn->InputComponent          ← 마지막에 처리
```

### 결론

| | IMC 교체 | InputComponent 스택 |
|---|---|---|
| **목적** | 같은 Actor의 키-Action 매핑 전환 | 어느 Actor/시스템이 처리할지 라우팅 |
| **언제** | 전투/메뉴/탈것 컨텍스트 전환 | 차량 탑승, UI 가로채기, 모달 입력 |
| **처리 주체** | 변하지 않음 | 동적으로 추가/제거 가능 |

Lyra는 두 가지를 함께 쓴다. 컨텍스트 전환은 IMC로, 특수 상황의 입력 가로채기는 `PushInputComponent`로 한다.
