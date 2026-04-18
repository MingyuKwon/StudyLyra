# RPC (Remote Procedure Call)

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/ScriptCore.cpp`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Private/NetDriver.cpp`

---

## Replication과 RPC의 차이

헷갈리기 쉬운데 근본적으로 다른 메커니즘이다.

| | Replication (프로퍼티 복제) | RPC |
|---|---|---|
| 무엇을 보내나 | **값** (UPROPERTY) | **함수 호출** + 파라미터 |
| 언제 보내나 | 서버 틱마다 변경 감지 시 자동 | 코드에서 직접 호출 시 |
| 방향 | 서버 → 클라이언트 (단방향) | Server / Client / Multicast (3가지) |
| 수신 측 동작 | 값 적용 + OnRep 콜백 | 함수를 그대로 실행 |
| 신뢰성 | 항상 신뢰 (TCP-like) | Reliable / Unreliable 선택 |

> 프로퍼티 복제: "이 값이 지금 80이야, 반영해"  
> RPC: "지금 이 함수를 실행해"

---

## RPC 선언 방법

```cpp
// 클라이언트 → 서버
UFUNCTION(Server, Reliable)
void ServerFire();

// 서버 → 특정 클라이언트 (Actor Owner)
UFUNCTION(Client, Unreliable)
void ClientPlayEffect();

// 서버 → 모든 클라이언트 (+ 서버 자신)
UFUNCTION(NetMulticast, Unreliable)
void MulticastExplosion();
```

`Server`, `Client`, `NetMulticast` 는 UHT가 `FUNC_NetServer`, `FUNC_NetClient`, `FUNC_NetMulticast` 플래그로 변환한다.  
`Reliable` → `FUNC_NetReliable`.

---

## 내부 호출 흐름 — ProcessEvent가 가로챈다

RPC를 호출하면 일반 함수 호출처럼 보이지만, `UObject::ProcessEvent()`가 중간에 가로채서 네트워크로 보낸다.

```
코드에서 ServerFire() 호출
  ↓
UObject::ProcessEvent(Function, Parms)     ScriptCore.cpp:2015
  │
  ├─ GetFunctionCallspace()                ← 이 함수를 어디서 실행할지 판단
  │    → Local / Remote / (Local|Remote)
  │
  ├─ (Remote 포함이면) CallRemoteFunction() ← 네트워크로 전송
  │
  └─ (Local 포함이면) 로컬에서도 실행
```

```cpp
// ScriptCore.cpp:2048
int32 FunctionCallspace = GetFunctionCallspace(Function, NULL);
if (FunctionCallspace & FunctionCallspace::Remote)
    CallRemoteFunction(Function, Parms, NULL, NULL);  // 원격 전송

if ((FunctionCallspace & FunctionCallspace::Local) == 0)
    return;  // Remote만이면 로컬 실행 없이 종료
// Local 포함이면 계속해서 함수 본체 실행
```

---

## GetFunctionCallspace — 어디서 실행할지 결정

`AActor::GetFunctionCallspace()` (Actor.cpp:5430)

이 함수가 RPC 동작의 핵심 로직이다.

```
[Server RPC — FUNC_NetServer]
  클라이언트에서 호출:
    LocalRole = AutonomousProxy, bIsServer=false, FUNC_NetServer
    → Remote 반환 (서버로 전송)

  서버에서 호출:
    bIsServer=true, FUNC_NetServer (send-to-server 아님)
    → Local 반환 (자기 자신 = 이미 서버, 로컬 실행)

[Client RPC — FUNC_NetClient]
  서버에서 호출:
    bIsServer=true, FUNC_NetClient
    → Remote 반환 (클라이언트로 전송)

  클라이언트에서 호출:
    bIsServer=false, FUNC_NetClient (send-to-client 아님)
    → Local 반환 (무시 또는 로컬 실행)

[Multicast — FUNC_NetMulticast]
  서버에서 호출:
    → (Local | Remote) 반환 — 서버도 실행, 모든 클라이언트에도 전송
    // Actor.cpp:5504: Server should execute locally and call remotely

  클라이언트에서 호출:
    → Local 또는 Absorbed — 클라이언트가 Multicast를 직접 쏘는 건 무의미
```

---

## CallRemoteFunction → NetDriver 전송

`AActor::CallRemoteFunction()` (Actor.cpp:5613)

```cpp
bool AActor::CallRemoteFunction(UFunction* Function, void* Parameters, ...)
{
    // 이 Actor가 속한 World의 NetDriver들을 순회
    for (FNamedNetDriver& Driver : Context->ActiveNetDrivers)
    {
        if (Driver.NetDriver->ShouldReplicateFunction(this, Function))
            Driver.NetDriver->ProcessRemoteFunction(this, Function, Parameters, ...);
    }
}
```

`NetDriver::InternalProcessRemoteFunctionPrivate()` (NetDriver.cpp:2911)

```cpp
// 대역폭 포화 상태이고 Unreliable RPC면 드랍
if (!(Function->FunctionFlags & FUNC_NetReliable) && !Connection->IsNetReady())
    return;  // NetDriver.cpp:2929

// Actor Channel 확인 — 없으면 새로 생성 (서버 기준)
UActorChannel* Ch = Connection->FindActorChannelRef(Actor);
if (!Ch)
    Ch = Connection->CreateChannelByName(NAME_Actor, ...);

// 실제 직렬화 + 전송
ProcessRemoteFunctionForChannelPrivate(Ch, ..., Function, Parms, ...);
```

`ProcessRemoteFunctionForChannelPrivate()` (NetDriver.cpp:3051):

```cpp
// Reliable 여부 설정
if (Function->FunctionFlags & FUNC_NetReliable)
    Bunch.bReliable = 1;

// 파라미터 직렬화
TSharedPtr<FRepLayout> RepLayout = GetFunctionRepLayout(Function);
RepLayout->SendPropertiesForRPC(Function, Ch, TempWriter, Parms);
// → 파라미터들을 비트스트림으로 직렬화

// Unreliable Multicast는 큐에 쌓고, 나머지는 즉시 전송
if (QueueBunch)  // Unreliable Multicast
    Ch->WriteFieldHeaderAndPayload(Bunch, ...);  // 이번 틱 끝에 일괄 전송
else
    Ch->SendBunch(&Bunch, ...);  // 즉시 전송
```

---

## 수신 측 처리

클라이언트(또는 서버)가 RPC 패킷을 받으면:

```
ReceivedBunch()
  → UActorChannel::ProcessBunch()
      → UObject::ProcessEvent(Function, ReceivedParms)
           → GetFunctionCallspace() → Local
           → 함수 본체 실행
```

수신 측은 `GetFunctionCallspace`가 `Local`을 반환하도록 상태가 맞춰져 있다.  
서버가 `ServerFire_Implementation()`을 실행할 때는 `LocalRole = Authority`이므로 다시 네트워크로 나가지 않는다.

---

## Server RPC와 Validation

```cpp
UFUNCTION(Server, Reliable, WithValidation)
void ServerFire(FVector Location);

// 자동 생성되는 두 함수
bool ServerFire_Validate(FVector Location);   // 검증
void ServerFire_Implementation(FVector Location);  // 실제 구현
```

`WithValidation`을 붙이면 서버 수신 시 `_Validate`가 먼저 호출된다.  
`false` 반환 시 해당 클라이언트 연결을 끊는다 (치팅 방지용).

```cpp
bool AMyActor::ServerFire_Validate(FVector Location)
{
    return Location.Z > -10000.f;  // 말도 안 되는 값이면 false → 연결 끊음
}
```

---

## Reliable vs Unreliable

```cpp
// Reliable — 반드시 도착 보장, 순서 보장
UFUNCTION(Server, Reliable)
void ServerImportantAction();

// Unreliable — 도착 보장 없음, 패킷 로스 허용
UFUNCTION(NetMulticast, Unreliable)
void MulticastFootstep();
```

**코드에서 차이** (NetDriver.cpp:2929):

```cpp
// Unreliable이고 대역폭 포화 상태면 그냥 드랍
if (!(Function->FunctionFlags & FUNC_NetReliable) && !Connection->IsNetReady())
    return;  // 전송 포기, 조용히 사라짐
```

Reliable RPC가 버퍼를 초과하면 연결 자체를 끊는다 (NetDriver.cpp:3152).

```
Reliable 버퍼 오버플로우:
  → NMT_Failure 메시지 전송
  → Connection->Close()  ← 연결 종료
```

| | Reliable | Unreliable |
|---|---|---|
| 도착 보장 | O (재전송) | X |
| 대역폭 포화 시 | 버퍼에 쌓음 (초과 시 연결 끊음) | 조용히 드랍 |
| 용도 | 중요한 게임 이벤트 (스킬, 구매, 사망) | 빈번한 이펙트 (발소리, 파티클) |

---

## Multicast의 특수 동작

Unreliable Multicast는 즉시 전송하지 않고 틱 끝에 일괄 처리한다.

```cpp
// NetDriver.cpp:3228
bool QueueBunch = (!Bunch.bReliable && Function->FunctionFlags & FUNC_NetMulticast);

if (QueueBunch)
    Ch->WriteFieldHeaderAndPayload(...);  // 큐에 추가, 이번 틱 끝에 SendBunch
else
    Ch->SendBunch(&Bunch, ...);           // 즉시 전송
```

같은 틱에 Multicast를 여러 번 호출해도 하나의 패킷에 묶어서 전송된다.

---

## 주의사항

### 1. Server RPC는 bReplicates=true인 Actor에서만 동작한다

```cpp
// Actor.cpp:5597
if (RemoteRole == ROLE_None)
{
    UE_LOG(LogNet, Warning, TEXT("Client is absorbing remote function %s on actor %s because RemoteRole is ROLE_None"));
    return FunctionCallspace::Absorbed;  // 조용히 무시
}
```

`bReplicates=false`면 `RemoteRole=ROLE_None` → RPC가 도달하지 않는다.

### 2. Client RPC는 Owner가 있어야 한다

`Client` RPC는 Actor를 소유한 PlayerController의 연결로 전송된다.  
Owner가 없는 Actor에서 Client RPC를 쏘면 Absorbed (무시)된다.

### 3. Server RPC는 클라이언트에서 호출해도 서버에서 실행된다

함수 본체는 서버에서만 실행되므로, 클라이언트에서 `_Implementation` 안에 `HasAuthority()` 체크가 없어도 된다. 이미 서버에서 실행 중이다.

### 4. Unreliable RPC는 호출해도 도착하지 않을 수 있다

패킷 로스나 대역폭 포화 상태에서는 그냥 드랍된다. 중요한 상태 변경은 반드시 Reliable을 쓰거나 프로퍼티 복제로 처리해야 한다.

### 5. RPC와 프로퍼티 복제를 혼용하는 패턴

서버에서 값을 바꾸고 RPC로 클라이언트에 알리는 것은 중복이다.

```cpp
// ❌ 중복 — OnRep_Health가 이미 클라이언트에 알린다
void AMyActor::TakeDamage(float Amount)
{
    Health -= Amount;       // 복제됨 → OnRep_Health 자동 호출
    ClientPlayHitEffect();  // 이것도 같은 목적이면 중복
}

// ✅ 복제만으로 충분한 경우
UPROPERTY(ReplicatedUsing = OnRep_Health)
float Health;

void AMyActor::OnRep_Health() { PlayHitEffect(); }

// ✅ RPC가 필요한 경우 — 값 변경 없이 이벤트만 전달
UFUNCTION(NetMulticast, Unreliable)
void MulticastExplosionVFX(FVector Location);
```
