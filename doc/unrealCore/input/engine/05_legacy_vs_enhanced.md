# 레거시 입력 vs Enhanced Input

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedInputSubsystems.cpp`

---

Enhanced Input은 레거시 UPlayerInput 구조를 **교체한 것이 아니다.**  
기존 파이프라인 위에 얹어서 자기 처리를 먼저 끝내고, 레거시 단계는 빈 껍데기로 통과시킨다.

---

## 레거시 구조

```
[키 입력]
    ↓
UPlayerInput::InputKey()          ← EventAccumulator에 적재
    ↓
APlayerController::PlayerTick()
    ProcessInputStack()
        EvaluateKeyMapState()     ← Accumulator flush, bDown 갱신
        EvaluateInputDelegates()  ← BindAction/BindAxis 콜백 실행
        PostProcessInput()        ← 오버라이드 가능한 후처리 훅
        FinishProcessingPlayerInput()  ← bDownPrevious = bDown
```

`BindAction("Jump", IE_Pressed, this, &AMyCharacter::Jump)`처럼 키를 직접 함수에 연결한다.  
키 → 함수 매핑이 코드에 하드코딩되고, 런타임에 교체할 수 없다.

---

## Enhanced Input 구조

```
[키 입력]
    ↓
FSlateApplication::Tick()
    InputPreProcessors
        UEnhancedInputLocalPlayerSubsystem::Tick()
            활성 IMC로 키 → InputAction 변환
            UEnhancedInputComponent 콜백 실행   ← 여기서 콜백 완료
    ↓
APlayerController::PlayerTick()
    ProcessInputStack()
        EvaluateKeyMapState()                   ← 여전히 실행 (bDown 갱신)
        EvaluateInputDelegates()                ← Enhanced IC는 추가 발화 없음 (빈 껍데기)
        PostProcessInput()
            LyraASC->ProcessAbilityInput()      ← GAS 브릿지
        FinishProcessingPlayerInput()
```

콜백이 **PlayerController 틱이 아닌 Slate 틱**에서 실행된다.  
IMC(Input Mapping Context)를 런타임에 추가/제거해서 활성 키 집합을 동적으로 바꿀 수 있다.

---

## 두 구조 비교

| | 레거시 | Enhanced Input |
|---|---|---|
| **콜백 실행 위치** | PlayerController 틱 — EvaluateInputDelegates | Slate 틱 — PreProcessor::Tick |
| **키 → 함수 연결** | 코드 하드코딩 (`BindAction("Jump", ...)`) | IMC 에셋 (런타임 교체 가능) |
| **UPlayerInput 사용** | 사용 | 여전히 사용 |
| **KeyStateMap / bDown** | EvaluateInputDelegates가 직접 참조 | Enhanced가 직접 참조 안 함 — 하지만 갱신은 됨 |
| **포커스 의존** | SViewport가 포커스를 가져야 UPlayerInput::InputKey() 도달 | PreProcessor는 포커스 무관 실행 |
| **GAS 연결** | 없음 (수동 구현 필요) | PostProcessInput → ProcessAbilityInput |

---

## UPlayerInput이 여전히 살아있는 이유

Enhanced Input을 사용해도 `UPlayerInput::InputKey()`는 계속 호출되고 `KeyStateMap`이 갱신된다.

```
SViewport::OnKeyDown()
    → UGameViewportClient::InputKey()
        → APlayerController::InputKey()
            → UPlayerInput::InputKey()   ← Enhanced Input 사용 여부와 무관하게 실행
```

Enhanced Input PreProcessor가 `false`를 반환하므로 Slate 위젯 라우팅이 계속 진행되고,  
결국 `SViewport → UGameViewportClient → UPlayerInput`까지 도달한다.

`UPlayerInput`의 `bDown`은 "이 키가 현재 눌려있는가"를 추적하는 상태다.  
Enhanced Input 콜백과는 별개로 이 상태 자체는 계속 정확하게 유지된다.

---

## EvaluateInputDelegates가 빈 껍데기인 이유

레거시에서는 `UInputComponent`에 `BindAction/BindAxis`로 등록한 델리게이트를 이 단계에서 실행한다.

Enhanced Input에서는 `UEnhancedInputComponent`가 InputComponent 스택에 있지만,  
콜백이 이미 PreProcessor 단계에서 실행됐으므로 이 단계에서 추가로 발화할 것이 없다.  
`EvaluateInputDelegates()`는 돌지만 아무것도 실행하지 않고 통과한다.

---

## PostProcessInput은 레거시 구조가 아니다

```cpp
// 레거시 PlayerController — PostProcessInput 오버라이드 없음
// → 기본 구현 (빈 함수)

// Lyra PlayerController — GAS 브릿지로 오버라이드
void ALyraPlayerController::PostProcessInput(const float DeltaTime, const bool bGamePaused)
{
    if (ULyraAbilitySystemComponent* LyraASC = GetLyraAbilitySystemComponent())
        LyraASC->ProcessAbilityInput(DeltaTime, bGamePaused);
    Super::PostProcessInput(DeltaTime, bGamePaused);
}
```

`PostProcessInput`은 레거시 콜백 단계(`EvaluateInputDelegates`)가 끝난 뒤에 불리는 **훅**이다.  
Lyra는 이 훅을 GAS 연결 지점으로 활용한다. 레거시 입력과는 무관하다.

Enhanced Input PreProcessor가 `AbilityInputTagPressed()`를 호출해서 `InputPressedSpecHandles`에 적재해두면,  
`PostProcessInput`에서 그 핸들을 읽어 `TryActivateAbility()`를 실행한다.

---

## 두 시스템이 공존하는 방식 — 타임라인

```
Slate Tick
  [1] EnhancedInput PreProcessor::Tick()
        키 → InputAction 변환
        Input_Move() 콜백 실행           ← Native 입력 완료
        AbilityInputTagPressed() 호출    ← handles 적재

  [2] 위젯 라우팅 (Tunnel/Bubble)
        SViewport::OnKeyDown()
        UPlayerInput::InputKey()         ← KeyStateMap 갱신

PlayerController Tick
  [3] EvaluateKeyMapState()              ← Accumulator flush, bDown 갱신
  [4] EvaluateInputDelegates()           ← 빈 껍데기 통과
  [5] PostProcessInput()
        ProcessAbilityInput()            ← TryActivateAbility 실행
  [6] FinishProcessingPlayerInput()      ← bDownPrevious = bDown
```

[1]과 [2]는 같은 Slate Tick 안에서 순서대로 일어난다.  
[3]~[6]은 그다음 PlayerController Tick에서 일어난다.

---

## 관련 문서

- [01_enhanced_input.md](01_enhanced_input.md) — Subsystem/Component 역할 분리
- [02_preprocessor.md](02_preprocessor.md) — PreProcessor 등록 · 포커스 무관 실행 원리
- [03_tick_and_gas.md](03_tick_and_gas.md) — PostProcessInput → ProcessAbilityInput 상세
- [background/03_legacy_tick_detail.md](background/03_legacy_tick_detail.md) — Accumulator 패턴, bDown, EvaluateInputDelegates 상세
