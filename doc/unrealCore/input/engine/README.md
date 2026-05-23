# 엔진 입력 파이프라인

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

---

## 레거시 입력 파이프라인

언리얼의 기본 입력 파이프라인이다. Enhanced Input 이전, 그리고 Enhanced Input 이후에도 이 골격은 그대로 유지된다.

### 이벤트 수집 — OS → UPlayerInput

```
[OS 키 이벤트 (비동기)]
    → FSlateApplication::ProcessKeyDownEvent()
        → InputPreProcessors.HandleKeyDownEvent()    ← 등록된 PreProcessor들 실행
        → Tunnel/Bubble 위젯 라우팅
            → SViewport::OnKeyDown()
            → FSceneViewport::OnKeyDown()
            → UGameViewportClient::InputKey()
            → APlayerController::InputKey()
            → UPlayerInput::InputKey()
                    KeyStateMap에 이벤트 적재        ← EventAccumulator에 추가만 함, 콜백 없음

[패드 폴링 (동기, 매 Slate Tick)]
    FSlateApplication::Tick()
        → PlatformApplication->Tick()               ← XInput 폴링
            → OnControllerButtonPressed()  → ProcessKeyDownEvent()   (위와 동일 경로)
            → OnControllerAnalog()         → ProcessAnalogInputEvent()
```

### 콜백 처리 — PlayerController Tick

```
APlayerController::PlayerTick()
    → TickPlayerInput()
        → ProcessInputStack()
            EvaluateKeyMapState()           ← EventAccumulator → EventCounts flush, bDown 갱신
            EvaluateInputDelegates()        ← BindAction / BindAxis 콜백 실행
            PostProcessInput()              ← 오버라이드 가능한 후처리 훅 (기본은 빈 함수)
            FinishProcessingPlayerInput()   ← bDownPrevious = bDown
```

키 이벤트 수집과 콜백 실행이 분리된 구조다.  
이벤트는 OS 타이밍에 맞춰 Accumulator에 쌓이고, 처리는 매 PlayerController 틱에서 일괄 실행된다.

### 레거시의 한계

```cpp
// 키 → 함수를 코드에 직접 작성
PlayerInputComponent->BindAction("Jump", IE_Pressed, this, &ACharacter::Jump);
PlayerInputComponent->BindAxis("MoveForward", this, &ACharacter::MoveForward);
```

- **키-함수 하드코딩**: 런타임에 키 변경 불가, 리매핑 어려움
- **컨텍스트 없음**: 메뉴 / 전투 / 탈것 상황별 입력 세트 전환이 어려움
- **모디파이어 없음**: 데드존, 감도 배율, 축 변환을 직접 구현해야 함
- **트리거 없음**: 홀드, 탭, 더블탭, 코드(Chord) 조합을 직접 구현해야 함

---

## Enhanced Input — 도입 이유와 방식

### 왜 도입했는가

현대 게임은 상황에 따라 다른 입력 세트가 필요하다.

```
전투 중:   W → 이동,  LMB → 공격
차량 탑승: W → 가속,  LMB → 경적
메뉴 열림: W → 메뉴 이동,  Esc → 닫기
```

레거시에서 이를 처리하려면 코드에 상태 분기를 직접 작성해야 했다.  
Enhanced Input은 이 문제를 **IMC(Input Mapping Context)** 로 해결한다.

| 개념 | 역할 |
|------|------|
| **InputAction** | 물리 키와 분리된 추상 액션 (예: `IA_Move`, `IA_Jump`) |
| **IMC** | "어떤 키가 어떤 Action으로 바뀌는가"를 정의하는 에셋 |
| **Modifier** | 값 변환 (데드존, 스케일, DeltaTime 곱, 축 교체 등) |
| **Trigger** | 발화 조건 (Pressed / Released / Hold / Tap / Chord 등) |

런타임에 IMC를 추가/제거해서 현재 상황에 맞는 입력 세트로 즉시 전환할 수 있다.

### 어떻게 도입했는가 — 기존 파이프라인의 확장

Enhanced Input은 레거시 파이프라인을 **교체하지 않았다.** 클래스 교체와 오버라이드로 기존 골격 위에 얹었다.

#### 1. UEnhancedPlayerInput — UPlayerInput 교체

`PlayerController->PlayerInput`의 클래스가 `UPlayerInput` → `UEnhancedPlayerInput`으로 바뀐다.

| 오버라이드 함수 | 추가 동작 |
|----------------|----------|
| `EvaluateKeyMapState()` | Enhanced 키 상태 추가 추적 |
| `PrepareInputDelegatesForEvaluation()` | IMC → ActionMappings 빌드, 모디파이어/트리거 평가 |
| `EvaluateInputDelegates()` | Super(레거시) 호출 후 `UEnhancedInputComponent` 콜백 발화 |

이벤트 수집(`InputKey()` → KeyStateMap), Accumulator flush(`EvaluateKeyMapState` 기반), `PostProcessInput` 훅 — 모두 기존 골격을 그대로 사용한다.

#### 2. UEnhancedInputLocalPlayerSubsystem — IMC 관리

LocalPlayer당 하나 생성되는 서브시스템.  
`AddMappingContext()` / `RemoveMappingContext()`로 활성 IMC를 관리한다.  
`UEnhancedPlayerInput`은 매 틱 이 IMC 목록을 읽어 ActionMappings를 구성한다.

#### 3. UEnhancedInputComponent — InputAction → 콜백

`UInputComponent`를 상속한다. Pawn에 붙어 `BuildInputStack`에 올라간다.  
`BindAction(IA_Move, Triggered, this, &Input_Move)` 형태로 InputAction과 함수를 연결한다.

#### 4. FEnhancedInputWorldProcessor — WorldSubsystem 경로

PlayerController가 없는 월드 액터들을 위한 별도 경로.  
`IInputProcessor`로 등록되어 키 이벤트를 `UEnhancedInputWorldSubsystem`에 전달한다.  
LocalPlayer 입력과는 무관하다.

---

## 전체 큰그림 — 레거시와 Enhanced 비교

```
─────────────────────────────────────────────────────────────────
                    레거시 입력                Enhanced Input
─────────────────────────────────────────────────────────────────
[OS 이벤트]
    ↓
FSlateApplication
  InputPreProcessors       (없음)          FEnhancedInputWorldProcessor
                                           → WorldSubsystem 전달 (return false)
  위젯 라우팅
    SViewport → UGameViewportClient → PlayerController::InputKey()
         ↓
  UPlayerInput::InputKey()          UEnhancedPlayerInput::InputKey()
    (동일 구조 — KeyStateMap 갱신)

─────────────────────────────────────────────────────────────────
[PlayerController Tick]
  EvaluateKeyMapState()              EvaluateKeyMapState()
    Accumulator flush, bDown 갱신      + Enhanced 키 상태 추적

  EvaluateInputDelegates()           EvaluateInputDelegates() ★
    BindAction/BindAxis 콜백 실행      PrepareInputDelegatesForEvaluation()
    (코드 하드코딩 → 직접 실행)          → IMC로 ActionMappings 빌드
                                      → Modifier / Trigger 평가
                                     EvaluateInputComponentDelegates()
                                      → Input_Move() 등 콜백 실행
                                      → AbilityInputTagPressed()

  PostProcessInput()                 PostProcessInput() ★ (Lyra 오버라이드)
    (기본: 빈 함수)                     → ProcessAbilityInput()
                                         → TryActivateAbility()

  FinishProcessingPlayerInput()      FinishProcessingPlayerInput()
    bDownPrevious = bDown              (동일)
─────────────────────────────────────────────────────────────────
```

핵심 차이는 `EvaluateInputDelegates` 하나다.  
레거시는 코드에 직접 등록한 키-함수 쌍을 실행하고,  
Enhanced는 IMC → ActionMappings → Modifier/Trigger → InputAction → 콜백 체인을 실행한다.  
나머지 파이프라인은 동일하다.

---

## 현재 흐름 (Enhanced Input 적용)

```
[키 입력 / 패드 폴링]
    ↓
FSlateApplication::Tick()
    위젯 라우팅 (이벤트 발생 시)
        SViewport → UGameViewportClient
            → UEnhancedPlayerInput::InputKey()   ← KeyStateMap 갱신
    ↓
APlayerController::PlayerTick()
    ProcessInputStack()
        EvaluateKeyMapState()            ← bDown 갱신
        EvaluateInputDelegates()  ★
            → Input_Move(), Input_LookMouse() 등  ← Native 입력 처리 완료
            → AbilityInputTagPressed()             ← Ability 입력 큐에 적재
        PostProcessInput()  ★
            LyraASC->ProcessAbilityInput()
                InputPressedSpecHandles → TryActivateAbility()
                InputHeldSpecHandles → WhileInputActive GA 매 틱 실행
```

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. Enhanced Input](01_enhanced_input.md) | Subsystem vs Component 역할 분리, IMC, BindAction 오버로드 3종 |
| [02. InputPreProcessor](02_preprocessor.md) | FEnhancedInputWorldProcessor 역할, 커스텀 PreProcessor 패턴 |
| [03. 틱 처리 · GAS 연결](03_tick_and_gas.md) | PostProcessInput → ProcessAbilityInput, bDown 홀드 유지, BuildInputStack |
| [04. 게임패드](04_gamepad.md) | 디지털/아날로그 분기, FSlateApplication 진입 경로, 데드존, 진동 |
| [05. 레거시 vs Enhanced Input](05_legacy_vs_enhanced.md) | 두 구조 상세 비교, PrepareInputDelegatesForEvaluation 위치, 공존 타임라인 |

---

## 배경 지식

Slate 내부 라우팅, ViewportClient 경로, 레거시 입력 처리가 궁금할 때:  
→ [background/](background/README.md)

---

## GAS 개발자 시작점

```
01_enhanced_input.md        ← Enhanced Input 구조 파악
    ↓
02_preprocessor.md          ← PreProcessor 패턴, 커스텀 차단 구현
    ↓
03_tick_and_gas.md          ← PostProcessInput → ProcessAbilityInput
    ↓
lyra/03_ability_input.md    ← AbilityInputTagPressed → TryActivateAbility
```
