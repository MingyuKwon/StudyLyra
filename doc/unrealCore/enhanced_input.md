# Enhanced Input — Subsystem vs Component

> 소스: `Source/LyraGame/Character/LyraHeroComponent.cpp`

Enhanced Input은 역할이 다른 두 클래스로 분리되어 있다.

---

## 역할 분리

| | UEnhancedInputLocalPlayerSubsystem | UEnhancedInputComponent |
|---|---|---|
| **부착 대상** | LocalPlayer (플레이어당 하나) | Actor (Pawn, PC 등) |
| **역할** | 활성 IMC 관리, 키 → Action 변환 | Action → 콜백 바인딩 |

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

---

## 내 노트

`AddMappingContext`를 Subsystem에 하는 이유: IMC는 로컬 플레이어 단위로 관리되기 때문.
같은 머신에 플레이어가 2명(스플릿스크린)이면 각자 다른 IMC 세트를 가질 수 있다.
