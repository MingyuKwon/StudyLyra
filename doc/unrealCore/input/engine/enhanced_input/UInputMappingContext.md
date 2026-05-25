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
// 전투 → 탈것 전환
Subsystem->RemoveMappingContext(CombatIMC);
Subsystem->AddMappingContext(VehicleIMC, Priority);

// 오버레이 추가 (기존 유지 + 새 컨텍스트 추가)
Subsystem->AddMappingContext(SprintOverlayIMC, HighPriority);
```

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
