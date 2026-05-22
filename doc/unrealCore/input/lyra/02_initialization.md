# 초기화 흐름 — HeroComponent → 입력 바인딩

> 출처: `Character/LyraHeroComponent.cpp:145-302`, `Input/LyraInputComponent.h`

---

## 초기화가 일어나는 시점

입력 바인딩은 Pawn이 스폰된 직후가 아니라 **초기화 상태 머신**이 특정 단계에 도달해야 실행된다.

```
InitState_Spawned
    → InitState_DataAvailable    조건: PlayerState 있음, Controller 있음,
    │                                  Pawn->InputComponent 있음 (로컬 PC일 때)
    → InitState_DataInitialized  조건: PawnExtensionComponent가 DataInitialized 도달
    │       ★ 여기서 InitializePlayerInput() 호출
    → InitState_GameplayReady
```

`HandleChangeInitState(DataAvailable → DataInitialized)` 내부:

```cpp
// LyraHeroComponent.cpp:167
if (ALyraPlayerController* LyraPC = GetController<ALyraPlayerController>())
{
    if (Pawn->InputComponent != nullptr)
    {
        InitializePlayerInput(Pawn->InputComponent);  // ← 이 시점에 바인딩
    }
}
```

---

## InitializePlayerInput() 전체 흐름

```cpp
// LyraHeroComponent.cpp:225
void ULyraHeroComponent::InitializePlayerInput(UInputComponent* PlayerInputComponent)
```

### 1단계 — IMC 등록

```cpp
UEnhancedInputLocalPlayerSubsystem* Subsystem = LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
Subsystem->ClearAllMappings();  // 기존 매핑 초기화

for (const FInputMappingContextAndPriority& Mapping : DefaultInputMappings)
{
    Subsystem->AddMappingContext(IMC, Mapping.Priority, Options);  // IMC 등록
}
```

`DefaultInputMappings`는 `HeroComponent`의 `UPROPERTY(EditAnywhere)`로 에디터에서 설정.  
`ClearAllMappings()` 후 재등록하므로 리스폰 시에도 깔끔하게 재설정된다.

### 2단계 — Ability 입력 바인딩

```cpp
ULyraInputComponent* LyraIC = Cast<ULyraInputComponent>(PlayerInputComponent);

TArray<uint32> BindHandles;
LyraIC->BindAbilityActions(InputConfig, this,
    &ThisClass::Input_AbilityInputTagPressed,   // ETriggerEvent::Triggered
    &ThisClass::Input_AbilityInputTagReleased,  // ETriggerEvent::Completed
    BindHandles);
```

`BindAbilityActions` 내부 (`LyraInputComponent.h:52`):

```cpp
for (const FLyraInputAction& Action : InputConfig->AbilityInputActions)
{
    // 키 누름
    BindHandles.Add(BindAction(Action.InputAction, ETriggerEvent::Triggered,
        Object, PressedFunc, Action.InputTag).GetHandle());
    // 키 뗌
    BindHandles.Add(BindAction(Action.InputAction, ETriggerEvent::Completed,
        Object, ReleasedFunc, Action.InputTag).GetHandle());
}
```

`AbilityInputActions`의 모든 항목을 순회해 **InputTag를 인자로 전달**하는 바인딩을 설정.

### 3단계 — Native 입력 바인딩

```cpp
LyraIC->BindNativeAction(InputConfig, LyraGameplayTags::InputTag_Move,
    ETriggerEvent::Triggered, this, &ThisClass::Input_Move, false);
LyraIC->BindNativeAction(InputConfig, LyraGameplayTags::InputTag_Look_Mouse,
    ETriggerEvent::Triggered, this, &ThisClass::Input_LookMouse, false);
LyraIC->BindNativeAction(InputConfig, LyraGameplayTags::InputTag_Look_Stick,
    ETriggerEvent::Triggered, this, &ThisClass::Input_LookStick, false);
LyraIC->BindNativeAction(InputConfig, LyraGameplayTags::InputTag_Crouch,
    ETriggerEvent::Triggered, this, &ThisClass::Input_Crouch, false);
LyraIC->BindNativeAction(InputConfig, LyraGameplayTags::InputTag_AutoRun,
    ETriggerEvent::Triggered, this, &ThisClass::Input_AutoRun, false);
```

### 4단계 — BindInputsNow 이벤트 브로드캐스트

```cpp
bReadyToBindInputs = true;

UGameFrameworkComponentManager::SendGameFrameworkComponentExtensionEvent(
    const_cast<APlayerController*>(PC), NAME_BindInputsNow);
UGameFrameworkComponentManager::SendGameFrameworkComponentExtensionEvent(
    const_cast<APawn*>(Pawn), NAME_BindInputsNow);
```

기본 바인딩 이후 **외부 시스템(GameFeature 등)이 추가 입력을 바인딩**할 수 있도록 이벤트를 보낸다.  
`AddAdditionalInputConfig()`도 이 이후에 호출 가능.

---

## ULyraInputComponent 클래스 계층

```
UInputComponent (엔진)
    └─ UEnhancedInputComponent (엔진 Enhanced Input)
            └─ ULyraInputComponent (Lyra)
                    ├─ BindNativeAction()    ← 태그로 NativeInputActions를 찾아 바인딩
                    ├─ BindAbilityActions()  ← AbilityInputActions 전체 순회 바인딩
                    ├─ AddInputMappings()    ← 커스텀 매핑 추가 (현재 빈 구현)
                    └─ RemoveBinds()         ← 핸들 배열로 일괄 바인딩 해제
```

`LyraInputComponent`는 `EnhancedInputComponent`를 얇게 래핑해 **GameplayTag 기반 바인딩 헬퍼**를 추가한 것이다.
