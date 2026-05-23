# 틱 처리 상세 — Accumulator 패턴 · 레거시 입력

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`

---

Enhanced Input을 사용하면 이 문서의 내용은 직접 건드릴 일이 없다.  
`bDown` 홀드 유지 원리나 레거시 `BindAction` 콜백 흐름이 궁금할 때 참고한다.

---

## Accumulator 패턴 — 비동기 수집 · 동기 처리 분리

키 이벤트는 OS에서 비동기로 도착한다. 매 틱 처리와 분리하기 위해 두 단계로 나뉜다.

### 1단계: 이벤트 수집 (OS 이벤트 발생 시)

```cpp
// PlayerInput.cpp:278
bool UPlayerInput::InputKey(const FInputKeyEventArgs& Params)
{
    FKeyState& KeyState = KeyStateMap.FindOrAdd(Params.Key);

    switch (Params.Event)
    {
    case IE_Pressed:
    case IE_Repeat:
        KeyState.RawValueAccumulator.X = Params.AmountDepressed;
        KeyState.EventAccumulator[Params.Event].Add(++EventCount);
        break;
    case IE_Released:
        KeyState.RawValueAccumulator.X = 0.f;
        KeyState.EventAccumulator[IE_Released].Add(++EventCount);
        break;
    }
}
```

`EventAccumulator`에 이벤트 번호만 추가한다. 콜백은 실행되지 않는다.

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

        // Accumulator → EventCounts swap (flush)
        for (uint8 EventIndex = 0; EventIndex < IE_MAX; ++EventIndex)
        {
            KeyState->EventCounts[EventIndex].Reset();
            Exchange(KeyState->EventCounts[EventIndex], KeyState->EventAccumulator[EventIndex]);

            if (KeyState->EventCounts[EventIndex].Num() > 0)
                KeysWithEvents.Emplace(Key, KeyState);
        }

        KeyState->RawValue = KeyState->RawValueAccumulator;
        ProcessNonAxesKeys(Key, KeyState);          // bDown 갱신

        KeyState->RawValueAccumulator = FVector(0.f, 0.f, 0.f);
        KeyState->SampleCountAccumulator = 0;
    }
}
```

`KeyStateMap` 전체를 순회한다. 이번 틱에 이벤트가 없어도 모든 키를 처리한다.

---

## bDown 홀드 상태 유지 원리

```cpp
// PlayerInput.cpp:1210
void UPlayerInput::ProcessNonAxesKeys(FKey InKey, FKeyState* KeyState)
{
    int32 const PressDelta = KeyState->EventCounts[IE_Pressed].Num()
                           - KeyState->EventCounts[IE_Released].Num();

    if (PressDelta < 0)
        KeyState->bDown = false;              // Released 더 많음 → 뗐다
    else if (PressDelta > 0)
        KeyState->bDown = true;               // Pressed 더 많음 → 눌렀다
    else
        KeyState->bDown = KeyState->bDownPrevious;  // 이벤트 없음 → 이전 상태 유지
}

// PlayerInput.cpp:1747
void UPlayerInput::FinishProcessingPlayerInput()
{
    for (TMap<FKey,FKeyState>::TIterator It(KeyStateMap); It; ++It)
    {
        FKeyState& KeyState = It.Value();
        KeyState.bDownPrevious = KeyState.bDown;  // 다음 틱을 위해 보존
        KeyState.bConsumed = false;
    }
}
```

키를 계속 누르고 있으면 OS Repeat 이벤트와 무관하게 `bDownPrevious` 복사만으로 매 틱 `bDown == true`가 유지된다.

---

## EvaluateInputDelegates — 레거시 BindAction/BindAxis 콜백

```
EvaluateInputDelegates(InputComponentStack, KeysWithEvents)
    │
    ├─ InputComponent 스택을 높은 우선순위 → 낮은 순으로 순회
    │       └─ EvaluateInputComponentDelegates(IC)
    │               ├─ KeysWithEvents에서 바인딩된 키 찾기
    │               ├─ 매칭된 바인딩을 NonAxisDelegates / AxisDelegates에 수집
    │               └─ bConsumed → 스택 순회 중단
    │
    └─ SortAndExecuteDelegates()
            ActionDelegate.Execute(Key)    ← BindAction 콜백 실행
            Delegate.Execute(Value)         ← BindAxis 콜백 실행
```

Enhanced Input을 사용할 때 이 단계(`UPlayerInput::EvaluateInputDelegates`)의 **레거시 경로**는 빈 껍데기다.  
`UEnhancedPlayerInput`은 `EvaluateInputDelegates`를 오버라이드해서 Enhanced 콜백을 별도로 발화한다.  
즉 `EvaluateInputDelegates` 자체는 빈 껍데기가 아니라, 레거시 부분(BindAction 경로)만 빈 껍데기다.  
→ 상세는 [../05_legacy_vs_enhanced.md](../05_legacy_vs_enhanced.md)
