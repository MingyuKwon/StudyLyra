# Lyra 입력 시스템 전체 흐름

> 출처: `Source/LyraGame/Input/`, `Source/LyraGame/Character/LyraHeroComponent.cpp`,  
>        `Source/LyraGame/AbilitySystem/LyraAbilitySystemComponent.cpp`,  
>        `Source/LyraGame/Player/LyraPlayerController.cpp`

---

## 개요

Lyra는 언리얼의 **Enhanced Input** 시스템 위에 **GameplayTag** 기반 레이어를 얹은 구조다.  
입력을 두 가지 경로로 처리한다:

| 경로 | 대상 | 처리 주체 |
|------|------|-----------|
| **Ability 입력** | 스킬, 공격 등 GA로 연결되는 입력 | `LyraASC::ProcessAbilityInput()` (매 틱) |
| **Native 입력** | 이동, 시점, 웅크리기 등 직접 처리 | Enhanced Input 바인딩 콜백 (이벤트 시) |

---

## 전체 흐름 다이어그램

```
[데이터 설정]
ULyraPawnData
    └─ InputConfig: ULyraInputConfig    ← InputAction ↔ GameplayTag 매핑 테이블
            ├─ NativeInputActions[]     ← 이동/시점 등 직접 처리
            └─ AbilityInputActions[]    ← GA 활성화용

[초기화 — 게임 시작 시 1회]
ULyraHeroComponent::InitializePlayerInput()
    ├─ EnhancedInputSubsystem에 InputMappingContext 등록
    ├─ LyraInputComponent::BindAbilityActions()   ← AbilityInputActions 전체 바인딩
    │       ├─ ETriggerEvent::Triggered → Input_AbilityInputTagPressed(InputTag)
    │       └─ ETriggerEvent::Completed → Input_AbilityInputTagReleased(InputTag)
    └─ LyraInputComponent::BindNativeAction()     ← Native 각각 바인딩
            ├─ InputTag_Move       → Input_Move()
            ├─ InputTag_Look_Mouse → Input_LookMouse()
            ├─ InputTag_Look_Stick → Input_LookStick()
            ├─ InputTag_Crouch     → Input_Crouch()
            └─ InputTag_AutoRun    → Input_AutoRun()

[런타임 — Ability 입력 경로 (매 틱)]
키 누름 → Enhanced Input → Input_AbilityInputTagPressed(Tag)
    └─ LyraASC::AbilityInputTagPressed()
            └─ 해당 Tag를 가진 AbilitySpec → InputPressedSpecHandles / InputHeldSpecHandles에 추가

[매 틱] ALyraPlayerController::PostProcessInput()
    └─ LyraASC::ProcessAbilityInput()
            ├─ InputHeldSpecHandles   → WhileInputActive GA 활성화 시도
            ├─ InputPressedSpecHandles → OnInputTriggered GA 활성화 시도 / AbilitySpecInputPressed
            └─ InputReleasedSpecHandles → AbilitySpecInputReleased
            (처리 후 Pressed/Released 배열 초기화, Held는 유지)

[런타임 — Native 입력 경로 (이벤트 시)]
키 입력 → Enhanced Input → Input_Move() / Input_LookMouse() 등
    └─ Pawn::AddMovementInput() / AddControllerYawInput() 등 직접 호출
```

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 데이터 에셋](01_data_assets.md) | LyraInputConfig 구조, NativeInputActions vs AbilityInputActions |
| [02. 초기화 흐름](02_initialization.md) | HeroComponent 초기화 단계, IMC 등록, 바인딩 시점 |
| [03. Ability 입력 경로](03_ability_input.md) | Tag Pressed/Released → ASC → ProcessAbilityInput 상세 |
| [04. Native 입력 경로](04_native_input.md) | 이동/시점/웅크리기 콜백 구현 |
