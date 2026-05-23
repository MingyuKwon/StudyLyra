# 언리얼 엔진 입력 파이프라인

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`

---

## 핵심 질문: 입력이 없어도 매 틱 처리 함수가 불리는가?

**그렇다.** 입력 파이프라인은 하드웨어 이벤트와 무관하게 **매 틱 무조건 실행**된다.

---

## 전체 호출 체인

```
[엔진 틱]
    │
    ▼
APlayerController::TickActor()          ← 엔진이 Actor Tick으로 호출
    │  (PlayerInput 객체가 있는 경우만 — 즉 로컬 PlayerController만)
    ▼
APlayerController::PlayerTick()         ← PlayerController.cpp:2309
    │
    ├─ TickPlayerInput(DeltaTime, bGamePaused)    ← :5320
    │       │
    │       ├─ PlayerInput->Tick()               ← 제스처 인식 등
    │       ├─ [마우스 오버 이벤트 처리]
    │       ├─ ProcessPlayerInput()              ← 핵심 처리
    │       └─ ProcessForceFeedbackAndHaptics()
    │
    └─ [이후 카메라, 이동 등 처리]
```

```
ProcessPlayerInput()                         ← PlayerController.cpp:2768
    │
    ├─ BuildInputStack(InputStack)           ← InputComponent 목록 구성
    └─ PlayerInput->ProcessInputStack(...)   ← PlayerInput.cpp:1239
            │
            ├─ PlayerController->PreProcessInput()   ← virtual 훅 (처리 전)
            ├─ EvaluateKeyMapState()                 ← Accumulator → EventCounts flush
            ├─ EvaluateInputDelegates()              ← 바인딩된 액션/축 델리게이트 실행
            ├─ PlayerController->PostProcessInput()  ← virtual 훅 ★ Lyra 오버라이드
            └─ FinishProcessingPlayerInput()         ← bDownPrevious 갱신
```

---

## 실제 코드 — TickPlayerInput

```cpp
// PlayerController.cpp:5320
void APlayerController::TickPlayerInput(const float DeltaSeconds, const bool bGamePaused)
{
    check(PlayerInput);
    PlayerInput->Tick(DeltaSeconds);   // 제스처 인식, 스무딩 등

    if (ULocalPlayer* LocalPlayer = Cast<ULocalPlayer>(Player))
    {
        // 마우스 오버 이벤트 — 커서 아래 컴포넌트 추적
        if (bEnableMouseOverEvents)
        {
            // ... GetHitResultAtScreenPosition → DispatchMouseOverEvents
        }
    }

    ProcessPlayerInput(DeltaSeconds, bGamePaused);
    ProcessForceFeedbackAndHaptics(DeltaSeconds, bGamePaused);
}
```

`PlayerInput`이 없으면 `check`에서 터진다. 로컬 `PlayerController`만 `PlayerInput`을 가지므로, 서버 전용 PC에서는 이 경로 자체가 호출되지 않는다.

---

## 실제 코드 — ProcessPlayerInput / ProcessInputStack

```cpp
// PlayerController.cpp:2768
void APlayerController::ProcessPlayerInput(const float DeltaTime, const bool bGamePaused)
{
    static TArray<UInputComponent*> InputStack;
    check(IsInGameThread() && !InputStack.Num());  // 재진입 방지

    BuildInputStack(InputStack);                              // 우선순위 스택 구성
    PlayerInput->ProcessInputStack(InputStack, DeltaTime, bGamePaused);
    InputStack.Reset();
}

// PlayerInput.cpp:1239
void UPlayerInput::ProcessInputStack(const TArray<UInputComponent*>& InputComponentStack,
                                     const float DeltaTime, const bool bGamePaused)
{
    APlayerController* PC = GetOuterAPlayerController();

    PC->PreProcessInput(DeltaTime, bGamePaused);          // virtual 훅 (기본 구현 비어있음)
    EvaluateKeyMapState(DeltaTime, bGamePaused, KeysWithEvents);   // Accumulator flush
    EvaluateInputDelegates(InputComponentStack, DeltaTime, bGamePaused, KeysWithEvents);
    PC->PostProcessInput(DeltaTime, bGamePaused);          // virtual 훅 ★
    FinishProcessingPlayerInput();                          // bDownPrevious 갱신
}
```

---

## 두 단계로 분리된 이유 — Accumulator 패턴

입력 처리는 **비동기 이벤트 수집**과 **동기 처리**로 분리된다.

### 1단계: 이벤트 수집 (틱과 무관, OS 이벤트 발생 시)

OS 이벤트 → Slate → `UGameViewportClient` → `APlayerController` → `UPlayerInput::InputKey()` 경로는 [03_viewport_to_playerinput.md](03_viewport_to_playerinput.md)에서 다룬다.

```cpp
// PlayerInput.cpp:278
bool UPlayerInput::InputKey(const FInputKeyEventArgs& Params)
{
    FKeyState& KeyState = KeyStateMap.FindOrAdd(Params.Key);
    KeyState.EventAccumulator[IE_Pressed].Add(++EventCount);  // 버퍼에 누적
    KeyState.RawValueAccumulator.X += Params.AmountDepressed;
}
```

- `InputKey()`는 `EventAccumulator`에 **누적만** 한다. 이 시점에는 아무것도 실행되지 않는다.

### 2단계: 일괄 처리 (매 틱 — EvaluateKeyMapState)

```cpp
// PlayerInput.cpp:1273
void UPlayerInput::EvaluateKeyMapState(const float DeltaTime, const bool bGamePaused,
                                        TArray<TPair<FKey, FKeyState*>>& KeysWithEvents)
{
    for (TMap<FKey,FKeyState>::TIterator It(KeyStateMap); It; ++It)
    {
        FKeyState* const KeyState = &It.Value();
        const FKey& Key = It.Key();

        // Accumulator → EventCounts 로 swap (flush)
        for (uint8 EventIndex = 0; EventIndex < IE_MAX; ++EventIndex)
        {
            KeyState->EventCounts[EventIndex].Reset();
            Exchange(KeyState->EventCounts[EventIndex], KeyState->EventAccumulator[EventIndex]);

            if (KeyState->EventCounts[EventIndex].Num() > 0)
                KeysWithEvents.Emplace(Key, KeyState);  // 이번 틱에 이벤트 있는 키만 따로 모음
        }

        // RawValue 갱신 (아날로그 값)
        KeyState->RawValue = KeyState->RawValueAccumulator;

        // bDown 상태 갱신
        ProcessNonAxesKeys(Key, KeyState);

        // Accumulator 초기화
        KeyState->RawValueAccumulator = FVector(0.f, 0.f, 0.f);
        KeyState->SampleCountAccumulator = 0;
    }
}
```

- `KeyStateMap` 전체를 순회 — 이번 틱 이벤트가 없어도 모든 키를 처리한다.
- `Exchange()`로 Accumulator와 EventCounts를 **swap**한다. Accumulator는 비워지고 EventCounts에 이벤트가 들어온다.
- 이벤트가 있는 키만 `KeysWithEvents`에 담아 `EvaluateInputDelegates`에 넘긴다.

---

## 키 홀드 상태가 유지되는 원리 — ProcessNonAxesKeys / FinishProcessingPlayerInput

```cpp
// PlayerInput.cpp:1210
void UPlayerInput::ProcessNonAxesKeys(FKey InKey, FKeyState* KeyState)
{
    int32 const PressDelta = KeyState->EventCounts[IE_Pressed].Num()
                           - KeyState->EventCounts[IE_Released].Num();

    if (PressDelta < 0)
        KeyState->bDown = false;        // Released가 더 많음 → 확실히 뗐다
    else if (PressDelta > 0)
        KeyState->bDown = true;         // Pressed가 더 많음 → 확실히 눌렀다
    else
        KeyState->bDown = KeyState->bDownPrevious;  // 이벤트 없음 → 이전 상태 유지
}

// PlayerInput.cpp:1747
void UPlayerInput::FinishProcessingPlayerInput()
{
    for (TMap<FKey,FKeyState>::TIterator It(KeyStateMap); It; ++It)
    {
        FKeyState& KeyState = It.Value();
        KeyState.bDownPrevious = KeyState.bDown;  // 다음 틱을 위해 현재 상태를 저장
        KeyState.bConsumed = false;
    }
}
```

매 틱 `bDown`이 결정되는 흐름:

```
EvaluateKeyMapState()
    → ProcessNonAxesKeys()
        PressDelta == 0 (이번 틱 이벤트 없음)
            → bDown = bDownPrevious   ← 이전 틱 상태 복사
    → FinishProcessingPlayerInput()
        → bDownPrevious = bDown       ← 다음 틱을 위해 보존
```

키를 계속 누르고 있으면 OS에서 Repeat 이벤트가 오기도 하지만, 그것과 무관하게 `bDownPrevious` 복사만으로 매 틱 `bDown == true`가 유지된다. 이것이 `WhileInputActive` 정책이 동작하는 근거다.

---

## BuildInputStack — 우선순위 스택 구성

```cpp
// PlayerController.cpp:2694
void APlayerController::BuildInputStack(TArray<UInputComponent*>& InputStack)
```

매 틱 아래 순서로 InputComponent를 스택에 쌓는다. **위에 있을수록 우선순위 높음.**

| 순서 (낮음 → 높음) | 대상 |
|---|---|
| 1 | Pawn의 `InputComponent` |
| 2 | Pawn에 붙은 다른 `UInputComponent` 파생 컴포넌트 |
| 3 | `LevelScriptActor`의 `InputComponent` |
| 4 | `PlayerController` 자신의 `InputComponent` |
| 5 | `PushInputComponent()`로 수동 추가된 컴포넌트 (가장 높음) |

`bConsumed` 플래그가 세워진 입력은 스택 아래쪽으로 전파되지 않는다.

---

## PostProcessInput이 매 틱 불리는 이유 요약

```
ProcessInputStack() 내부 구조:
    PreProcessInput()        ← 항상 호출
    EvaluateKeyMapState()    ← 항상 호출 (Accumulator가 비어도)
    EvaluateInputDelegates() ← 항상 호출
    PostProcessInput()       ← 항상 호출  ★
```

`ProcessInputStack`은 "입력이 있을 때만" 호출되는 것이 아니라, **매 틱 `ProcessPlayerInput()`에서 무조건 호출**된다. 따라서 `PostProcessInput`도 — 그리고 Lyra의 `ProcessAbilityInput`도 — **매 틱 실행**된다.

입력 이벤트가 없는 틱에도 파이프라인이 도는 이유:
- `bDown` 상태 갱신 (홀드 지속 판정)
- 축(Axis) 값 업데이트 (0으로 초기화 포함)
- `WhileInputActive`처럼 상태 기반 처리를 위해 현재 상태를 매 틱 확인해야 함

---

## GAS 연결 지점

```cpp
// LyraPlayerController.cpp:376
void ALyraPlayerController::PostProcessInput(const float DeltaTime, const bool bGamePaused)
{
    if (ULyraAbilitySystemComponent* LyraASC = GetLyraAbilitySystemComponent())
    {
        LyraASC->ProcessAbilityInput(DeltaTime, bGamePaused);  // 매 틱 호출됨
    }
    Super::PostProcessInput(DeltaTime, bGamePaused);
}
```

`ProcessAbilityInput` 내부에서는 이번 틱에 쌓인 `InputPressedSpecHandles` / `InputReleasedSpecHandles`를 소화하고, `WhileInputActive` 정책의 GA는 `bDown` 상태를 보고 매 틱 활성화를 시도한다.
