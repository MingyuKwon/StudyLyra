# Subsystem vs Component 역할 분리

> 출처: `Source/LyraGame/Character/LyraHeroComponent.cpp`  
> 엔진: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/`

---

## 역할 분리

| | UEnhancedInputLocalPlayerSubsystem | UEnhancedInputComponent |
|---|---|---|
| **부착 대상** | LocalPlayer (플레이어당 하나) | Actor (Pawn, PC 등) |
| **역할** | 활성 IMC 관리, 키 → Action 변환 | Action → 콜백 바인딩 |

`UEnhancedPlayerInput`이 실제 핵심이다. `UPlayerInput`의 서브클래스이며 `PlayerController->PlayerInput`으로 접근한다. Subsystem은 IMC 목록을 보관하고, PlayerInput이 매 틱 그 목록을 소비해서 ActionMappings를 빌드·평가한다.

---

## 처리 흐름

```
[키 입력]
    ↓
UEnhancedInputLocalPlayerSubsystem
  활성 IMC 목록을 보고 "W키 → IA_Move" 변환
    ↓
UEnhancedInputComponent
  "IA_Move Triggered → Input_Move() 호출"
    ↓
[함수 실행]
```

**Subsystem** = 키 → Action 번역기 (어떤 컨텍스트가 켜져 있는가)  
**Component** = Action → 함수 라우터 (발생한 Action을 누구에게 전달하는가)

---

## Lyra 코드에서의 분리

```cpp
// Subsystem: IMC 활성화 (어떤 키가 어떤 Action으로 바뀌는가)
Subsystem->AddMappingContext(IMC, Mapping.Priority, Options);

// Component: 콜백 바인딩 (Action 발생 시 뭘 실행하는가)
LyraIC->BindNativeAction(InputConfig, TAG_Move, ETriggerEvent::Triggered, this, &Input_Move);
```

두 작업이 모두 `InitializePlayerInput()`에서 일어나지만 역할은 완전히 다르다.

### 설정값 소비 시점

| 설정값 | 저장 위치 | 소비 단계 |
|---|---|---|
| `AddMappingContext` | Subsystem의 ActiveIMC 목록 | `PrepareInputDelegatesForEvaluation()` — 키 → Action 변환 |
| `BindNativeAction` | Component의 델리게이트 맵 | `EvaluateInputComponentDelegates()` — Action → 콜백 실행 |

Subsystem이 먼저 "이 키가 어떤 Action인가"를 결정하고, 그 결과를 Component가 받아 "이 Action이면 이 함수"를 실행한다.

---

## IMC가 LocalPlayer 단위인 이유

스플릿스크린에서 플레이어마다 다른 컨텍스트 세트를 가질 수 있기 때문이다. `UEnhancedInputLocalPlayerSubsystem`은 이름 그대로 LocalPlayer 하나에 하나가 존재한다.

---

## FEnhancedInputWorldProcessor — WorldSubsystem 전용 경로

`FSlateApplication`에 `IInputProcessor`로 등록되는 클래스다. LocalPlayer와 무관하게 `UEnhancedInputWorldSubsystem`(월드 레벨, 플레이어 없는 엔티티용)에만 이벤트를 전달하고 `return false`를 반환해 일반 위젯 라우팅을 계속 진행시킨다.

LocalPlayer의 콜백 발화 경로와 분리되어 있다. LocalPlayer 경로는 `PlayerController Tick → UEnhancedPlayerInput::EvaluateInputDelegates()`이다.
