# 엔진 입력 파이프라인

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

---

## 도입 배경

언리얼 레거시 입력은 키와 함수를 코드에 직접 연결한다.

```cpp
PlayerInputComponent->BindAction("Jump", IE_Pressed, this, &ACharacter::Jump);
```

- **키-함수 하드코딩**: 런타임 리매핑 불가
- **컨텍스트 없음**: 메뉴 / 전투 / 탈것 상황별 입력 세트 전환이 어려움
- **모디파이어 없음**: 데드존, 감도, 축 변환을 직접 구현해야 함
- **트리거 없음**: 홀드, 탭, 더블탭, Chord 조합을 직접 구현해야 함

Enhanced Input은 **IMC(Input Mapping Context)** 로 이 문제를 해결한다.

| 개념 | 역할 |
|------|------|
| **InputAction** | 물리 키와 분리된 추상 액션 (`IA_Move`, `IA_Jump`) |
| **IMC** | "어떤 키가 어떤 Action인가"를 정의하는 에셋 |
| **Modifier** | 값 변환 (데드존, 스케일, DeltaTime 곱, 축 교체 등) |
| **Trigger** | 발화 조건 (Pressed / Released / Hold / Tap / Chord 등) |

런타임에 IMC를 교체하면 입력 세트가 즉시 바뀐다. Enhanced Input은 레거시를 교체하지 않고 **서브클래싱과 오버라이드**로 기존 골격 위에 얹었다.

---

## 파이프라인 비교

### 레거시

```
[키/패드 이벤트]
    ↓
FSlateApplication → SViewport → UGameViewportClient
    ↓
UPlayerInput::InputKey()             ← KeyStateMap 갱신 (콜백 없음)

APlayerController::PlayerTick()
    EvaluateKeyMapState()            ← Accumulator flush, bDown 갱신
    EvaluateInputDelegates()         ← BindAction/BindAxis 콜백 (코드 하드코딩)
    PostProcessInput()               ← 빈 함수
    FinishProcessingPlayerInput()    ← bDownPrevious = bDown
```

### Enhanced Input

```
[키/패드 이벤트]
    ↓
FSlateApplication::ProcessKeyDownEvent()
    InputPreProcessors
        FEnhancedInputWorldProcessor::HandleKeyDownEvent()
            → UEnhancedInputWorldSubsystem 전달  ← WorldSubsystem 전용 경로
            return false                          ← 위젯 라우팅 계속 진행
    위젯 라우팅 → SViewport → UGameViewportClient
        ↓
UEnhancedPlayerInput::InputKey()     ← KeyStateMap 갱신 (레거시와 동일)

APlayerController::PlayerTick()
    EvaluateKeyMapState()            ← 동일 + Enhanced 키 상태 추적
    EvaluateInputDelegates()  ★      ← UEnhancedPlayerInput 오버라이드
        PrepareInputDelegatesForEvaluation()
            → Subsystem->GetActiveIMCs() 읽음  ← AddMappingContext 값 여기서 소비
            → IMC → ActionMappings 빌드
            → Modifier / Trigger 평가
        EvaluateInputComponentDelegates()
            → UEnhancedInputComponent 바인딩 실행  ← BindNativeAction 바인딩 여기서 소비
            → Input_Move() 등 콜백 실행
            → AbilityInputTagPressed()            ← handles 적재
    PostProcessInput()  ★            ← Lyra 오버라이드
        ProcessAbilityInput()
            → TryActivateAbility()
    FinishProcessingPlayerInput()    ← 동일
```

### 왜 EvaluateKeyMapState와 EvaluateInputDelegates를 분리했는가

두 함수의 책임이 다르다. **"상태 확정"과 "반응"을 의도적으로 분리한 것이다.**

**EvaluateKeyMapState** — 이번 틱의 상태를 확정(스냅샷)한다.

```
EventAccumulator (OS 이벤트가 비동기로 쌓이는 곳)
    → EventCounts로 이동 후 Accumulator 초기화
    → bDown, bDownPrevious 갱신
```

이 함수가 끝나면 "W가 눌렸는가 / 홀드 중인가 / 떼어졌는가"가 이번 틱 기준으로 확정된다.

**EvaluateInputDelegates** — 확정된 상태에 반응한다.

확정된 EventCounts / bDown을 읽어 등록된 콜백을 실행한다.

분리하지 않으면 콜백 실행 도중 새 OS 이벤트가 들어와 상태가 바뀔 수 있다.

```
[OS 이벤트 — 비동기]          [게임 틱 — 동기]
키 이벤트 → Accumulator       EvaluateKeyMapState()    → 스냅샷 확정
                              EvaluateInputDelegates() → 콜백 실행
키 이벤트 → Accumulator  ←── 이 시점에 새 이벤트가 들어와도 이번 틱에 영향 없음
```

`EvaluateKeyMapState`가 Accumulator를 비워 스냅샷을 만드는 순간, 이후 OS 이벤트는 다음 틱 Accumulator에만 쌓인다. Enhanced Input이 `EvaluateInputDelegates()` 안에 `PrepareInputDelegatesForEvaluation()`을 끼워 넣을 수 있는 것도 이 구조 덕분이다.

### 설정값 소비 시점

| 설정값 | 저장 위치 | 소비 단계 |
|---|---|---|
| `AddMappingContext` | Subsystem의 ActiveIMC 목록 | `PrepareInputDelegatesForEvaluation()` — 키 → Action 변환 |
| `BindNativeAction` | Component의 델리게이트 맵 | `EvaluateInputComponentDelegates()` — Action → 콜백 실행 |

Subsystem이 먼저 "이 키가 어떤 Action인가"를 결정하고, 그 결과를 Component가 받아 "이 Action이면 이 함수"를 실행한다.

---

## 핵심 차이

| 단계 | 레거시 | Enhanced Input |
|------|--------|----------------|
| PlayerInput 클래스 | `UPlayerInput` | `UEnhancedPlayerInput` |
| PreProcessor 역할 | 없음 | `FEnhancedInputWorldProcessor` — WorldSubsystem 전달만 (LocalPlayer와 무관) |
| 키 → 함수 연결 | 코드 하드코딩 | IMC 에셋 (런타임 교체 가능) |
| `EvaluateInputDelegates` | BindAction/BindAxis 콜백 직접 실행 | IMC → ActionMappings → Modifier/Trigger → 콜백 체인 |
| `PostProcessInput` | 빈 함수 | `ProcessAbilityInput()` → `TryActivateAbility()` |
| GAS 연결 | 없음 (수동 구현 필요) | `PostProcessInput` → `ProcessAbilityInput` |

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [00. InputComponent](00_input_component.md) | InputComponent 개념, PC/Pawn 생성 위치, 기본 클래스 결정, EnableInput |
| [01. Enhanced Input](01_enhanced_input.md) | Subsystem vs Component 역할 분리, IMC, BindAction 오버로드 3종 |
| [02. InputPreProcessor](02_preprocessor.md) | FEnhancedInputWorldProcessor 역할, 커스텀 PreProcessor 패턴 |
| [03. 틱 처리 · GAS 연결](03_tick_and_gas.md) | PostProcessInput → ProcessAbilityInput, bDown 홀드 유지, BuildInputStack |
| [04. 게임패드](04_gamepad/README.md) | 폴링 vs 인터럽트, 디지털/아날로그, 데드존, Modifier, 진동, 플랫폼 특수 기능 |
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
