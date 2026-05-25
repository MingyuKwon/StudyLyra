# UEnhancedInputLocalPlayerSubsystem

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedInputSubsystems.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedInputSubsystemInterface.h`

---

## 무엇인가

**LocalPlayer당 하나 존재하는 서브시스템**이다. 이 플레이어가 현재 어떤 IMC를 활성화하고 있는지를 관리한다.

핵심 역할 하나: **"지금 이 플레이어에게 어떤 IMC가 활성화되어 있는가"를 기록하고, `UEnhancedPlayerInput`이 매 틱 그 목록을 읽어 키→Action 변환에 사용한다.**

---

## 클래스 위치

```
USubsystem → ULocalPlayerSubsystem → UEnhancedInputLocalPlayerSubsystem
                                      + IEnhancedInputSubsystemInterface (실제 API 대부분)
```

`ULocalPlayerSubsystem`이므로 `LocalPlayer`가 생성될 때 자동 생성, 제거될 때 자동 제거된다.

---

## 접근 방법

```cpp
// C++
ULocalPlayer* LP = PC->GetLocalPlayer();
UEnhancedInputLocalPlayerSubsystem* Subsystem =
    ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(LP);

// 또는 간단하게
auto* Subsystem = PC->GetLocalPlayer()->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
```

---

## 핵심 API

### IMC 관리

```cpp
// IMC 활성화
void AddMappingContext(
    const UInputMappingContext* MappingContext,
    int32 Priority,
    const FModifyContextOptions& Options = FModifyContextOptions());

// IMC 비활성화
void RemoveMappingContext(
    const UInputMappingContext* MappingContext,
    const FModifyContextOptions& Options = FModifyContextOptions());

// 전체 초기화
void ClearAllMappings();
```

**Priority**: 값이 높을수록 먼저 처리. 같은 키가 여러 IMC에 겹칠 때 높은 Priority의 IMC가 우선한다.

**FModifyContextOptions**:
```cpp
struct FModifyContextOptions
{
    bool bIgnoreAllPressedKeysUntilRelease = true;
    // true: IMC 추가 시점에 눌려 있던 키는 떼고 다시 눌러야 인식
    // false: 이미 눌린 키도 즉시 인식

    bool bForceImmediately = false;
    // true: 이번 틱에 즉시 반영
    // false: 다음 틱에 반영 (기본)
};
```

### 키 리매핑

```cpp
// 특정 키를 다른 키로 교체 (플레이어 커스텀 키 설정)
void AddPlayerMappedKeyInSlot(const FName MappingName, FKey NewKey);
void RemovePlayerMappedKeyInSlot(const FName MappingName);
```

### 입력 주입

```cpp
// 코드에서 직접 Action 값을 주입 (AI, 튜토리얼, 테스트용)
void InjectInputForAction(
    const UInputAction* Action,
    FInputActionValue RawValue,
    const TArray<UInputModifier*>& Modifiers,
    const TArray<UInputTrigger*>& Triggers);
```

### 입력 모드 (Input Mode)

```cpp
// 현재 입력 모드 GameplayTag 컨테이너 설정
// IMC의 InputModeFilterOptions와 연동
void SetInputModeTag(const FGameplayTag& InputModeTag);
FGameplayTagContainer GetCurrentInputMode() const;
```

### 유저 세팅

```cpp
// 플레이어별 키 세팅 (저장/불러오기 가능)
UEnhancedInputUserSettings* GetUserSettings() const;
```

---

## 주요 델리게이트

```cpp
FOnControlMappingsRebuilt ControlMappingsRebuiltDelegate;
// 컨트롤 매핑이 재빌드된 프레임 끝에 호출

FOnMappingContextAdded OnMappingContextAdded;
// AddMappingContext 호출 직후 발생 (매핑 재빌드 보장 안 함)

FOnMappingContextRemoved OnMappingContextRemoved;
// RemoveMappingContext 호출 직후 발생
```

매핑 재빌드가 실제로 완료된 후에 처리해야 한다면 `ControlMappingsRebuiltDelegate`를 사용한다.

---

## UEnhancedPlayerInput과의 관계

```
UEnhancedInputLocalPlayerSubsystem
    ActiveIMCs[]  ← AddMappingContext 결과물
         ↓ 매 틱 PrepareInputDelegatesForEvaluation에서 읽음
UEnhancedPlayerInput
    EnhancedActionMappings[] ← IMC → Mapping 빌드 결과
```

Subsystem은 "어떤 IMC가 활성인가"만 기록한다. 실제 키→Action 변환과 Modifier/Trigger 평가는 `UEnhancedPlayerInput`이 매 틱 수행한다.

---

## UEnhancedInputWorldSubsystem — 비교

PlayerController가 없는 Actor(문, 함정 등)에 입력을 연결할 때 사용하는 World 레벨 서브시스템이다. `FEnhancedInputWorldProcessor`(IInputProcessor)가 Slate에서 이벤트를 받아 전달한다. LocalPlayer와는 완전히 분리된 경로다.

---

## Lyra에서의 사용

```cpp
// LyraHeroComponent.cpp — InitializePlayerInput()
UEnhancedInputLocalPlayerSubsystem* Subsystem =
    ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(LocalPlayer);

for (const FInputMappingContextAndPriority& Mapping : InputConfig->DefaultInputMappings)
{
    Subsystem->AddMappingContext(Mapping.InputMappingContext, Mapping.Priority, Options);
}
```

---

## 요약

```
UEnhancedInputLocalPlayerSubsystem
  = LocalPlayer당 1개, 활성 IMC 목록 관리자

핵심 API:
  AddMappingContext(IMC, Priority)    ← 상황 전환
  RemoveMappingContext(IMC)
  InjectInputForAction(...)          ← AI/테스트용 입력 주입
  GetUserSettings()                  ← 플레이어별 키 커스텀

UEnhancedPlayerInput이 이 목록을 매 틱 소비해서 키→Action 변환 수행.
```
