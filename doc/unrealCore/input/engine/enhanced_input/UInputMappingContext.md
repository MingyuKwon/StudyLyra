# UInputMappingContext

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputMappingContext.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/EnhancedActionKeyMapping.h`

---

## 무엇인가

**"어떤 키가 어떤 Action인가"를 정의하는 에셋**이다. 특정 상황(전투, 메뉴, 탈것 등)에서 어떤 키 세트를 쓸지 담는 컨텍스트 묶음이다.

런타임에 `AddMappingContext` / `RemoveMappingContext`로 교체하면 입력 세트가 즉시 바뀐다.

---

## 클래스 위치

```
UObject → UDataAsset → UInputMappingContext
```

에디터에서 우클릭 → Input → Input Mapping Context로 생성.

---

## 핵심 구조

```cpp
class UInputMappingContext : public UDataAsset
{
    FInputMappingContextMappingData DefaultKeyMappings;
    //   └── TArray<FEnhancedActionKeyMapping> Mappings  ← 실제 매핑 배열

    TMap<FString, FInputMappingContextMappingData> MappingProfileOverrides;
    //   └── 프로파일 ID → 해당 프로파일용 매핑 (리매핑 지원)
};
```

### MappingProfileOverrides — 플레이어 키 커스터마이징

```cpp
TMap<FString, FInputMappingContextMappingData> MappingProfileOverrides;
//   프로파일 ID            └── TArray<FEnhancedActionKeyMapping>
```

플레이어가 키 설정 화면에서 키를 바꿨을 때 저장되는 데이터다. `DefaultKeyMappings`의 Action은 그대로 두고, 어떤 물리 키가 그 Action을 발동하는지만 프로파일별로 다르게 저장한다.

```
DefaultKeyMappings:
  IA_Jump → SpaceBar
  IA_Move → WASD

MappingProfileOverrides["Player_1"]:
  IA_Jump → LeftCtrl     ← Player_1이 SpaceBar를 LeftCtrl로 바꾼 것
  IA_Move → 화살표키
```

런타임에 특정 프로파일 ID를 활성화하면 `DefaultKeyMappings` 대신 해당 프로파일의 매핑이 사용된다. Action 목록과 Trigger/Modifier는 변하지 않는다. 달라지는 것은 `FEnhancedActionKeyMapping.Key` 필드뿐이다.

**IMC 교체와의 차이**:

| | 무엇을 바꾸는가 | 언제 쓰는가 |
|---|---|---|
| `MappingProfileOverrides` | 어떤 키가 Action을 발동하는가 | 플레이어 키 커스터마이징 |
| IMC 교체 | 어떤 Action들이 활성화되는가 | 게임플레이 상황 전환 |

`MappingProfileOverrides`로는 Action 자체를 교체할 수 없다. 도보 Action을 탈것 Action으로 바꾸는 것은 반드시 IMC 교체로 해야 한다.

---

## FEnhancedActionKeyMapping — 키 하나의 매핑 정보

IMC 내부의 핵심 단위. "W키 → IA_Move, Negate Modifier 없음" 처럼 키 하나와 Action의 연결을 담는다.

```cpp
struct FEnhancedActionKeyMapping
{
    // 연결 정보
    TObjectPtr<const UInputAction> Action;  // 어떤 Action에 연결되는가
    FKey Key;                               // 어떤 물리 키인가

    // Mapping 레벨 수정자 (Action 레벨보다 먼저 적용됨)
    TArray<TObjectPtr<UInputTrigger>>  Triggers;   // 이 키 매핑의 발화 조건
    TArray<TObjectPtr<UInputModifier>> Modifiers;  // 이 키 매핑의 값 변환

    // Transient — 런타임 추적용
    uint8 bShouldBeIgnored : 1;       // IMC 재빌드 중 키가 눌려 있으면 무시
    uint8 bHasAlwaysTickTrigger : 1;  // AlwaysTick Trigger 존재 여부 (성능 최적화 플래그)
};
```

### SettingBehavior — 키 리매핑 화면 메타데이터 처리 방식

키 리매핑 UI(게임 내 "키 설정" 화면)에서 이 매핑을 어떻게 표시할지를 결정한다.

```cpp
EPlayerMappableKeySettingBehaviors SettingBehavior = InheritSettingsFromAction;
TObjectPtr<UPlayerMappableKeySettings> UserSettings;  // OverrideSettings일 때 사용
```

| 값 | 동작 |
|---|---|
| `InheritSettingsFromAction` (기본) | IA 에셋에 붙은 `UPlayerMappableKeySettings`를 그대로 상속 |
| `OverrideSettings` | `UserSettings`에 지정한 별도 설정으로 재정의. 같은 IA라도 키마다 다른 이름·카테고리 부여 가능 |
| `IgnoreSettings` | 이 키 매핑을 리매핑 UI에서 숨김. 내부 키, 디버그 키 등에 사용 |

`UPlayerMappableKeySettings`가 담는 정보:

```cpp
class UPlayerMappableKeySettings : public UObject
{
    FName    Name;             // 리매핑 저장 시 사용하는 식별자 (고유해야 함)
    FText    DisplayName;      // UI에 표시되는 이름 (예: "이동 — 앞으로")
    FText    DisplayCategory;  // UI 카테고리 (예: "이동", "전투", "메뉴")
    UObject* Metadata;         // 추가 커스텀 데이터 (아이콘 등)
    TArray<FString> SupportedKeyProfileIds;  // 이 설정이 적용되는 프로파일 목록
};
```

**언제 사용하는가**: 기본 `InheritSettingsFromAction`만으로도 IA 에셋 단위 리매핑은 구현된다. 같은 IA를 여러 기기에 매핑하고 기기별로 UI 이름을 다르게 표시하거나, 특정 매핑을 UI에서 숨기고 싶을 때 `OverrideSettings`/`IgnoreSettings`를 쓴다.

---

### 런타임 처리 흐름 — EnhancedActionMappings와 FInputActionInstance

`AddMappingContext` 호출 시, IMC 안의 모든 `FEnhancedActionKeyMapping`이 `UEnhancedPlayerInput.EnhancedActionMappings` 배열에 추가된다. 여러 IMC가 활성화되면 각 IMC의 항목이 **전부 별도 항목으로** 이 배열에 들어간다.

```
활성 IMC:
  IMC_Combat (P10):  IA_Attack → LeftClick, Modifier: Scalar(2.0), Trigger: Hold
  IMC_Default (P0):  IA_Attack → LeftClick, Modifier: 없음,        Trigger: 없음

EnhancedActionMappings (빌드 결과):
  [0] IMC_Combat:  Action=IA_Attack, Key=LeftClick, Modifiers=[Scalar(2.0)], Triggers=[Hold]
  [1] IMC_Default: Action=IA_Attack, Key=LeftClick, Modifiers=[],            Triggers=[]
```

매 틱 이 배열을 순회하며 각 항목을 **독립적으로** 처리한다. 항목마다 자신의 Modifier와 Trigger가 실행된다. 처리 결과는 같은 Action의 `FInputActionInstance` 하나에 누적된다.

```
[0] 처리: Scalar(2.0) 적용 → Hold 진행 중 → Ongoing, Value=2.0
[1] 처리: 변환 없음        → 즉시 발동    → Triggered, Value=1.0
         ↓ AccumulationBehavior + FTriggerStateTracker
FInputActionInstance(IA_Attack):
  Value: TakeHighestAbsoluteValue → 2.0
  TriggerEvent: 가장 강한 상태 → Triggered
```

단, `IA_Attack.bConsumeInput = true`(기본)이면 IMC_Combat(P10)이 키를 소비해 IMC_Default(P0)의 항목은 스킵된다. 이 경우 IMC_Combat의 Modifier/Trigger만 실행된다.

**핵심**: `UInputAction` 에셋은 상태가 없는 설계도이고, `FEnhancedActionKeyMapping`은 키별 처리 설정을 담는 처리 단위이며, `FInputActionInstance`는 모든 처리가 끝난 후의 최종 결과를 담는 런타임 저장소다.

---

### Modifier / Trigger의 두 레벨

같은 Action에 키별로 다른 동작을 줘야 할 때 Mapping 레벨 Modifier/Trigger를 쓴다.

```
W키 Mapping:
    Modifier: SwizzleAxis(YXZ)    ← W는 Y축 전진으로 변환
    Trigger:  없음

S키 Mapping:
    Modifier: Negate              ← S는 값을 뒤집어서 후진
             SwizzleAxis(YXZ)
    Trigger:  없음

IA_Move(Action 레벨):
    Modifier: 없음               ← 공통 변환 없음
    Trigger:  없음
```

---

## 기타 프로퍼티

### InputModeFilterOptions — 입력 모드 필터링

```cpp
EMappingContextInputModeFilterOptions InputModeFilterOptions;
```

| 값 | 동작 |
|---|---|
| `UseProjectDefaultQuery` (기본) | 프로젝트 설정의 기본 쿼리로 필터링 |
| `UseCustomQuery` | `InputModeQueryOverride` GameplayTagQuery로 필터링 |
| `DoNotFilter` | 현재 입력 모드 무시, 항상 활성 |

`bEnableInputModeFiltering`(Developer Settings)이 켜진 경우에만 적용된다. UI 포커스 중 게임 입력을 막는 등의 용도.

### RegistrationTrackingMode — 다중 등록 처리

```cpp
EMappingContextRegistrationTrackingMode RegistrationTrackingMode;
```

| 값 | 동작 |
|---|---|
| `Untracked` (기본) | Add를 여러 번 해도 Remove 1번이면 제거됨 |
| `CountRegistrations` | Add 횟수만큼 Remove가 필요. 여러 시스템이 같은 IMC를 공유할 때 안전 |

---

## 런타임에서의 역할

1. `AddMappingContext(IMC, Priority)` 호출 시 `UEnhancedInputLocalPlayerSubsystem`의 활성 IMC 목록에 추가
2. 매 틱 `UEnhancedPlayerInput::PrepareInputDelegatesForEvaluation()`이 활성 IMC 목록을 읽어 `EnhancedActionMappings` 빌드
3. 빌드된 `EnhancedActionMappings`를 순회하며 키 상태 → Modifier → Trigger → 값 누적

IMC 자체는 에셋이므로 런타임에 값을 가지지 않는다. 값·상태는 `UEnhancedPlayerInput::ActionInstanceData`가 관리한다.

### Priority — 우선순위

`AddMappingContext(IMC, Priority)` 의 Priority 값이 높을수록 먼저 처리된다. 같은 키가 여러 IMC에 겹칠 때 높은 우선순위 IMC의 매핑이 유효하고, `bConsumeInput = true`인 Action이면 하위 IMC의 같은 키 매핑이 차단된다.

### IMC 교체 패턴

```cpp
// 완전 교체 — 기존 IMC를 제거하고 새 IMC로 전환
Subsystem->RemoveMappingContext(CombatIMC);
Subsystem->AddMappingContext(VehicleIMC, Priority);

// 오버레이 — 기존 IMC를 유지하면서 새 IMC를 위에 추가
Subsystem->AddMappingContext(SprintOverlayIMC, HighPriority);
```

### Overlay — 높은 우선순위 IMC는 자신이 매핑한 키만 차단한다

IMC를 교체하지 않고 위에 추가(overlay)하면, 높은 우선순위 IMC가 **명시적으로 매핑한 키만** 하위 IMC에서 차단된다. 매핑하지 않은 키는 하위 IMC로 그대로 통과된다.

```
IMC_Base (P0):    IA_Move → WASD,  IA_Jump → Space,  IA_Interact → F
IMC_Vehicle (P10): IA_Accelerate → W,  IA_Brake → S

W 입력 → IMC_Vehicle이 소비 → IMC_Base의 IA_Move 차단
Space  → IMC_Vehicle에 매핑 없음 → IMC_Base의 IA_Jump 그대로 발동
F      → IMC_Vehicle에 매핑 없음 → IMC_Base의 IA_Interact 그대로 발동
```

**Overlay vs 완전 교체 선택 기준**:

| 패턴 | 언제 쓰는가 |
|------|------------|
| Overlay (Add만) | 일부 키만 덮어쓰고 나머지는 유지하고 싶을 때 (스프린트, 줌 등) |
| 완전 교체 (Remove + Add) | 입력 세트를 통째로 바꾸고 싶을 때 (도보 → 탈것 전환 등) |

탈것 탑승 시 Space(점프)까지 막으려면 Overlay로는 부족하고 완전 교체를 해야 한다.

---

## 요약

```
UInputMappingContext = 키↔Action 매핑 테이블
  DefaultKeyMappings:
    FEnhancedActionKeyMapping[]
      Action, Key, Triggers[], Modifiers[]
  
  런타임에 AddMappingContext로 활성화
  → UEnhancedPlayerInput이 매 틱 이 테이블을 소비
```
