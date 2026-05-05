# 입력 시스템 (Lyra)

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 12. 언리얼 입력 파이프라인 & ProcessAbilityInput 호출 경로

**출처 (Lyra)**: `Player/LyraPlayerController.cpp:376-384`, `AbilitySystem/LyraAbilitySystemComponent.cpp:216`  
**출처 (엔진 UE 5.7)**: `Engine/Source/Runtime/Engine/Private/PlayerController.cpp`, `Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`  
**상세 문서**: `unrealCore/input_pipeline.md`

### 전체 호출 체인

```
APlayerController::PlayerTick()                    ← PC.cpp:2309, 매 틱 무조건 (로컬 PC만)
    └─ TickPlayerInput()                           ← PC.cpp:5320
        ├─ PlayerInput->Tick()                     ← 제스처 인식 등
        └─ ProcessPlayerInput()                    ← PC.cpp:2768
            ├─ BuildInputStack()                   ← InputComponent 우선순위 스택 구성
            └─ PlayerInput->ProcessInputStack()    ← PlayerInput.cpp:1239
                ├─ PreProcessInput()               ← virtual 훅
                ├─ EvaluateKeyMapState()           ← Accumulator → EventCounts flush
                ├─ EvaluateInputDelegates()        ← 바인딩 델리게이트 실행
                ├─ PostProcessInput()              ← virtual 훅 ★ Lyra가 오버라이드
                │       └─ LyraASC->ProcessAbilityInput()
                └─ FinishProcessingPlayerInput()
```

### Accumulator 패턴 (두 단계 분리)

- **1단계 — 비동기 수집**: OS 키 이벤트 → `UPlayerInput::InputKey()` → `EventAccumulator`에 누적 (PlayerInput.cpp:278)
- **2단계 — 매 틱 flush**: `EvaluateKeyMapState()`가 `EventAccumulator` → `EventCounts`로 이동 후 Accumulator 초기화 (PlayerInput.cpp:1281)
- 입력이 없는 틱에도 flush 함수는 실행된다 (빈 Accumulator를 처리).

### bDown 홀드 상태 유지 원리

```cpp
// PlayerInput.cpp — ProcessNonAxesKeys 내부
if (KeyState->EventCounts[IE_Pressed].Num() > 0)
    KeyState->bDown = true;
else
    KeyState->bDown = KeyState->bDownPrevious;  // 이전 프레임 상태 복사
```
이 덕분에 `WhileInputActive` 정책이 키 홀드를 매 틱 감지할 수 있다.

### BuildInputStack 우선순위 (낮음 → 높음)
1. Pawn->InputComponent
2. Pawn에 붙은 다른 UInputComponent
3. LevelScriptActor->InputComponent
4. PlayerController->InputComponent
5. PushInputComponent()로 수동 추가된 것 (최우선)

### PostProcessInput이 매 틱 불리는 이유
`ProcessInputStack()`이 매 틱 `ProcessPlayerInput()`에서 무조건 호출되기 때문.
입력 이벤트 유무와 무관하다.

---

## 13. Lyra 입력 시스템 전체 구조

**출처**: `Input/LyraInputConfig.h`, `Input/LyraInputComponent.h/.cpp`, `Character/LyraHeroComponent.cpp`, `AbilitySystem/LyraAbilitySystemComponent.cpp:186-318`  
**상세 문서**: `doc/LyraImpl/input/`

### 핵심 클래스

- `ULyraInputConfig` — DataAsset. `NativeInputActions[]`(이동/시점)와 `AbilityInputActions[]`(GA용) 두 목록을 가짐. InputAction ↔ GameplayTag 매핑.
- `ULyraInputComponent` — `UEnhancedInputComponent` 서브클래스. `BindNativeAction()`, `BindAbilityActions()` 헬퍼 추가.
- `ULyraHeroComponent` — `InitState_DataInitialized` 도달 시 `InitializePlayerInput()` 호출. IMC 등록 + 바인딩 설정.

### 입력 경로 두 가지

**Ability 경로** (GA 활성화):
1. 키 누름 → Enhanced Input → `Input_AbilityInputTagPressed(Tag)` → `ASC::AbilityInputTagPressed()`
2. `AbilityInputTagPressed`: ActivatableAbilities 순회, `HasTagExact(InputTag)`로 Spec 찾아 `InputPressedSpecHandles` + `InputHeldSpecHandles`에 추가
3. 매 틱 `PostProcessInput()` → `ProcessAbilityInput()`: Held(WhileInputActive) + Pressed(OnInputTriggered) 처리 → `TryActivateAbility()`
4. 키 뗌 → `AbilityInputTagReleased()` → `InputReleasedSpecHandles`에 추가, `InputHeldSpecHandles`에서 제거
5. Pressed/Released는 ProcessAbilityInput 끝에 초기화. Held는 키 뗄 때까지 유지.

**Native 경로** (이동/시점):
- Enhanced Input 이벤트 즉시 콜백 호출. `Input_Move()`, `Input_LookMouse()`, `Input_LookStick()`, `Input_Crouch()`, `Input_AutoRun()`
- 마우스: 델타 그대로 전달. 스틱: `* Rate * DeltaSeconds`로 프레임 독립적 처리.

---

## Enhanced Input — Subsystem vs Component 역할 분리

> 출처: `Source/LyraGame/Character/LyraHeroComponent.cpp`  
> 상세 문서: `doc/unrealCore/enhanced_input.md`

- **UEnhancedInputLocalPlayerSubsystem**: LocalPlayer당 하나. 활성 IMC 목록 관리. 키 → InputAction 변환 담당.
- **UEnhancedInputComponent**: Actor에 붙는 컴포넌트. InputAction → 콜백 함수 바인딩 담당.

```
키 입력 → Subsystem(IMC로 Action 결정) → Component(Action에 바인딩된 함수 실행)
```

AddMappingContext는 Subsystem에, BindNativeAction은 Component에 — 둘 다 InitializePlayerInput에서 호출되지만 역할이 다르다.
IMC가 LocalPlayer 단위인 이유: 스플릿스크린에서 플레이어마다 다른 컨텍스트 세트를 가질 수 있기 때문.

BindAction 오버로드 구조:
- `HandlerSignature`: void Func() — VarTypes로 추가 인자 고정 (FGameplayTag 패턴)
- `ValueSignature`: void Func(FInputActionValue&) — 입력값 전달
- `InstanceSignature`: void Func(FInputActionInstance&) — 값 + 타이밍(ElapsedTime 등) 전달
- UFUNCTION 버전: FName 문자열로 런타임 바인딩 (Blueprint용)
함수 파라미터 타입으로 컴파일러가 오버로드 자동 선택. VarTypes는 델리게이트 생성 시 고정되어 Execute 시 입력값 대신 전달.

---

### AbilitySpecInputPressed / AbilitySpecInputReleased

> 출처: `LyraAbilitySystemComponent.cpp:150`, 엔진 `AbilitySystemComponent_Abilities.cpp:2879`  
> 상세 문서: `doc/LyraImpl/input/README.md`

**GA가 이미 활성 중일 때만** 호출된다. GA 발동(TryActivateAbility)과 다른 경로.

- 엔진 Super: `Spec.InputPressed` 플래그 세팅 + `GA->InputPressed/Released()` 호출
- Lyra 오버라이드: `InvokeReplicatedEvent(InputPressed/Released)` 추가
  - `bReplicateInputDirectly` 미사용, 대신 ReplicatedEvent로 WaitInputPress/Release Task에 전달

ProcessAbilityInput에서의 분기:
- GA 비활성 + OnInputTriggered → TryActivateAbility()
- GA 활성 중 → AbilitySpecInputPressed() → WaitInputPress Task 깨움

### AbilityInputBlocked
`TAG_Gameplay_AbilityInputBlocked` 태그가 ASC에 있으면 `ProcessAbilityInput` 진입 시 전체 무시 + `ClearAbilityInput()`.

### 복제
`AbilitySpecInputPressed/Released`에서 `bReplicateInputDirectly` 미사용. `InvokeReplicatedEvent`로 처리 → `WaitInputPress/Release` AbilityTask와 호환.
