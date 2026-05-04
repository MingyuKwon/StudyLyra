# 언리얼 네트워킹 / 복제

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 언리얼 복제 시스템 파이프라인

> 출처: `NetDriver.cpp`, `DataChannel.cpp`, `DataReplication.cpp`, `RepLayout.cpp`, `ActorReplication.cpp`

### 서버 매 틱 흐름
```
UNetDriver::TickFlush()
  → ServerReplicateActors()
    1. BuildConsiderList() — 후보 Actor 목록 (NextUpdateTime, RemoteRole, IsActorInitialized 필터)
    2. [각 Connection] IsNetRelevantFor() — 이 클라이언트에 관련 있는가
    3. GetNetPriority() 정렬 — 대역폭 부족 시 우선순위
    4. ActorChannel::ReplicateActor()
         bNetInitial=true: SerializeNewActor() (클라이언트에서 Actor 스폰)
         FObjectReplicator::ReplicateProperties()
           CompareProperties() — 현재값 vs Shadow Buffer 비교
           변경된 프로퍼티만 직렬화 → 전송
```

### Shadow Buffer
- `FRepLayout`이 "지난번에 보낸 값"의 복사본을 유지
- 현재값과 비교해 변경된 것만 직렬화 → 대역폭 절약
- `GShareShadowState`: 같은 프레임에 커넥션 100개라도 CompareProperties는 1번만

### Actor 복제 등록 시점
- `DispatchBeginPlay()` → `StartReplicatingActor()` → `BeginPlay()`
- `RouteEndPlay()` → `StopReplicatingActor()`

### Relevancy 플래그 (ActorReplication.cpp:382)
- `bAlwaysRelevant=true`: 모든 클라이언트에 항상
- `bOnlyRelevantToOwner=true`: Owner만
- 기본값: `NetCullDistanceSquared` 거리 컬링

### NetUpdateFrequency
- `SetNetUpdateFrequency(100.0f)` — ConsiderList 진입 최대 빈도 (초당)
- 높다고 매 틱 복제되는 게 아님 — 대역폭/우선순위에 따라 실제 전송은 스킵 가능

### RPC 내부 흐름
> 출처: `ScriptCore.cpp`, `Actor.cpp`, `NetDriver.cpp`

- **프로퍼티 복제와 차이**: 복제=값 자동 전파, RPC=함수 호출 직접 전달
- **진입점**: `UObject::ProcessEvent()` → `GetFunctionCallspace()` → Remote면 `CallRemoteFunction()` → `NetDriver::ProcessRemoteFunction()`
- **GetFunctionCallspace 로직** (Actor.cpp):
  - Server RPC + 클라이언트 호출 → Remote (서버로 전송)
  - Server RPC + 서버 호출 → Local (이미 서버)
  - Client RPC + 서버 호출 → Remote (Owner 클라이언트로 전송)
  - Multicast + 서버 호출 → Local|Remote (서버 실행 + 모든 클라에 전송)
- **직렬화**: `FRepLayout::SendPropertiesForRPC()` — 파라미터를 비트스트림으로 직렬화
- **Unreliable + 대역폭 포화** → 조용히 드랍 (NetDriver.cpp:2929)
- **Reliable 버퍼 오버플로우** → 연결 자체 끊음 (NetDriver.cpp:3152)
- **Unreliable Multicast** → 즉시 전송 안 하고 틱 끝에 일괄 처리 (QueueBunch)
- **bReplicates=false인 Actor의 RPC** → RemoteRole=ROLE_None → Absorbed (무시)

---

## N. GetLifetimeReplicatedProps 내부 동작 — 매크로 전개

소스: `Engine/Source/Runtime/Engine/Public/Net/UnrealNetwork.h`, `CoreUObject/Public/UObject/CoreNet.h`

### 호출 시점

인스턴스당 매번 호출되지 않는다. `FRepLayout::InitFromObjectClass(UClass*)` 에서 **클래스당 1회**만 호출된다.
결과로 빌드된 `Cmds[]`는 동일 클래스의 모든 인스턴스가 공유한다.

### DOREPLIFETIME 전개 (UnrealNetwork.h:259)

```cpp
DOREPLIFETIME(AMyActor, Health)
  →  GetReplicatedProperty(StaticClass(), c::StaticClass(), GET_MEMBER_NAME_CHECKED(c,v))
       // CPF_Net 플래그 검사 — UPROPERTY(Replicated) 없으면 Fatal
  →  RegisterReplicatedLifetimeProperty(FProperty*, OutLifetimeProps, FDoRepLifetimeParams())
       // OutLifetimeProps.AddUnique( FLifetimeProperty{RepIndex, COND_None, REPNOTIFY_OnChanged} )
```

### FLifetimeProperty 구조 (CoreNet.h:299)

```cpp
class FLifetimeProperty {
    uint16 RepIndex;                               // UHT가 Replicated 프로퍼티마다 자동 부여
    ELifetimeCondition Condition;                  // COND_None, COND_OwnerOnly 등
    ELifetimeRepNotifyCondition RepNotifyCondition; // OnChanged / Always
    bool bIsPushBased;
};
```

`RepIndex`는 UHT가 컴파일 시점에 매기는 고유 번호. 패킷에 필드명 대신 이 번호가 들어간다.

### DOREPLIFETIME_CONDITION 전개 (UnrealNetwork.h:277)

`FDoRepLifetimeParams.Condition = cond` 설정 후 `DOREPLIFETIME_WITH_PARAMS` 호출하는 것과 동일.
RepLayout이 틱마다 해당 Connection이 조건을 만족하는지 확인 후 패킷 포함 여부 결정.

### FDoRepLifetimeParams 전체 옵션 (UnrealNetwork.h:134)

```cpp
struct FDoRepLifetimeParams {
    ELifetimeCondition Condition        = COND_None;
    ELifetimeRepNotifyCondition RepNotifyCondition = REPNOTIFY_OnChanged;
    bool bIsPushBased                  = false;
};
```

---

## 36. PredictionKey 생명주기 & 롤백 메커니즘

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp`
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayPrediction.h`

### Key 두 종류

| 구분 | Activation Prediction Key | Scoped Prediction Key |
|---|---|---|
| 생성 | `InternalTryActivateAbility()` | 각 콜백 `FScopedPredictionWindow` |
| 유효 범위 | `ActivateAbility()` 콜스택 | 콜백 동기 실행 범위 |
| 취득 | `GetActivationPredictionKey()` | `ASC->ScopedPredictionKey` |

### Dependent Key 체인

`FScopedPredictionWindow(ASC, true)` 클라이언트 생성 시 `GenerateDependentPredictionKey()` 호출:
```cpp
KeyType Previous = Current;   // Key#1 기억
Base = Current;                // Base = Key#1
GenerateNewPredictionKey();    // Current = Key#2
FPredictionKeyDelegates::AddDependency(Key#2, Key#1);
// → "Key#1 Reject 시 Key#2도 Reject" 등록 (클라이언트 내부에만 존재)
```

### GA 거부 시 롤백

1. 서버 → `ClientActivateAbilityFailed(Key#1)` RPC
2. `BroadcastRejectedDelegate(Key#1)` → Key#1 GE 롤백
3. `AddDependency`가 등록한 `Reject(Key#2)` 연쇄 호출 → Key#2 GE 롤백
4. Key#3, #4... 전부 같은 방식으로 연쇄
5. `EndAbility()` → 모든 AbilityTask 정리

### 뒤늦은 Input RPC
GA 종료 후 `ServerSetReplicatedEvent` 도착 시 → 델리게이트 해제 상태 → Broadcast 무시, 사이드 이펙트 없음

**핵심**: 연쇄 롤백은 서버 통신 없이 클라이언트 `FPredictionKeyDelegates` 맵에서 순수하게 처리됨.
