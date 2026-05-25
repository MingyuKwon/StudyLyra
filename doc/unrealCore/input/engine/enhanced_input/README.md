# Enhanced Input 엔진 구현

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/`

Enhanced Input이 어떻게 동작하는지를 클래스 역할, 파이프라인, 내부 자료구조 수준에서 다룬다.

---

## 클래스 레퍼런스 — 클래스 하나씩 이해하기

| 클래스 | 역할 한 줄 요약 |
|--------|----------------|
| [UInputAction](UInputAction.md) | 추상 행동 단위 (DataAsset). ValueType·AccumulationBehavior·Triggers·Modifiers |
| [UInputMappingContext](UInputMappingContext.md) | 키↔Action 매핑 테이블 (DataAsset). 컨텍스트별로 교체 가능 |
| [UInputModifier](UInputModifier.md) | 입력값 변환기. 체인 실행, 두 레벨(Mapping/Action), 내장 목록 |
| [UInputTrigger](UInputTrigger.md) | 발화 조건 판단기. ETriggerState/Type/Event, Chord, Combo |
| [UEnhancedInputLocalPlayerSubsystem](UEnhancedInputLocalPlayerSubsystem.md) | LocalPlayer당 1개. 활성 IMC 목록 관리, 리매핑, 입력 주입 |
| [UEnhancedInputComponent](UEnhancedInputComponent.md) | Actor에 붙는 Action→콜백 바인딩 저장소. BindAction 3종 |
| [UEnhancedPlayerInput](UEnhancedPlayerInput.md) | 매 틱 처리 엔진 (PC→PlayerInput). IMC 평가·콜백 발화 |

---

## 파이프라인 문서 — 런타임 동작 상세

| 문서 | 내용 |
|------|------|
| [00. 클래스 구조 전체 지도](00_class_map.md) | 모든 클래스의 계층·멤버를 한 곳에 |
| [01. Subsystem vs Component](01_subsystem_component.md) | 두 클래스의 역할 분리, 처리 흐름 |
| [02. BindAction 오버로드](02_bind_action.md) | 3종 시그니처, VarTypes 고정 패턴 |
| [03. IMC 평가 파이프라인](03_imc_evaluation.md) | PrepareInputDelegatesForEvaluation 전 과정 |
| [04. Trigger 상세](04_trigger.md) | FTriggerStateTracker 결합 규칙, 상태 전환 테이블 |
| [05. Modifier 상세](05_modifier.md) | 체인 실행 원리, WASD 패턴 |
| [06. FInputActionValue](06_action_value.md) | 값 타입 시스템, 누적 동작, FInputActionInstance |

---

## 전체 흐름 요약

```
PrepareInputDelegatesForEvaluation()        ← EvaluateInputDelegates() 내부에서 호출
    EnhancedActionMappings 순회             ← IMC → ActionMappings 빌드 결과
    각 매핑 per-tick:
        KeyState 조회 (RawValue)
        EKeyEvent 결정 (None/Actuated/Held)
        ApplyModifiers(Mapping.Modifiers)   ← Mapping 레벨 Modifier
        EvaluateTriggers(Mapping.Triggers)  ← Mapping 레벨 Trigger
        값 누적 (AccumulationBehavior)
    Post-tick (ActionsWithEventsThisTick):
        ApplyModifiers(Action.Modifiers)    ← Action 레벨 Modifier
        EvaluateTriggers(Action.Triggers)   ← Action 레벨 Trigger
        GetTriggerStateChangeEvent()        ← ETriggerEvent 확정

EvaluateInputComponentDelegates()
    ActionInstanceData에서 TriggerEvent 읽음
    매칭되는 바인딩 Execute() 호출
```
