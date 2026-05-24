# GAS 네트워크 동기화 원칙

> 출처: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`  
>        `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`

---

## 두 가지 동기화 방식

GAS는 동기화 대상에 따라 메커니즘을 나눈다.

| 구분 | 예시 | 메커니즘 |
|------|------|---------|
| **이벤트성** | GA 활성화·취소, 입력 신호, TargetData 전송 | RPC + 클라 예측 |
| **상태성** | Attribute 값, 활성 GE, 활성 태그 | Replicated 변수 (지속 동기화) |

---

## 이벤트성 — RPC + 클라 예측

클라가 먼저 로컬에서 실행하고, 서버에 RPC를 보낸다. 양쪽이 동일한 로직을 독립적으로 실행해서 결과를 맞춘다.

```
클라: GA 예측 실행 → 로컬에서 즉시 처리 (빠른 응답성)
서버: ServerTryActivateAbility() 수신 → 동일 로직 실행 → 결과 확정
```

서버가 결과를 거부하면 클라 상태를 롤백한다. 예측이 맞으면 그대로 유지.

입력 신호 경로도 동일한 구조다.

```
클라: 키 뗌 → WaitInputRelease::OnReleaseCallback()
                → ServerSetReplicatedEvent() RPC
서버: RPC 수신 → 동일 콜백 실행 → GA 종료
```

GA 취소 방법별 서버 동기화 경로:

| 취소 방법 | 서버 동기화 RPC |
|-----------|----------------|
| WaitInputRelease | Task 내장 `ServerSetReplicatedEvent()` |
| 취소 GA 실행 | `ServerTryActivateAbility()` — GA 예측 흐름 |
| 직접 CancelAbility | `EndAbility()` 내장 `ServerEndAbility()` |

---

## 상태성 — Replicated 변수

이벤트 이후 확정된 결과값은 레플리케이션으로 계속 동기화한다.

```
서버: GE 적용 → Health 감소 → 레플리케이션
클라: Health 값 수신 → OnRep_Health() → UI 갱신
```

| 상태 | 복제 방식 |
|------|---------|
| Attribute 값 | `UPROPERTY(Replicated)` |
| 활성 GE | `ActiveGameplayEffects` — FFastArraySerializer |
| 활성 태그 | `ReplicatedTags` |

---

## 예측이 브릿지 역할을 한다

클라가 예측으로 로컬 상태를 먼저 바꾸고(빠른 응답성), 서버가 나중에 레플리케이션으로 정답을 덮어쓴다(정확성).

```
클라 예측: GA 활성화 → Health -30 로컬 적용 → 즉시 UI 반영
서버 확정: GE 적용 → Health -30 레플리케이션 → 클라 수신
  ├─ 예측 일치 → 그대로 유지
  └─ 예측 불일치 → 서버값으로 덮어쓰기 (롤백)
```

이 구조 덕분에 네트워크 지연이 있어도 입력에 즉각 반응하는 것처럼 느껴진다.
