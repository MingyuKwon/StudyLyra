# UInputTrigger

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputTriggers.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/InputTriggers.cpp`

---

## 무엇인가

**"언제 Action이 발동되는가"를 결정하는 조건 오브젝트**다. Modifier가 값을 변환한 뒤, Trigger가 그 값을 보고 "지금 Action을 발동할 시점인가?"를 판단한다.

Trigger가 없으면 기본 동작은 `Down` — 입력이 있는 동안 매 틱 발동.  
Trigger를 붙이면 Hold(N초 홀드), Tap(짧게 눌렀다 떼기), Chord(조합키) 같은 복잡한 조건을 코드 없이 구현할 수 있다.

---

## 클래스 위치

```
UObject → UInputTrigger (abstract, EditInlineNew)
         → UInputTriggerTimedBase (abstract, 시간 기반 Trigger의 베이스)
```

`EditInlineNew`이므로 IMC의 키 매핑이나 IA 에셋에서 인라인 생성·편집 가능.

---

## 두 레벨

Trigger는 두 곳에 붙일 수 있고, 항상 이 순서로 평가된다.

### 왜 두 레벨인가

**"키마다 다른 조건"** 과 **"모든 키에 공통인 조건"** 을 분리하기 위해서다.

```
IA_Attack

  마우스 Mapping  → IMC Trigger: 없음 (마우스는 즉시 발동)
  패드 Mapping    → IMC Trigger: Hold(0.1초)
                   "패드 스틱은 드리프트가 있어 0.1초 이상 눌려야 의도적 입력으로 간주"

  IA_Attack 에셋 → Action 레벨 Trigger: 없음
                   "어떤 키든 공통 조건 없음"
```

만약 **어떤 키로 입력받든 반드시 충족해야 하는 조건**이 있다면 IA 에셋에 한 번만 붙이면 된다.

```
IA_HeavyAttack

  마우스 Mapping  → IMC Trigger: 없음
  패드 Mapping    → IMC Trigger: 없음

  IA_HeavyAttack 에셋 → Action 레벨 Trigger: Hold(1.0초)
                         "어떤 키든 1초 이상 눌러야 강공격. 키별로 따로 붙일 필요 없음"
```

두 레벨 모두 통과해야 Action이 발동된다. Mapping 레벨이 먼저, Action 레벨이 나중이다.

| 레벨 | 질문 |
|------|------|
| IMC Trigger | 이 키 고유의 발동 조건이 있는가? (장치별 차이) |
| IA Trigger | 어떤 키로 입력받든 공통으로 충족해야 할 조건이 있는가? |

```
1. Mapping 레벨 (FEnhancedActionKeyMapping.Triggers)
       → 키별 Trigger. 장치 특성에 맞는 조건 처리
       → 예: 패드에만 Hold 적용, 마우스는 그냥 즉시

2. Action 레벨 (UInputAction.Triggers)
       → IA 에셋 Trigger. 키 종류와 무관하게 공통 조건
       → 예: HeavyAttack은 어떤 키든 1초 Hold 필요
```

### Modifier와 다른 점 — 두 레벨이 상충할 수 있다

Modifier는 앞 레벨의 결과를 뒤 레벨이 이어받는 **체인**이라 충돌이 없다. Trigger는 두 레벨이 **각자 독립적으로 평가되고 AND로 결합**하기 때문에, 조합에 따라 동시 충족이 불가능한 경우가 생긴다.

```
Tap(Mapping) + Hold(Action)
  → Tap이 Triggered되려면 짧게 떼야 함
    Hold가 Triggered되려면 길게 눌러야 함
    두 조건을 동시에 충족하는 입력은 존재하지 않음
    → 영원히 발동 안 됨
```

| Mapping 레벨 | Action 레벨 | 결과 |
|---|---|---|
| `Down` | `Hold(1s)` | 호환. 1초 후 Down도 Triggered, Hold도 Triggered → 발동 |
| `Hold(1s)` | `Hold(2s)` | 호환. 2초 시점에 둘 다 Triggered → 2초 후 발동 |
| `Tap` | `Hold` | **상충. 영원히 발동 안 됨** |
| `Pressed` | `Hold` | **상충. Pressed는 누르는 순간만 Triggered, Hold 완료 시점에는 이미 None** |

두 레벨에 Trigger를 분산할 때는 **두 조건이 동시에 Triggered 상태가 될 수 있는지** 반드시 확인해야 한다.

---

## 인터페이스

### UpdateState — 이 틱의 상태 반환

```cpp
virtual ETriggerState UpdateState_Implementation(
    const UEnhancedPlayerInput* PlayerInput,  // 다른 Action 상태 참조 가능 (Chord용)
    FInputActionValue ModifiedValue,           // Modifier 적용 후 값
    float DeltaTime
) → ETriggerState
```

매 틱 호출된다. Trigger 내부 상태(HeldDuration 등)를 갱신하고 현재 상태를 반환한다.

### GetTriggerType — 복수 Trigger 결합 방식

```cpp
virtual ETriggerType GetTriggerType_Implementation() → ETriggerType
```

같은 Action에 Trigger가 여러 개일 때 어떻게 결합할지 결정한다. → [결합 규칙 참고](#trigger-결합-규칙-ftriggerstatetracker)

### IsBlocking — Blocker 차단 동작

```cpp
virtual bool IsBlocking(ETriggerState State) const → bool
```

Blocker 타입 Trigger만 override한다. true 반환 시 다른 모든 Trigger 무효화.

---

## 세 가지 핵심 열거형

### ETriggerState — Trigger 하나의 상태

```
None      : 조건 미충족
Ongoing   : 조건 진행 중 (예: Hold 타이머 측정 중)
Triggered : 조건 완전 충족
```

개별 `UpdateState()`가 반환하는 값이다.

### ETriggerType — 복수 Trigger 결합 방식

```
Explicit (기본) : 이 Trigger가 Triggered면 Action 발동 가능
Implicit        : 이 Trigger가 모두 Triggered여야 Action 발동 가능
Blocker         : IsBlocking()이 true이면 다른 Trigger 전부 무효화
```

### ETriggerEvent — Action 전체의 상태 전환 이벤트

`BindAction(Action, ETriggerEvent::Triggered, ...)` 에 쓰이는 이벤트다. 개별 Trigger의 ETriggerState가 아니라, **Action 전체**의 상태 전환을 나타낸다.

| ETriggerEvent | 발생 조건 |
|---|---|
| `Started` | None → Ongoing 또는 None → Triggered 전환 |
| `Ongoing` | Ongoing → Ongoing 유지 |
| `Triggered` | 발동 조건 충족 |
| `Canceled` | Ongoing → None (조건 미달로 취소) |
| `Completed` | Triggered → None (종료) |

---

## Trigger 결합 규칙 (FTriggerStateTracker)

Action에 Trigger가 여러 개일 때 결합 방식:

```
Implicits == 0, Explicits == 0  → 트리거 없음. 값이 0이 아니면 Triggered
Implicits == 0, Explicits  > 0  → Explicit 중 하나라도 Triggered면 Triggered
Implicits  > 0, Explicits == 0  → Implicit 전부 Triggered여야 Triggered
Implicits  > 0, Explicits  > 0  → Implicit 전부 + Explicit 하나 이상
Blocker IsBlocking() true       → 모두 None으로 강제
```

---

## 내장 Trigger 목록

### 기본 (ETriggerType: Explicit)

| 클래스 | 발동 조건 |
|---|---|
| **Down** (기본값) | 입력 ActuationThreshold 이상인 동안 **매 틱** |
| **Pressed** | Threshold 초과하는 **순간 1회**. 홀드해도 다시 발동 안 함 |
| **Released** | Threshold 아래로 내려가는 **순간 1회** |

### 시간 기반 (UInputTriggerTimedBase 파생)

```cpp
float HeldDuration;           // 누적 시간
bool  bAffectedByTimeDilation; // true이면 TimeDilation 적용, false이면 실제 시간
```

| 클래스 | 발동 조건 |
|---|---|
| **Hold** | `HoldTimeThreshold`초 이상 홀드 후 발동. `bIsOneShot`으로 반복 제어 |
| **HoldAndRelease** | `HoldTimeThreshold`초 이상 홀드 후 **떼는 순간** 발동 |
| **Tap** | `TapReleaseTimeThreshold`초 이내에 떼면 발동 |
| **RepeatedTap** | `NumberOfTapsWhichTriggerRepeat`번 연속 탭 (`RepeatDelay` 이내) |
| **Pulse** | 누르는 동안 `Interval`초마다 반복. `TriggerLimit`으로 횟수 제한 |

### 조합 (ETriggerType: Implicit / Blocker)

| 클래스 | ETriggerType | 용도 |
|---|---|---|
| **ChordAction** | Implicit | `ChordAction`이 Triggered여야 이 Action도 발동. Ctrl+C 같은 조합키 |
| **ChordBlocker** | Blocker | 조합키의 단독 키 발동을 막음. 자동 삽입, **수동 추가 금지** |
| **Combo** | Implicit | `ComboActions` 배열 순서대로 완료해야 발동. 격투게임 커맨드 입력 |

### Chord 조합키 구현 원리

```
IA_Ctrl에 ChordBlocker 자동 삽입
    → Ctrl 단독 입력 시 ChordBlocker.IsBlocking() = true → IA_Ctrl 콜백 차단

IA_CtrlC에 ChordAction(ChordAction = IA_Ctrl) 추가
    → IA_Ctrl이 Triggered 상태여야 IA_CtrlC가 Triggered 가능
    → Ctrl+C 동시 입력 → IA_CtrlC 발동
```

`EnhancedInput.OnlyTriggerLastActionInChord = 1` (기본): 체인의 마지막 Action(IA_CtrlC)만 발동하고 IA_Ctrl은 억제.

### ChordAction이 다른 Action 상태를 확인하는 방법

`UpdateState_Implementation`은 `UEnhancedPlayerInput* PlayerInput`을 받는다. `PlayerInput`이 `ActionInstanceData` 맵을 들고 있기 때문에, Trigger가 다른 Action의 현재 상태를 조회할 수 있다.

```cpp
// UInputTriggerChordAction::UpdateState_Implementation (엔진 소스)
ETriggerState UInputTriggerChordAction::UpdateState_Implementation(
    const UEnhancedPlayerInput* PlayerInput, FInputActionValue ModifiedValue, float DeltaTime)
{
    // ChordAction의 FInputActionInstance를 꺼내서 그 ETriggerState를 그대로 상속
    const FInputActionInstance* EventData = PlayerInput->FindActionInstanceData(ChordAction);
    return EventData ? EventData->GetEvaluatedActionTriggerState() : ETriggerState::None;
}
```

`PlayerInput->FindActionInstanceData(ChordAction)` → 해당 Action의 런타임 인스턴스 반환  
`GetEvaluatedActionTriggerState()` → 이번 틱에 평가된 `ETriggerState` 반환

ChordAction이 Triggered면 이 Trigger도 Triggered를 반환 → 조합 조건 충족.  
이것이 `UpdateState_Implementation`의 첫 번째 파라미터로 `PlayerInput`이 넘어오는 이유다. 다른 Action 상태를 참조할 수 있게 하기 위함이다. Combo Trigger도 동일한 방식으로 각 단계 Action의 상태를 확인한다.

---

## 유용한 프로퍼티

```cpp
float ActuationThreshold = 0.5f;  // IsActuated() 기준. 이 이상이어야 "눌린" 것으로 판단
bool  bShouldAlwaysTick = false;  // true이면 키 입력 없어도 매 틱 UpdateState 호출
                                   // 성능에 영향. 특수 목적에만 사용
FInputActionValue LastValue;       // 이전 틱 값. Pressed/Released 판단에 내부적으로 사용
```

---

## 커스텀 Trigger 작성

```cpp
UCLASS(EditInlineNew, BlueprintType, meta=(DisplayName="My Trigger"))
class UMyInputTrigger : public UInputTrigger
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    float MyThreshold = 0.8f;

protected:
    virtual ETriggerState UpdateState_Implementation(
        const UEnhancedPlayerInput* PlayerInput,
        FInputActionValue ModifiedValue,
        float DeltaTime) override
    {
        // 예: 80% 이상 눌렸을 때만 Triggered
        return ModifiedValue.GetMagnitude() >= MyThreshold
            ? ETriggerState::Triggered
            : ETriggerState::None;
    }
};
```

---

## 요약

```
UInputTrigger = 발화 조건 판단기
  UpdateState_Implementation()  ← 오버라이드 포인트, ETriggerState 반환
  GetTriggerType_Implementation() ← Explicit(기본) / Implicit / Blocker
  
ETriggerState: Trigger 하나의 상태 (None / Ongoing / Triggered)
ETriggerEvent: Action 전체의 이벤트 (Started / Ongoing / Triggered / Canceled / Completed)
  → BindAction의 두 번째 인자로 사용
```
