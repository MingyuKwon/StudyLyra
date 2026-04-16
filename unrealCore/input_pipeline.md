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
    ├─ TickPlayerInput(DeltaTime, bGamePaused)    ← :2326
    │       │
    │       ├─ PlayerInput->Tick()               ← 제스처 인식 등
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
            ├─ PreProcessInput()             ← virtual 훅 (처리 전)
            ├─ EvaluateKeyMapState()         ← Accumulator → EventCounts 복사
            ├─ EvaluateInputDelegates()      ← 바인딩된 액션/축 델리게이트 실행
            ├─ PostProcessInput()            ← virtual 훅 (처리 후) ← Lyra가 여기를 오버라이드
            └─ FinishProcessingPlayerInput()
```

---

## 두 단계로 분리된 이유 — Accumulator 패턴

입력 처리는 **비동기 이벤트 수집**과 **동기 처리**로 분리된다.

### 1단계: 이벤트 수집 (틱과 무관, OS 이벤트 발생 시)

```cpp
// PlayerInput.cpp:278
bool UPlayerInput::InputKey(const FInputKeyEventArgs& Params)
{
    FKeyState& KeyState = KeyStateMap.FindOrAdd(Params.Key);
    KeyState.EventAccumulator[IE_Pressed].Add(++EventCount);  // 버퍼에 누적
    KeyState.RawValueAccumulator.X += Params.AmountDepressed;
}
```

- OS로부터 키 이벤트가 오면 `InputKey()`를 통해 `EventAccumulator`에 **누적만** 한다.
- 이 시점에는 아무것도 실행되지 않는다.

### 2단계: 일괄 처리 (매 틱 — EvaluateKeyMapState)

```cpp
// PlayerInput.cpp:1281 — 매 틱 호출
for (TMap<FKey,FKeyState>::TIterator It(KeyStateMap); It; ++It)
{
    // Accumulator → EventCounts 로 이동 (flush)
    Exchange(KeyState->EventCounts[EventIndex], KeyState->EventAccumulator[EventIndex]);

    // Accumulator 초기화
    KeyState->RawValueAccumulator = FVector(0.f, 0.f, 0.f);
}
```

- 매 틱, 누적된 `EventAccumulator`를 `EventCounts`로 **한 번에 flush**한다.
- 이 배열이 비어 있어도(이번 틱에 입력 없음) 함수는 돈다.

---

## 키 홀드 상태가 유지되는 원리

```cpp
// PlayerInput.cpp:1220 (ProcessNonAxesKeys 내부)
if (KeyState->EventCounts[IE_Pressed].Num() > 0)
{
    KeyState->bDown = true;
}
else
{
    KeyState->bDown = KeyState->bDownPrevious;  // 이전 프레임 상태 유지
}
```

- 이번 틱에 새 이벤트가 없으면 `bDown = bDownPrevious`로 **이전 상태를 그대로 복사**.
- 키를 계속 누르고 있으면 매 틱 `bDown == true` 상태가 유지된다.
- 이것이 `WhileInputActive` 정책이 동작하는 근거다.

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
