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
