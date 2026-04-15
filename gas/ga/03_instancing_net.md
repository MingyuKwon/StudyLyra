# Instancing Policy & Net Execution Policy

> 참고: [GAS Doc 캐시](../gas_doc_cache.md)

---

## Instancing Policy

GA가 메모리에서 어떻게 인스턴스화되는지 결정한다.

| Policy | 설명 | Lyra 기본값 |
|---|---|---|
| `InstancedPerActor` | ASC당 1개 인스턴스 재사용 | ✅ 기본값 |
| `InstancedPerExecution` | 활성화마다 새 인스턴스 생성 | 성능 나쁨, 가급적 사용 금지 |
| `NonInstanced` | CDO에서 직접 실행 | Deprecated. 상태 저장 불가 |

### InstancedPerActor (Lyra 기본)

```cpp
// 생성자에서
InstancingPolicy = EGameplayAbilityInstancingPolicy::InstancedPerActor;
```

- 한 ASC에 대해 GA 인스턴스 1개만 유지
- 변수 상태가 활성화 간 유지되므로, `ActivateAbility()` 시작 시 수동 리셋 필요
- AbilityTask 델리게이트 바인딩 가능

### NonInstanced 지원 종료

Lyra에서는 NonInstanced가 Deprecated 처리되어 경고를 발생시킨다.

```cpp
// LyraAbilitySystemComponent::InitAbilityActorInfo()에서 검사
ensureMsgf(
    AbilitySpec.Ability->GetInstancingPolicy() != EGameplayAbilityInstancingPolicy::NonInstanced,
    TEXT("InitAbilityActorInfo: All Abilities should be Instanced...")
);
```

---

## Net Execution Policy

GA가 어느 위치에서 실행되는지를 결정한다.

| Policy | 실행 위치 | 설명 |
|---|---|---|
| `LocalPredicted` | 클라이언트 먼저 + 서버 검증 | Lyra 기본값. 반응성 좋음 |
| `LocalOnly` | 소유 클라이언트에서만 | 순수 클라이언트 효과 (UI, 사운드) |
| `ServerOnly` | 서버에서만 | 패시브 GA, 게임 로직 |
| `ServerInitiated` | 서버 먼저 + 클라이언트 | 서버가 시작 신호 |

```cpp
// 생성자에서
NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::LocalPredicted;
```

### LocalPredicted 흐름

```
클라이언트가 먼저 ActivateAbility() 실행
    │ PredictionKey 생성 → 서버에 RPC
    ▼
서버에서 CanActivateAbility() 검증
    │ 성공: 서버도 ActivateAbility() → ClientActivateAbilitySucceed()
    │ 실패: ClientActivateAbilityFailed() → 클라이언트 롤백
```

### OnSpawn 정책과 NetExecution 조합

```cpp
// TryActivateAbilityOnSpawn에서
const bool bIsLocalExecution = (NetExecutionPolicy == LocalPredicted) || (NetExecutionPolicy == LocalOnly);
const bool bIsServerExecution = (NetExecutionPolicy == ServerOnly) || (NetExecutionPolicy == ServerInitiated);

const bool bClientShouldActivate = ActorInfo->IsLocallyControlled() && bIsLocalExecution;
const bool bServerShouldActivate = ActorInfo->IsNetAuthority() && bIsServerExecution;
```

패시브 GA의 일반 패턴:
- `ActivationPolicy = OnSpawn`
- `NetExecutionPolicy = ServerOnly`
- 서버에서만 실행하면서 GE를 통해 클라이언트에 복제

---

## Net Security Policy

능력 실행 권한을 제어한다.

| Policy | 설명 |
|---|---|
| `ClientOrServer` | 제한 없음 (기본값) |
| `ServerOnlyExecution` | 클라이언트의 실행 요청 무시 |
| `ServerOnlyTermination` | 클라이언트의 취소/종료 요청 무시 |
| `ServerOnly` | 서버가 완전히 제어 |

---

## Replication Policy

```cpp
// Lyra 기본
ReplicationPolicy = EGameplayAbilityReplicationPolicy::ReplicateNo;
```

Replication Policy는 사용하지 않도록 권장된다 (향후 제거 예정). 대신:
- GA 실행 결과는 GE를 통해 복제
- 애니메이션은 `PlayMontageAndWait` AbilityTask가 ASC 통해 복제
