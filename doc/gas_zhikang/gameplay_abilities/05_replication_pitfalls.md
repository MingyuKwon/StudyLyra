# GA 복제 주의사항

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## GA를 일반 복제 오브젝트처럼 취급할 수 없다

GA의 활성화·종료는 `Replication Policy` 설정과 무관하게 **거의 항상 복제**된다.
유일한 예외는 `NetExecutionPolicy`를 `ServerOnly`로 설정한 경우다.

---

## 복제되는 GA의 조건

다음 두 가지를 **모두** 충족해야 한다:

1. `Replication Policy = Replicate`
2. `Instancing Policy = InstancedPerActor` 또는 `InstancedPerExecution`

`NonInstanced` 어빌리티는 클래스의 CDO(Class Default Object)를 사용하는데, CDO는 네트워크 오브젝트가 아니므로 복제 불가.
UE 5.5부터 NonInstanced 어빌리티는 사용자 오류를 유발하기 쉽다는 이유로 deprecated됐다.

복제된 GA는 **서버와 소유 플레이어의 클라이언트에만 존재**한다.
따라서 NetMulticast RPC를 시청각 피드백 목적으로 사용할 수 없다.

---

## GA에 복제 프로퍼티 사용 금지

GA에 복제 프로퍼티를 사용하는 것을 **강력히 권장하지 않는다.** UE 5.5부터 deprecated됐다.

**이유**: 어빌리티 활성화는 Reliable RPC로 처리된다.
서버가 복제 프로퍼티 값을 변경해도 그 변경이 어빌리티 활성화 RPC와 같은 순서로 클라이언트에 도착한다는 보장이 없다.

| Instancing Policy | 문제 |
|---|---|
| InstancedPerActor | 클라이언트가 이전 활성화에서의 outdated 값으로 어빌리티를 실행할 수 있음 |
| InstancedPerExecution | 서버가 설정한 복제값이 클라이언트 측 어빌리티 활성화 전에 도달하지 않음 |

---

## 서버-클라이언트 간 값 전달 — Reliable RPC 사용

복제 프로퍼티 대신 **Reliable RPC**를 사용한다.
같은 Actor의 Reliable RPC는 상대방에서도 동일한 순서로 실행된다.
어빌리티의 활성화·종료·취소·타겟 설정 자체도 Reliable RPC로 구현되어 있으므로,
그 사이에 호출하는 커스텀 Reliable RPC도 같은 순서가 보장된다.

### WaitNetSync

서버 측 실행이 클라이언트 측의 특정 지점 도달을 기다려야 하거나 그 반대인 경우 `WaitNetSync` AbilityTask를 사용한다.
한쪽이 특정 지점에 도달할 때까지 다른 쪽을 대기시켜 실행 흐름을 동기화한다.
한쪽이 다른 쪽의 확인을 기다리는 동안 레이턴시가 발생한다.

---

## 모든 클라이언트에 시청각 피드백 전달하는 방법

GA는 NetMulticast RPC를 직접 사용할 수 없으므로, 다음 방법 중 하나를 선택한다.

### 방법 1: GE → GameplayCue (Epic 권장)

어빌리티가 GameplayEffect를 적용하고, 그 GE에 GameplayCue를 연결한다.

- **서버가 GE를 적용하는 경우**: 모든 클라이언트에서 GE 효과가 적용되고 Cue가 로컬에서 실행된다.
- **로컬 예측 GA에서 GE를 적용하는 경우**: GE와 Cue가 예측적으로 실행된다. 서버가 어빌리티를 거부하면 예측 GE와 루프 Cue도 함께 제거된다.

이 방식은 예측 케이스까지 깔끔하게 처리하기 때문에 Epic이 가장 권장한다.

### 방법 2: 서버 측에서 GameplayCue 직접 실행

서버 측 GA 활성화에서 GameplayCue를 직접 실행하면 모든 클라이언트의 GameplayCue Notify가 반응한다.

- `ExecuteGameplayCueOnOwner` — 어빌리티 소유 Actor 대상
- `Add/ExecuteGameplayCueOnActor` — 모든 Actor 대상

단, 이 방식은 로컬 예측으로 어빌리티를 활성화한 플레이어가 **즉각적인 피드백을 받지 못한다.**

### 방법 3: 복제 Actor 등 다른 시스템 활용

서버 측 GA 활성화에서 복제 Actor를 스폰하거나, 다른 복제 시스템을 통해 시청각 요소를 전달한다.
