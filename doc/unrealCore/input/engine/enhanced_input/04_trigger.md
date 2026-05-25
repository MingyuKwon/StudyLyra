# Trigger 평가 체인

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputTriggers.h`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/InputTriggers.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedPlayerInput.cpp`

---

## 세 가지 열거형의 관계

| 열거형 | 설명 | 사용 위치 |
|---|---|---|
| `ETriggerState` | 개별 Trigger 하나의 상태 (None / Ongoing / Triggered) | `UpdateState()` 반환값 |
| `ETriggerType` | Trigger가 Action 전체에 미치는 방식 | `GetTriggerType()` |
| `ETriggerEvent` | Action 전체의 상태 전환 이벤트 | 바인딩 콜백 조건 |

---

## ETriggerState — 개별 Trigger 상태

```
None      : 조건 미충족, Trigger 비활성
Ongoing   : 조건 진행 중 (예: Hold 시간 측정 중)
Triggered : 조건 완전 충족
```

---

## ETriggerType — 복수 Trigger 결합 규칙

`FTriggerStateTracker.EvaluateTriggers`가 이 타입에 따라 결합한다.

```
Implicits == 0, Explicits == 0  → 트리거 없음, ModifiedValue가 0이 아니면 Triggered
Implicits == 0, Explicits  > 0  → Explicit 중 하나라도 Triggered이면 Triggered
Implicits  > 0, Explicits == 0  → Implicit 모두 Triggered이어야 Triggered
Implicits  > 0, Explicits  > 0  → Implicit 전부 + Explicit 하나 이상
Blockers   > 0                  → IsBlocking() true인 Blocker가 있으면 강제 None
```

| ETriggerType | 역할 |
|---|---|
| `Explicit` | 이 Trigger가 발동하면 Action이 발동될 수 있다 |
| `Implicit` | 이 Trigger가 모두 발동해야 Action이 발동될 수 있다 |
| `Blocker` | IsBlocking() true이면 다른 모든 Trigger를 무효화한다 |

기본값은 `Explicit`.

---

## ETriggerEvent — Action 상태 전환 이벤트

`GetTriggerStateChangeEvent(LastTriggerState, NewTriggerState)`가 반환하는 내부 enum이 `ConvertInternalTriggerEvent`를 거쳐 `ETriggerEvent`로 변환된다.

### 상태 전환 테이블

| LastTriggerState | NewTriggerState | ETriggerEvent |
|---|---|---|
| None | Ongoing | Started |
| None | Triggered | Started + Triggered (같은 프레임에 둘 다 발생) |
| Ongoing | None | Canceled |
| Ongoing | Ongoing | Ongoing |
| Ongoing | Triggered | Triggered |
| Triggered | Triggered | Triggered |
| Triggered | Ongoing | Ongoing |
| Triggered | None | Completed |

### StartedAndTriggered 특수 처리

`None → Triggered` 전환(단일 틱 발동)은 내부적으로 `StartedAndTriggered`로 표시된다. `EvaluateInputComponentDelegates`에서 Started 바인딩을 먼저 실행하고(EmplaceAt 0), 그 다음 Triggered 바인딩을 실행한다.

```cpp
if (ActionData->TriggerEventInternal == ETriggerEventInternal::StartedAndTriggered)
{
    // Started 바인딩 실행 시 TriggerEvent를 일시적으로 Started로 교체
    ActionData->TriggerEvent = Delegate->GetTriggerEvent();
    Delegate->Execute(*ActionData);
    ActionData->TriggerEvent = OriginalEvent;  // 복원
}
```

---

## UInputTrigger 기반 클래스

```
UInputTrigger (abstract)
    UpdateState_Implementation() → ETriggerState
    ActuationThreshold           → IsActuated() 헬퍼
    bShouldAlwaysTick            → true이면 EKeyEvent::None에도 매 틱 실행
    LastValue                    → 이전 틱 값 (Pressed/Released 판단에 사용)

UInputTriggerTimedBase (abstract)
    HeldDuration                 → 누적 시간
    CalculateHeldDuration()      → bAffectedByTimeDilation에 따라 Real/Dilated 선택
```

---

## 내장 Trigger 목록

| 클래스 | 발동 조건 | ETriggerType |
|---|---|---|
| **Down** (기본) | 입력이 ActuationThreshold 이상인 동안 매 틱 | Explicit |
| **Pressed** | Threshold 초과 순간 한 번만 | Explicit |
| **Released** | Threshold 아래로 내려가는 순간 | Explicit |
| **Hold** | `HoldTimeThreshold`초 이상 지속 후 발동 (`bIsOneShot`으로 반복 제어) | Explicit |
| **HoldAndRelease** | Hold 후 떼는 순간 발동 | Explicit |
| **Tap** | `TapReleaseTimeThreshold`초 내에 떼면 발동 | Explicit |
| **RepeatedTap** | `NumberOfTapsWhichTriggerRepeat`번 연속 탭 | Explicit |
| **Pulse** | 누르고 있는 동안 `Interval`초마다 반복 발동 | Explicit |
| **ChordAction** | `ChordAction`이 Triggered 상태여야 이 Action도 발동 | **Implicit** |
| **ChordBlocker** | ChordAction 키 단독 사용 시 차단 (자동 생성, 수동 추가 금지) | **Blocker** |
| **Combo** | `ComboActions` 배열 순서대로 완료해야 발동 | **Implicit** |

### Chord 동작 원리

`CtrlC` 같은 조합키를 구현할 때 사용한다.

1. `IA_CtrlC`에 `ChordAction = IA_Ctrl` Trigger 추가
2. `IA_Ctrl` 매핑에 자동으로 `ChordBlocker` 삽입
3. Ctrl 단독 입력 시: ChordBlocker가 Blocking → `IA_Ctrl` 단독 콜백 차단
4. Ctrl+C 입력 시: ChordAction이 Triggered → `IA_CtrlC` 발동

`EnhancedInput.OnlyTriggerLastActionInChord = 1` (기본): 체인의 마지막 Action만 발동하고 중간 Chord Action은 억제.

---

## bShouldAlwaysTick 주의사항

`UInputTrigger::bShouldAlwaysTick = true`이면 키 입력이 없는 틱에도 `ProcessActionMappingEvent`가 호출된다. 성능에 영향을 주므로 특수 목적에만 사용한다. Mapping의 `bHasAlwaysTickTrigger` 플래그로 이 상태를 추적한다.
