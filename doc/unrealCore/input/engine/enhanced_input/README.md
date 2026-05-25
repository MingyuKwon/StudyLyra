# Enhanced Input 엔진 구현

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/`

Enhanced Input이 어떻게 동작하는지를 클래스 역할, 파이프라인, 내부 자료구조 수준에서 다룬다.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [00. 클래스 구조 전체 지도](00_class_map.md) | UInputAction/IMC/FEnhancedActionKeyMapping/Component/PlayerInput 멤버 전체 |
| [01. Subsystem vs Component](01_subsystem_component.md) | 두 클래스의 역할 분리, 처리 흐름, Lyra에서의 사용 |
| [02. BindAction 오버로드](02_bind_action.md) | 3종 시그니처, VarTypes 고정 패턴, UFUNCTION 동적 바인딩 |
| [03. IMC 평가 파이프라인](03_imc_evaluation.md) | PrepareInputDelegatesForEvaluation 내부 — 키→Action 변환 전 과정 |
| [04. Trigger](04_trigger.md) | ETriggerState/Event/Type, FTriggerStateTracker, 내장 Trigger 목록 |
| [05. Modifier](05_modifier.md) | Modifier 체인, 두 레벨(Mapping/Action), 내장 Modifier |
| [06. FInputActionValue](06_action_value.md) | 값 타입 시스템, 누적 동작, FInputActionInstance 타이밍 |

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
