# 엔진 입력 파이프라인 — Enhanced Input 중심

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`

---

## Enhanced Input 관점 전체 흐름

```
[키 입력 / 패드 폴링]
    ↓
FSlateApplication::Tick()
    InputPreProcessors — UEnhancedInputLocalPlayerSubsystem
        IMC로 키 → InputAction 변환
        UEnhancedInputComponent 콜백 실행
            → Input_Move(), Input_LookMouse() 등  ← Native 입력 처리 완료
            → AbilityInputTagPressed()             ← Ability 입력 큐에 적재
    ↓
APlayerController::PlayerTick()
    ProcessInputStack()
        PostProcessInput()  ★
            LyraASC->ProcessAbilityInput()
                InputPressedSpecHandles → TryActivateAbility()
                InputHeldSpecHandles → WhileInputActive GA 매 틱 실행
```

**Native 입력(이동/시점)**: Slate 틱 — PreProcessor 단계에서 처리 완료  
**GAS Ability 입력**: PlayerController 틱 — PostProcessInput에서 처리

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. Enhanced Input](01_enhanced_input.md) | Subsystem vs Component 역할 분리, IMC, BindAction 오버로드 3종 |
| [02. InputPreProcessor](02_preprocessor.md) | Enhanced Input이 IInputProcessor를 구현하는 이유, 커스텀 PreProcessor 패턴 |
| [03. 틱 처리 · GAS 연결](03_tick_and_gas.md) | PostProcessInput → ProcessAbilityInput, bDown 홀드 유지, BuildInputStack |
| [04. 게임패드](04_gamepad.md) | 디지털/아날로그 분기, FSlateApplication 진입 경로, 데드존, 진동 |
| [05. 레거시 vs Enhanced Input](05_legacy_vs_enhanced.md) | 두 구조 비교, UPlayerInput이 여전히 살아있는 이유, 공존 방식 |

---

## 배경 지식

Slate 내부 라우팅, ViewportClient 경로, 레거시 입력 처리가 궁금할 때:  
→ [background/](background/README.md)

---

## GAS 개발자 시작점

```
01_enhanced_input.md        ← Enhanced Input 구조 파악
    ↓
02_preprocessor.md          ← 왜 포커스 무관 전역 처리가 가능한가
    ↓
03_tick_and_gas.md          ← PostProcessInput → ProcessAbilityInput
    ↓
lyra/03_ability_input.md    ← AbilityInputTagPressed → TryActivateAbility
```
