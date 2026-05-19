# RPC vs Property Replication — Owner/NetConnection 의존성

> 소스:  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`  
> `Engine/Source/Runtime/Engine/Private/NetDriver.cpp`

RPC와 Property Replication은 둘 다 네트워크로 데이터를 전송하지만, **NetConnection을 찾는 방식이 근본적으로 다르다.**
이 차이는 Controller가 없는 NPC나 오브젝트를 다룰 때 중요한 설계 제약이 된다.

> RPC 선언·직렬화·수신 흐름 전체는 [`../replication/03_rpc.md`](../replication/03_rpc.md) 참고.

---

## RPC — Actor가 능동적으로 NetConnection을 찾는다

RPC를 보낼 때 엔진은 `AActor::GetNetConnection()`을 호출해서 "이 RPC를 어느 Connection으로 보낼지"를 결정한다.

```
Actor::GetNetConnection()
  → Owner 있으면: Owner->GetNetConnection() 재귀 호출
  → Owner 없으면: nullptr 반환

재귀의 끝:
  APlayerController::GetNetConnection()
    → 직접 NetConnection 참조를 가지고 있음
```

즉 Owner 체인이 **반드시 PlayerController에서 끝나야** NetConnection이 존재한다.

```
일반 Actor → Owner → ... → PlayerController → NetConnection  ✓
일반 Actor → Owner 없음 → nullptr                              ✗
```

---

## Controller 없는 NPC/오브젝트에서 RPC 동작

AI Pawn은 AIController가 붙어 있지만, AIController는 `GetNetConnection()`에서 `nullptr`을 반환한다.
PlayerController와 달리 클라이언트 연결(NetConnection)을 직접 소유하지 않기 때문이다.
단순한 Prop(상자, 트리거 등)은 Owner 자체가 없다.

| RPC 종류 | 동작 |
|---|---|
| `Server` RPC (클라 → 서버) | GetNetConnection()=nullptr → `Absorbed` (조용히 무시) |
| `Client` RPC (서버 → 특정 클라) | Owner 없으면 전송 대상 Connection을 찾을 수 없음 → `Absorbed` |
| `NetMulticast` (서버 → 전체) | 서버가 `NetDriver`의 **모든** Connection을 순회해서 전송 → **정상 동작** |

```cpp
// Actor.cpp:5613 — CallRemoteFunction
// Client RPC: Actor→GetNetConnection()으로 Connection 단 하나를 찾음
// 없으면 → FunctionCallspace::Absorbed
```

NetMulticast가 정상 동작하는 이유는 "특정 Connection을 찾는" 게 아니라
NetDriver가 **모든 Connection 목록**을 직접 순회하기 때문이다.

---

## Property Replication — NetDriver가 능동적으로 밀어준다

UPROPERTY(Replicated)로 선언된 값의 복제는 방향이 반대다.
Actor가 Connection을 찾는 게 아니라, **NetDriver가 모든 Connection을 순회하며 각자에게 관련 Actor의 변경사항을 밀어넣는다.**

```
매 틱:
NetDriver::ServerReplicateActors()
  → 모든 ClientConnection 순회
      → 각 Connection에서 Relevant한 Actor 목록 결정
          → 각 Actor의 변경된 UPROPERTY 직렬화 + 전송
```

Actor의 Owner가 없어도, PlayerController가 없어도 무관하다.
**"이 Actor가 이 Connection의 클라이언트 시야에 존재하는가(Relevancy)"** 가 기준이다.

---

## GAS가 Property Replication을 쓰는 이유

GAS의 핵심 상태들은 전부 UPROPERTY로 복제된다.

| GAS 데이터 | 복제 방식 |
|---|---|
| `FActiveGameplayEffect` (GE 상태) | `FActiveGameplayEffectsContainer` — `FFastArraySerializer` UPROPERTY |
| Attribute 값 (`Health`, `Stamina` 등) | AttributeSet의 UPROPERTY(Replicated) |
| GameplayCue 태그 | ASC 내부 UPROPERTY 컨테이너 |
| GameplayTag 카운트 | ASC 내부 UPROPERTY 컨테이너 |

덕분에 ASC를 소유한 Actor에 PlayerController가 없어도(AI, 파괴 가능 오브젝트 등) GE 적용 결과, Attribute 변화, GameplayCue가 클라이언트에 정상 복제된다.

```
AI Pawn (PlayerController 없음)
  → Client RPC: 불가 (NetConnection 없음)
  → GE 적용 결과 복제: 가능 (NetDriver가 밀어줌)
  → Attribute 변화 복제: 가능
  → GameplayCue 재생 복제: 가능
```

---

## 정리

| | RPC (Server/Client) | RPC (NetMulticast) | Property Replication |
|---|---|---|---|
| NetConnection 필요 | **필요** (Owner 체인) | 불필요 | **불필요** |
| 전송 주체 | Actor 스스로 | NetDriver (전체 순회) | NetDriver (전체 순회) |
| Controller 없는 Actor | Server/Client 불가 | 정상 | 정상 |
| GAS 상태 전달 | 사용 안 함 | 사용 안 함 | **항상 이 방식** |
