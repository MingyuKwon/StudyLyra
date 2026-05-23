# 레거시 입력 vs Enhanced Input

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedInputWorldProcessor.cpp`

---

Enhanced Input은 레거시 `UPlayerInput`을 교체한 것이 아니다.  
`PlayerController->PlayerInput`의 클래스를 `UEnhancedPlayerInput`으로 바꾸고, `ProcessInputStack` 안의 처리 함수들을 오버라이드하는 방식이다.  
입력이 들어오는 경로와 콜백이 발화하는 위치 모두 레거시와 동일하다. 다른 것은 처리 로직이다.

---

## 레거시 구조

```
[키 누름] → SViewport → UGameViewportClient → APlayerController::InputKey()
                → UPlayerInput::InputKey()             ← KeyStateMap 갱신

APlayerController::PlayerTick()
    ProcessInputStack()
        EvaluateKeyMapState()                          ← Accumulator flush, bDown 갱신
        EvaluateInputDelegates()                       ← BindAction/BindAxis 콜백 실행
        PostProcessInput()                             ← 오버라이드 가능한 훅
        FinishProcessingPlayerInput()                  ← bDownPrevious = bDown
```

`BindAction("Jump", IE_Pressed, this, &AMyCharacter::Jump)`처럼 키를 직접 함수에 연결한다.  
키 → 함수 매핑이 코드에 하드코딩되고, 런타임에 교체할 수 없다.

---

## Enhanced Input 구조 (LocalPlayer)

```
[키 누름] → SViewport → UGameViewportClient → APlayerController::InputKey()
                → UEnhancedPlayerInput::InputKey()     ← KeyStateMap 갱신 (레거시와 동일)

APlayerController::PlayerTick()
    ProcessInputStack()
        EvaluateKeyMapState()                          ← 동일 (bDown 갱신)
        PrepareInputDelegatesForEvaluation()           ← Enhanced만: IMC → ActionMappings 처리, 모디파이어/트리거 평가
        EvaluateInputDelegates()
            Super::EvaluateInputDelegates()            ← 레거시 BindAction 경로 (Enhanced에서 빈 껍데기)
            EvaluateInputComponentDelegates()          ← UEnhancedInputComponent 콜백 발화 ★
        PostProcessInput()
            LyraASC->ProcessAbilityInput()             ← GAS 브릿지
        FinishProcessingPlayerInput()
```

콜백이 발화하는 위치는 레거시와 동일하다 — `EvaluateInputDelegates` 안, PlayerController 틱에서.  
다른 것은 `UEnhancedPlayerInput`이 IMC 기반으로 키를 ActionMapping으로 변환하는 로직이 중간에 추가된다는 점이다.

---

## 두 구조 비교

| | 레거시 | Enhanced Input (LocalPlayer) |
|---|---|---|
| **PlayerInput 클래스** | `UPlayerInput` | `UEnhancedPlayerInput` |
| **콜백 발화 위치** | `EvaluateInputDelegates` (레거시 경로) | `EvaluateInputDelegates` (Enhanced 경로) — 같은 함수, 다른 구현 |
| **키 → 함수 연결** | 코드 하드코딩 (`BindAction("Jump", ...)`) | IMC 에셋 (런타임 교체 가능) |
| **포커스 의존** | SViewport 포커스 필요 | SViewport 포커스 필요 (동일) |
| **PreProcessor 역할** | 없음 | WorldSubsystem 전달용 — LocalPlayer 콜백과 무관 |
| **GAS 연결** | 없음 (수동 구현 필요) | PostProcessInput → ProcessAbilityInput |

---

## EvaluateInputDelegates 내부 — 레거시 경로와 Enhanced 경로

`UEnhancedPlayerInput::EvaluateInputDelegates()`는 두 단계로 나뉜다.

```cpp
// EnhancedPlayerInput.cpp:339
void UEnhancedPlayerInput::EvaluateInputDelegates(...)
{
    Super::EvaluateInputDelegates(...);   // ① 레거시 경로
    // ② Enhanced 경로
    for (UInputComponent* IC : InputComponentStack)
    {
        if (UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(IC))
            EvaluateInputComponentDelegates(EIC, ...);   // 콜백 발화
    }
}
```

- ① 레거시 경로: `BindAction/BindAxis`로 등록된 콜백 실행. `UEnhancedInputComponent`는 여기서 처리되지 않으므로 빈 껍데기.
- ② Enhanced 경로: `UEnhancedInputComponent`에 바인딩된 `Input_Move()`, `AbilityInputTagPressed()` 등 실행.

---

## AbilityInputTagPressed가 적재되는 타이밍

```
EvaluateInputDelegates()
    → UEnhancedInputComponent 콜백
        → AbilityInputTagPressed(Tag)    ← InputPressedSpecHandles에 추가
    (콜백 완료)
PostProcessInput()
    → ProcessAbilityInput()
        → InputPressedSpecHandles 읽기 → TryActivateAbility()
```

`AbilityInputTagPressed()`는 `EvaluateInputDelegates` 안에서 호출되고,  
`ProcessAbilityInput()`은 같은 틱의 `PostProcessInput`에서 handles를 읽는다.  
적재와 소비가 같은 PlayerController 틱 안에서 일어난다.

---

## FEnhancedInputWorldProcessor — PreProcessor의 실제 역할

`FSlateApplication`에 등록된 Enhanced Input PreProcessor는 `FEnhancedInputWorldProcessor`다.  
`UEnhancedInputLocalPlayerSubsystem`이 아니다.

```cpp
// EnhancedInputWorldProcessor.cpp:15
bool FEnhancedInputWorldProcessor::HandleKeyDownEvent(...)
{
    InputKeyToSubsystem(Params);   // UEnhancedInputWorldSubsystem에만 전달
    return false;                  // 항상 false — 위젯 라우팅 계속
}
```

`InputKeyToSubsystem`은 `UEnhancedInputWorldSubsystem`(월드 레벨 서브시스템)을 순회한다.  
이것은 PlayerController 없이 월드 액터들이 Enhanced Input을 쓸 수 있게 하는 별도 경로다.  
**LocalPlayer(Lyra)의 콜백과는 무관하다.**

---

## 두 시스템이 공존하는 방식 — 타임라인

```
Slate Tick (OS 메시지 처리)
  [1] FEnhancedInputWorldProcessor::HandleKeyDownEvent()
        → UEnhancedInputWorldSubsystem 전달     ← WorldSubsystem 경로만
        → return false
  [2] 위젯 라우팅 (Tunnel/Bubble)
        → SViewport::OnKeyDown()
        → UGameViewportClient::InputKey()
        → UEnhancedPlayerInput::InputKey()       ← KeyStateMap 갱신

PlayerController Tick (콜백 발화)
  [3] EvaluateKeyMapState()                      ← Accumulator flush, bDown 갱신
  [4] PrepareInputDelegatesForEvaluation()       ← IMC → ActionMappings, 모디파이어/트리거 계산
  [5] EvaluateInputDelegates()
        Input_Move() 등 콜백 발화               ← Native 입력 완료
        AbilityInputTagPressed()                 ← GAS handles 적재
  [6] PostProcessInput()
        ProcessAbilityInput()                    ← TryActivateAbility
  [7] FinishProcessingPlayerInput()              ← bDownPrevious = bDown
```

[1][2]는 Slate Tick(같은 프레임 내 OS 메시지 처리), [3]~[7]은 PlayerController Tick.  
콜백이 발화하는 [5]는 레거시도 Enhanced도 같은 위치다.

---

## 관련 문서

- [01_enhanced_input.md](01_enhanced_input.md) — Subsystem/Component 역할 분리
- [02_preprocessor.md](02_preprocessor.md) — PreProcessor 등록 패턴, 커스텀 차단 예시
- [03_tick_and_gas.md](03_tick_and_gas.md) — PostProcessInput → ProcessAbilityInput 상세
- [background/03_legacy_tick_detail.md](background/03_legacy_tick_detail.md) — Accumulator 패턴, bDown, EvaluateInputDelegates 상세
