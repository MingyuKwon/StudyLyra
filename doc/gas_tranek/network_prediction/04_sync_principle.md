# GAS 네트워크 동기화 원칙

> 출처: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`  
>        `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`

---

## 두 가지 동기화 방식

GAS는 동기화 대상에 따라 메커니즘을 나눈다.

| 구분 | 예시 | 메커니즘 |
|------|------|---------|
| **상태성** | Attribute 값, 활성 GE, 활성 태그 | Replicated 변수 (지속 동기화) |
| **이벤트성** | GA 활성화·취소, 입력 신호, TargetData | RPC + 클라 예측 |

---

## 상태성 — Replicated 변수

서버가 권위를 가지는 지속 상태값은 레플리케이션으로 계속 동기화한다.  
패킷이 유실돼도 다음 주기에 자동 보정된다.

| 상태 | 복제 방식 |
|------|---------|
| Attribute 값 | `UPROPERTY(Replicated)` |
| 활성 GE | `ActiveGameplayEffects` — FFastArraySerializer |
| 활성 태그 | `ReplicatedTags` |

---

## 이벤트성 — RPC + 클라 예측

일회성 이벤트는 레플리케이션으로 표현할 수 없다. 클라가 먼저 로컬에서 실행하고(즉각 반응), 서버에 RPC를 보내 동일한 로직을 실행시킨다.

```
클라: GA 예측 실행 → 로컬에서 즉시 처리
서버: ServerTryActivateAbility() 수신 → 동일 로직 실행 → 결과 확정
```

---

## 왜 이 구조가 작동하는가

### RPC 발산 문제

RPC가 정상 전달돼도, 클라가 보낸 시점과 서버가 실행하는 시점 사이에 RTT만큼 시간이 지난다.  
그 사이 서버 상태가 달라져 있으면 로직 결과가 발산할 수 있다.

```
클라: 체력 100 → 스킬 사용 → ServerTryActivateAbility() 전송
      ↓ (RTT 동안 서버 상태 변화)
서버: 체력 5, CC 상태로 수신 → 조건 불충족 → 활성화 거부
클라: 이미 로컬에서 실행 중 → 발산
```

### 레플리케이션이 최종 교정한다

RPC로 실행된 로직이 발산해도, 그 결과로 바뀌는 Attribute·GE·태그는 레플리케이션이 덮어씌운다.  
**RPC는 트리거, 레플리케이션은 최종 심판자다.**

```
클라 예측: GA 실행 → Health -30 로컬 적용 → 즉시 UI 반영
서버 거부: GA 활성화 안 함 → Health 변화 없음
           → 레플리케이션으로 서버 체력값 전송
클라:      서버값 수신
  ├─ 예측 일치 → 그대로 유지
  └─ 예측 불일치 → 서버값으로 롤백
```

클라가 예측으로 먼저 반응하고(응답성), 서버가 레플리케이션으로 정답을 덮어쓰는(정확성) 이 구조 덕분에 네트워크 지연이 있어도 입력에 즉각 반응하는 것처럼 느껴진다.  
Prediction Key 시스템은 발산을 감지해 롤백 타이밍을 잡기 위한 장치다.
