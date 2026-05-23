# 틱 처리 — PostProcessInput과 GAS 연결

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `Source/LyraGame/Player/LyraPlayerController.cpp`

---

Enhanced Input의 콜백(`Input_Move` 등)은 PreProcessor 단계(Slate 틱)에서 이미 실행된다.  
이 문서는 그 이후 — **GAS Ability 입력이 매 틱 처리되는 경로**를 다룬다.

---

## Enhanced Input 관점의 틱 흐름

```
[엔진 틱]
    ↓
FSlateApplication::Tick()
    PlatformApplication->Tick()          ← 패드 폴링
    InputPreProcessors.Tick()            ← Enhanced Input Subsystem Tick
        Enhanced Input: 이번 틱 Triggered/Completed 상태 갱신
        → Input_Move() 등 Native 콜백 실행  ← 여기서 이동/시점 처리 끝
    ↓
APlayerController::PlayerTick()
    TickPlayerInput()
        ProcessPlayerInput()
            ProcessInputStack()
                EvaluateKeyMapState()        ← bDown 상태 갱신
                EvaluateInputDelegates()     ← 레거시 BindAction 콜백 (Enhanced 미사용)
                PostProcessInput()  ★       ← Lyra: ProcessAbilityInput
    ↓
GAS Ability 활성화/해제
```

Native 입력(이동, 시점)과 GAS Ability 입력의 처리 시점이 다르다.

| 경로 | 처리 시점 | 담당 |
|---|---|---|
| Native (`Input_Move` 등) | Slate 틱 — PreProcessor | Enhanced Input |
| GAS Ability 활성화 | PlayerController 틱 — PostProcessInput | ProcessAbilityInput |

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
단, `EvaluateInputDelegates`에서 Enhanced Input 콜백을 실행하는 것은 아니다 — 콜백은 이미 PreProcessor 단계에서 끝났다.
