# Lyra 입력 시스템 전체 흐름

> 출처: `Source/LyraGame/Input/`, `Source/LyraGame/Character/LyraHeroComponent.cpp`,  
>        `Source/LyraGame/AbilitySystem/LyraAbilitySystemComponent.cpp`,  
>        `Source/LyraGame/Player/LyraPlayerController.cpp`

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 데이터 에셋](01_data_assets.md) | LyraInputConfig 구조, NativeInputActions vs AbilityInputActions |
| [02. 초기화 흐름](02_initialization.md) | HeroComponent 초기화 단계, IMC 등록, 바인딩 시점 |
| [03. Ability 입력 경로](03_ability_input.md) | Tag Pressed/Released → ASC → ProcessAbilityInput 상세 |
| [04. Native 입력 경로](04_native_input.md) | 이동/시점/웅크리기 콜백 구현 |
| [05. 설정 시스템 아키텍처](05_settings_architecture.md) | SettingsLocal vs SettingsShared vs InputUserSettings, GameSettingRegistry 구조 |
| [06. 게임패드 설정 UI](06_gamepad_settings.md) | 게임패드 탭 항목 구성, InputModifier 3종 연동, 플랫폼 Trait Tag |
| [07. 키 바인딩 변경](keybinding/README.md) | 런타임 리맵핑 전체 흐름 (아키텍처/데이터/IMC등록/레지스트리/UI/적용저장 6개 문서) |
| [08. CommonUI 입력 레이어](08_commonui_input.md) | 입력 모드 스택, 게임패드 포커스, 버튼 아이콘 자동 갱신, 컨트롤러 연결 끊김 |

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

## AbilitySpecInputPressed / AbilitySpecInputReleased 상세

### 핵심 전제 — 이미 활성 중인 GA에만 호출된다

`ProcessAbilityInput`에서 `InputPressedSpecHandles`를 처리할 때 두 경로가 갈린다.

```
InputPressedSpecHandles 처리
    ├─ GA 비활성 + OnInputTriggered → TryActivateAbility()       [GA 발동]
    └─ GA 이미 활성 중             → AbilitySpecInputPressed()   [입력 전달]
```

GA가 비활성이면 `AbilitySpecInputPressed`는 호출되지 않는다.

### 엔진 Super 처리

```cpp
// AbilitySystemComponent_Abilities.cpp
void AbilitySpecInputPressed(FGameplayAbilitySpec& Spec)
{
    Spec.InputPressed = true;
    for (UGameplayAbility* Instance : Spec.GetAbilityInstances())
        Instance->InputPressed(...);   // GA의 가상함수 or BP 이벤트 호출
}
```

### Lyra 오버라이드 추가 동작

```cpp
// LyraAbilitySystemComponent.cpp
void AbilitySpecInputPressed(FGameplayAbilitySpec& Spec)
{
    Super::AbilitySpecInputPressed(Spec);
    if (Spec.IsActive())
        InvokeReplicatedEvent(EAbilityGenericReplicatedEvent::InputPressed, ...);
}
```

엔진 기본값인 `bReplicateInputDirectly`를 쓰지 않고 `InvokeReplicatedEvent`로 대체한다.
`WaitInputPress` / `WaitInputRelease` AbilityTask가 이 이벤트를 수신해서 동작한다.

### 전체 흐름

```
키 누름 → Input_AbilityInputTagPressed(Tag)
  → InputPressedSpecHandles에 추가

매 틱 ProcessAbilityInput
  ├─ GA 비활성 → TryActivateAbility() [발동]
  └─ GA 활성 중 → AbilitySpecInputPressed()
        ├─ Super: Spec.InputPressed=true, GA->InputPressed() 호출
        └─ Lyra:  InvokeReplicatedEvent(InputPressed)
                    → WaitInputPress Task 깨어남

키 뗌 → Input_AbilityInputTagReleased(Tag)
  → InputReleasedSpecHandles에 추가

매 틱 ProcessAbilityInput
  └─ GA 활성 중 → AbilitySpecInputReleased()
        ├─ Super: Spec.InputPressed=false, GA->InputReleased() 호출
        └─ Lyra:  InvokeReplicatedEvent(InputReleased)
                    → WaitInputRelease Task 깨어남
```

> **용도**: 이미 실행 중인 GA 안에서 `WaitInputPress` / `WaitInputRelease` AbilityTask로  
> 입력 이벤트를 기다릴 때 사용한다. 차징, 홀드 스킬 등이 대표적인 사례다.
