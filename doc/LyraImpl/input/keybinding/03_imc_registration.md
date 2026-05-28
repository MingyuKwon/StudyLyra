# 03. IMC 등록 — 어떤 키가 리맵 가능한가

> 출처: `Source/LyraGame/Character/LyraHeroComponent.cpp` (`InitializePlayerInput`),  
>        엔진 `UserSettings/EnhancedInputUserSettings.h` (`RegisterInputMappingContext`)

---

## 핵심 질문

> "IMC(InputMappingContext)의 어떤 키가 설정 화면에 나타나고, 어떻게 등록되는가?"

---

## 등록 진입점: `InitializePlayerInput()`

캐릭터가 스폰되고 `DataInitialized` 상태에 도달하면 `LyraHeroComponent`가 `InitializePlayerInput()`을 호출한다.  
이 함수가 IMC를 두 곳에 등록한다: **EnhancedInput 서브시스템(게임 입력)** 과 **UserSettings(리맵핑)**.

```cpp
// LyraHeroComponent.cpp
void ULyraHeroComponent::InitializePlayerInput(UInputComponent* PlayerInputComponent)
{
    // ...
    UEnhancedInputLocalPlayerSubsystem* Subsystem =
        LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();

    Subsystem->ClearAllMappings();  // 기존 매핑 전부 제거

    for (const FInputMappingContextAndPriority& Mapping : DefaultInputMappings)
    {
        if (UInputMappingContext* IMC = Mapping.InputMapping.LoadSynchronous())
        {
            if (Mapping.bRegisterWithSettings)  // ← 이 플래그가 핵심
            {
                // [1] UserSettings에 등록 — 리맵 가능한 키 목록으로 노출
                if (UEnhancedInputUserSettings* Settings = Subsystem->GetUserSettings())
                {
                    Settings->RegisterInputMappingContext(IMC);
                }

                // [2] EnhancedInput에 등록 — 실제 게임 입력에 적용
                FModifyContextOptions Options = {};
                Options.bIgnoreAllPressedKeysUntilRelease = false;
                Subsystem->AddMappingContext(IMC, Mapping.Priority, Options);
            }
        }
    }
    // ...
}
```

**`bRegisterWithSettings`의 의미**:

| 값 | 결과 |
|----|------|
| `true` | 게임 입력에도 등록되고, 설정 화면에서 리맵도 가능 |
| `false` | 게임 입력에만 등록. 설정 화면에 나타나지 않음 |

예를 들어 "시스템 전용 단축키"처럼 사용자가 바꾸면 안 되는 IMC는 `false`로 설정한다.

---

## `RegisterInputMappingContext()` 내부 동작 (엔진)

```
Settings->RegisterInputMappingContext(IMC)
    └─ IMC 내 모든 FEnhancedActionKeyMapping 순회
            ├─ PlayerMappableKeySettings가 null → 건너뜀 (리맵 불가)
            └─ PlayerMappableKeySettings가 있음 → 리맵 가능 키로 등록
                    └─ 현재 활성 프로필에 FPlayerKeyMapping 추가
                            ├─ DefaultKey = IMC에 설정된 원래 키
                            └─ CurrentKey = 저장된 값이 있으면 복원, 없으면 DefaultKey와 동일
```

즉, **IMC에 `UPlayerMappableKeySettings`(또는 서브클래스)가 지정된 키만** 설정 화면에 나타난다.

---

## `FInputMappingContextAndPriority` 구조체

`DefaultInputMappings`는 `ULyraHeroComponent`의 멤버다.  
에디터에서 블루프린트를 통해 설정하거나, 코드로 직접 추가할 수 있다.

```cpp
// LyraHeroComponent.h (추정 구조)
struct FInputMappingContextAndPriority
{
    TSoftObjectPtr<UInputMappingContext> InputMapping;  // IMC 에셋 레퍼런스
    int32 Priority = 0;                                // 입력 우선순위
    bool bRegisterWithSettings = true;                 // 설정 화면 노출 여부
};

UPROPERTY(EditDefaultsOnly, Category = Input)
TArray<FInputMappingContextAndPriority> DefaultInputMappings;
```

---

## IMC 에셋에서 리맵 가능 키 설정하는 방법

에디터에서 IMC 에셋을 열었을 때의 설정 경로:

```
[IMC 에셋]
├─ Mappings
│   ├─ [0] Action: IA_Jump, Key: SpaceBar
│   │       ├─ Triggers: []
│   │       ├─ Modifiers: []
│   │       └─ Player Mappable Key Settings
│   │               ├─ Class: LyraPlayerMappableKeySettings  ← 이걸 지정
│   │               ├─ Display Name: "점프"
│   │               ├─ Display Category: "이동"
│   │               └─ (Tooltip은 클래스 에셋 디테일에서 설정)
│   │
│   ├─ [1] Action: IA_Move, Key: W
│   │       └─ Player Mappable Key Settings: (없음)  ← 설정 화면에 안 나옴
│   │
│   └─ [2] Action: IA_Interact, Key: E
│           └─ Player Mappable Key Settings: LyraPlayerMappableKeySettings
│                   ├─ Display Name: "상호작용"
│                   └─ Display Category: "액션"
```

위 예시에서 설정 화면에 나타나는 키는 `IA_Jump`(SpaceBar)와 `IA_Interact`(E)뿐이다.  
`IA_Move`는 `PlayerMappableKeySettings`가 없어서 나타나지 않는다.

---

## `ClearAllMappings()` 주의사항

`InitializePlayerInput()`의 첫 줄에서 `Subsystem->ClearAllMappings()`를 호출한다.  
이는 이전 IMC를 전부 제거하는 것이다. 캐릭터가 죽고 다시 스폰될 때마다 새로 등록한다.

**UserSettings에 저장된 키 변경값은 지워지지 않는다.**  
`RegisterInputMappingContext()`가 다시 호출되면 저장된 `CurrentKey`가 자동으로 복원된다.

---

## 추가 IMC 등록 — `AddAdditionalInputConfig()`

기본 IMC 외에 런타임 중 추가 InputConfig를 바인딩할 수 있다.

```cpp
// LyraHeroComponent.cpp
void ULyraHeroComponent::AddAdditionalInputConfig(const ULyraInputConfig* InputConfig)
{
    // 이 함수는 새 IMC를 등록하지는 않고
    // 추가 AbilityInputActions를 기존 LyraInputComponent에 바인딩하는 용도
    ULyraInputComponent* LyraIC = Pawn->FindComponentByClass<ULyraInputComponent>();
    LyraIC->BindAbilityActions(InputConfig, this,
        &ThisClass::Input_AbilityInputTagPressed,
        &ThisClass::Input_AbilityInputTagReleased,
        BindHandles);
}
```

장비 장착 시 추가 능력 입력을 등록할 때 사용한다.  
`RemoveAdditionalInputConfig()`는 현재 `@TODO: Implement me!` 상태.

---

## 등록 시점 다이어그램

```
[캐릭터 스폰]
    └─ ULyraPawnExtensionComponent → InitState: DataInitialized

[ULyraHeroComponent]
    ├─ DataAvailable → DataInitialized 전환 시
    │       └─ InitializePlayerInput() 호출
    │               ├─ ClearAllMappings()
    │               ├─ RegisterInputMappingContext(IMC_A)  → 설정 화면 노출
    │               ├─ AddMappingContext(IMC_A, Priority)  → 게임 입력 등록
    │               ├─ BindAbilityActions(...)              → GA 입력 연결
    │               └─ BindNativeAction(...)                → 이동/시점 연결
    │
    └─ DataInitialized → GameplayReady 전환 시
            └─ (추가 작업 없음. 입력은 이미 완료)
```
