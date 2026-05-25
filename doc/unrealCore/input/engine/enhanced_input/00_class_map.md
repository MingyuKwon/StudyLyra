# Enhanced Input — 클래스 구조 전체 지도

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/`

Enhanced Input을 구성하는 모든 클래스의 계층과 핵심 멤버를 한 곳에 정리한다.

---

## 클래스 계층

```
UObject
├── UDataAsset
│   ├── UInputAction                 ← "뭘 하는가" 정의 (에셋)
│   └── UInputMappingContext          ← "어떤 키가 어떤 Action인가" (에셋)
│
├── UInputModifier (abstract)         ← 값 변환기 (EditInlineNew)
│   ├── UInputModifierDeadZone
│   ├── UInputModifierNegate
│   ├── UInputModifierScalar
│   ├── UInputModifierSwizzleInputAxisValues
│   ├── UInputModifierNormalize
│   ├── UInputModifierSmoothDelta
│   ├── UInputModifierResponseCurveExponential
│   ├── UInputModifierResponseCurveUser
│   ├── UInputModifierFOVScaling
│   ├── UInputModifierToWorldSpace
│   └── UInputModifierCollection
│
└── UInputTrigger (abstract)          ← 발화 조건 (EditInlineNew)
    ├── UInputTriggerDown             ← 기본. 누르는 동안 매 틱
    ├── UInputTriggerPressed          ← 눌리는 순간 1회
    ├── UInputTriggerReleased         ← 떼는 순간 1회
    ├── UInputTriggerTimedBase (abstract)
    │   ├── UInputTriggerHold         ← N초 이상 홀드
    │   ├── UInputTriggerHoldAndRelease
    │   ├── UInputTriggerTap          ← N초 이내 탭
    │   ├── UInputTriggerRepeatedTap  ← 더블탭 등
    │   └── UInputTriggerPulse        ← 주기적 발화
    ├── UInputTriggerChordAction      ← 조합키 (Implicit)
    ├── UInputTriggerChordBlocker     ← 자동 삽입, 수동 추가 금지 (Blocker)
    └── UInputTriggerCombo            ← 순서 있는 콤보 (Implicit)

USubsystem → ULocalPlayerSubsystem
└── UEnhancedInputLocalPlayerSubsystem  ← LocalPlayer당 1개, IMC 목록 관리

UInputComponent (ActorComponent)
└── UEnhancedInputComponent             ← Actor에 붙음, Action→콜백 바인딩 저장

UPlayerInput (UObject, PC의 멤버)
└── UEnhancedPlayerInput                ← 매 틱 IMC 평가·콜백 발화 엔진
```

---

## UInputAction — 행동 정의 에셋

```cpp
class UInputAction : public UDataAsset
{
    EInputActionValueType ValueType;                  // Boolean / Axis1D / Axis2D / Axis3D
    EInputActionAccumulationBehavior AccumulationBehavior; // TakeHighestAbsoluteValue(기본) / Cumulative
    TArray<TObjectPtr<UInputTrigger>>  Triggers;      // Action 레벨 Trigger (Mapping 이후 적용)
    TArray<TObjectPtr<UInputModifier>> Modifiers;     // Action 레벨 Modifier (Mapping 이후 적용)
    bool bTriggerWhenPaused;   // 게임 일시정지 중에도 발동 여부
    bool bConsumeInput;        // true이면 하위 우선순위 Enhanced 바인딩 차단
    bool bConsumesActionAndAxisMappings; // true이면 레거시 키 매핑도 차단
    bool bReserveAllMappings;  // 상위 IMC의 자동 오버라이드 방지
};
```

**설계 의도**: 물리 키와 분리된 논리 행동 단위. IMC가 키를 연결하고, Action이 타입·조건·변환을 정의한다. UInputAction 하나에 여러 키를 매핑할 수 있고, 여러 플랫폼 프로파일을 IMC 단위로 교체할 수 있다.

---

## UInputMappingContext — 키↔액션 매핑 테이블 에셋

```cpp
class UInputMappingContext : public UDataAsset
{
protected:
    FInputMappingContextMappingData DefaultKeyMappings;
    //   └── TArray<FEnhancedActionKeyMapping> Mappings  ← 실제 매핑 목록

    TMap<FString, FInputMappingContextMappingData> MappingProfileOverrides;
    //   └── 프로파일 ID → 해당 프로파일용 매핑 (리매핑 지원)

    EMappingContextInputModeFilterOptions InputModeFilterOptions;
    //   UseProjectDefaultQuery / UseCustomQuery / DoNotFilter
    FGameplayTagQuery InputModeQueryOverride;

    EMappingContextRegistrationTrackingMode RegistrationTrackingMode;
    //   Untracked(기본): 처음 Remove 시 제거
    //   CountRegistrations: Add 횟수만큼 Remove 필요
};
```

**설계 의도**: "지금 이 상황에서 어떤 키가 어떤 Action인가"를 담는 컨텍스트 에셋. 런타임에 `AddMappingContext` / `RemoveMappingContext`로 교체하면 입력 세트가 즉시 바뀐다. 메뉴/전투/탈것처럼 상황별 입력 세트 전환에 사용한다.

---

## FEnhancedActionKeyMapping — 키 하나의 매핑 정보 (struct)

```cpp
struct FEnhancedActionKeyMapping
{
    TObjectPtr<const UInputAction> Action;   // 연결된 Action 에셋
    FKey Key;                                // 물리 키 (W, Gamepad_LeftX, ...)

    TArray<TObjectPtr<UInputTrigger>>  Triggers;  // Mapping 레벨 Trigger (Action보다 먼저 적용)
    TArray<TObjectPtr<UInputModifier>> Modifiers; // Mapping 레벨 Modifier (Action보다 먼저 적용)

    // Transient — 런타임 추적용, 에셋에 저장 안 됨
    uint8 bShouldBeIgnored : 1;         // IMC 전환 시 키가 눌려 있으면 무시
    uint8 bHasAlwaysTickTrigger : 1;    // bShouldAlwaysTick Trigger 존재 여부
};
```

IMC 에셋 안에 `TArray<FEnhancedActionKeyMapping>`으로 보관된다. 런타임에는 `UEnhancedPlayerInput::EnhancedActionMappings`에 복사되어 매 틱 순회된다.

---

## UInputModifier — 값 변환기

```cpp
class UInputModifier : public UObject
{
    // 오버라이드 포인트
    virtual FInputActionValue ModifyRaw_Implementation(
        const UEnhancedPlayerInput* PlayerInput,
        FInputActionValue CurrentValue,
        float DeltaTime);
};
```

- **EditInlineNew** — IMC나 IA 에셋에서 인라인으로 생성·편집 가능
- 배열 순서대로 체인 실행. 반환 타입은 항상 원본 ValueType으로 강제 복원
- 두 레벨: Mapping 레벨(키별) → Action 레벨(IA 에셋별) 순서

---

## UInputTrigger — 발화 조건

```cpp
class UInputTrigger : public UObject
{
    float ActuationThreshold;    // IsActuated() 판단 기준
    bool  bShouldAlwaysTick;     // true이면 키 입력 없어도 매 틱 실행 (성능 주의)
    FInputActionValue LastValue; // 이전 틱 값 (Pressed/Released 판단에 사용)

    virtual ETriggerType  GetTriggerType_Implementation() const; // Explicit(기본)/Implicit/Blocker
    virtual ETriggerState UpdateState_Implementation(...);       // 이 틱의 상태 반환
    virtual bool IsBlocking(ETriggerState State) const;         // Blocker 타입만 override
};
```

- **EditInlineNew** — IMC나 IA 에셋에서 인라인 생성
- `UInputTriggerTimedBase`는 `HeldDuration`을 누적하고, `bAffectedByTimeDilation`으로 실제시간/딜레이션 선택

---

## UEnhancedInputComponent — Action→콜백 바인딩 저장소

```cpp
class UEnhancedInputComponent : public UInputComponent
{
protected:
    // 이벤트 바인딩 (BindAction 결과)
    TArray<TUniquePtr<FEnhancedInputActionEventBinding>> EnhancedActionEventBindings;

    // 값 구독 바인딩 (BindActionValue 결과 — 콜백 없이 현재 값만 추적)
    TArray<FEnhancedInputActionValueBinding> EnhancedActionValueBindings;

    // 비배포 빌드 전용 디버그 키 바인딩
    TArray<TUniquePtr<FInputDebugKeyBinding>> DebugKeyBindings;
};
```

### FEnhancedInputActionEventBinding (non-UObject)

```cpp
struct FEnhancedInputActionEventBinding : FInputBindingHandle
{
    TWeakObjectPtr<const UInputAction> Action;  // 구독 대상 Action
    ETriggerEvent TriggerEvent;                 // 바인딩 조건 이벤트
    uint8 bConsumes : 1;                        // 하위 우선순위 바인딩 차단 여부

    virtual void Execute(const FInputActionInstance& ActionData) const = 0;
};
```

실제 구현체는 `FEnhancedInputActionEventDelegateBinding<TSignature>`. 시그니처가 다른 3종(+Dynamic)을 템플릿으로 처리하고, `Execute()`에서 각각 다른 인자를 추출해 델리게이트에 전달한다.

```cpp
// HandlerSignature: 입력 데이터 무시, 바인딩 시 고정한 VarTypes 전달
void Execute(...) { Delegate.Execute(); }

// ValueSignature: 입력값만 전달
void Execute(...) { Delegate.Execute(ActionData.GetValue()); }

// InstanceSignature: 타이밍 포함 전체 전달
void Execute(...) { Delegate.Execute(ActionData); }
```

---

## UEnhancedInputLocalPlayerSubsystem — IMC 목록 관리

LocalPlayer당 하나 존재한다. `AddMappingContext` / `RemoveMappingContext` 호출의 결과를 내부 활성 IMC 목록으로 관리한다. `UEnhancedPlayerInput`이 매 틱 이 목록을 읽어서 `EnhancedActionMappings`를 빌드한다.

```cpp
// 사용 패턴
if (UEnhancedInputLocalPlayerSubsystem* Sub = Subsystem)
{
    Sub->AddMappingContext(IMC, Priority);     // IMC 활성화
    Sub->RemoveMappingContext(IMC);             // IMC 비활성화
    Sub->ClearAllMappings();                    // 전체 초기화
}
```

---

## UEnhancedPlayerInput — 런타임 처리 엔진

```cpp
class UEnhancedPlayerInput : public UPlayerInput
{
    // IMC에서 빌드된 런타임 매핑 목록 (매 틱 순회 대상)
    TArray<FEnhancedActionKeyMapping> EnhancedActionMappings;

    // Action별 인스턴스 데이터 (값 + 타이밍 + 트리거 상태)
    mutable TMap<TObjectPtr<const UInputAction>, FInputActionInstance> ActionInstanceData;

    // 이번 틱 이벤트가 있었던 Action 집합 (Post-tick 처리 대상)
    TSet<TObjectPtr<const UInputAction>> ActionsWithEventsThisTick;

    // 이전 틱 키 상태 스냅샷 (Held 판단용)
    TMap<FKey, bool> KeyDownPrevious;

    // InjectInputForAction으로 주입된 입력
    TMap<TObjectPtr<const UInputAction>, FInjectedInputArray> InputsInjectedThisTick;
};
```

`PlayerController->PlayerInput`이 가리키는 실제 클래스. `UPlayerInput`의 `EvaluateInputDelegates` / `PrepareInputDelegatesForEvaluation`을 오버라이드해서 Enhanced Input 파이프라인을 끼워 넣는다.

---

## 전체 오브젝트 관계도

```
[에셋 레이어]
UInputAction ──────────────────────────────────────┐
  ValueType, AccumulationBehavior                   │
  Triggers[], Modifiers[]                           │
                                                    │ 참조
UInputMappingContext                                │
  DefaultKeyMappings:                               │
    FEnhancedActionKeyMapping[]                     │
      Action ──────────────────────────────────────┘
      Key (FKey)
      Triggers[] (UInputTrigger* — IMC 인라인 생성)
      Modifiers[] (UInputModifier* — IMC 인라인 생성)

[런타임 레이어]
UEnhancedInputLocalPlayerSubsystem
  ActiveIMCs (우선순위 정렬 목록)
      ↓ AddMappingContext 호출 시 등록
      ↓ 매 틱 PrepareInputDelegatesForEvaluation에서 읽음
      ↓
UEnhancedPlayerInput (PC->PlayerInput)
  EnhancedActionMappings[] ← IMC→Mapping 빌드 결과
  ActionInstanceData{}     ← Action별 FInputActionInstance
      ↓ EvaluateInputComponentDelegates
      ↓
UEnhancedInputComponent (Actor에 붙음)
  EnhancedActionEventBindings[]
    FEnhancedInputActionEventBinding
      Action, TriggerEvent → Execute(ActionInstance) → 콜백
```
