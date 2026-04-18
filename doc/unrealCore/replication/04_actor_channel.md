# UActorChannel — Actor 전용 통신 채널

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/Channel.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/ActorChannel.h`  
> `Engine/Source/Runtime/Engine/Private/DataChannel.cpp`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/CoreNetTypes.h`

---

## 전체 구조 — Connection 안의 Channel들

`UNetConnection`은 서버-클라이언트 간 연결 하나다.  
그 연결 안에 여러 **Channel**이 존재한다.

```cpp
// Channel.h:24
enum EChannelType
{
    CHTYPE_Control = 1,  // 연결 제어 (핸드셰이크, 맵 로드 등)
    CHTYPE_Actor   = 2,  // Actor 프로퍼티 복제 + RPC
    CHTYPE_Voice   = 4,  // 음성 데이터
};
```

Channel은 하나의 연결 안에서 서로 다른 목적의 데이터 흐름을 분리하는 **논리적 레인**이다.

```
서버 ↔ 클라이언트1  (UNetConnection)
  ├─ ControlChannel (ChIndex=0)   핸드셰이크, 연결 관리
  ├─ VoiceChannel  (ChIndex=1)    음성 데이터
  ├─ ActorChannel  (ChIndex=2)    PlayerCharacter 복제 + RPC
  ├─ ActorChannel  (ChIndex=3)    Enemy_A 복제 + RPC
  ├─ ActorChannel  (ChIndex=4)    Pickup_7 복제 + RPC
  └─ ...
```

**복제되는 Actor 하나당 ActorChannel 하나**가 각 클라이언트 연결에 만들어진다.

---

## UActorChannel 클래스 구조

```cpp
// ActorChannel.h:77
UCLASS(transient, customConstructor, MinimalAPI)
class UActorChannel : public UChannel
{
    // 이 채널이 담당하는 Actor
    UPROPERTY()
    TObjectPtr<AActor> Actor;                        // ActorChannel.h:86

    // Actor 복제를 담당하는 메인 Replicator
    TSharedPtr<FObjectReplicator> ActorReplicator;  // ActorChannel.h:130

    // Actor + 모든 서브오브젝트(컴포넌트)의 Replicator 맵
    TMap<UObject*, TSharedRef<FObjectReplicator>> ReplicationMap;  // ActorChannel.h:132

    // 최초 패킷이 실렸던 패킷 ID (INDEX_NONE이면 아직 최초 복제 전)
    FPacketIdRange OpenPacketId;

    // 큐에 쌓인 RPC Bunch (Unreliable Multicast 등)
    TArray<FOutBunch*> QueuedExportBunches;         // ActorChannel.h:152
};
```

---

## 패킷 구조 — 헤더 주석 그대로

`ActorChannel.h:46` 주석이 패킷 포맷을 직접 설명한다.

```
최초 복제 패킷 (bNetInitial=true):
  ┌──────────────────────────┐
  │ SpawnInfo                │ ← 클라이언트가 이 Actor를 스폰할 정보
  │   Actor Class            │   (어떤 클래스인지)
  │   Spawn Location/Rotation│   (어디서 스폰할지)
  │   Actor NetGUID          │   (이 Actor의 네트워크 식별자)
  │   Component NetGUIDs     │   (컴포넌트 식별자들)
  ├──────────────────────────┤
  │ Properties...            │ ← 변경된 프로퍼티 (FObjectReplicator 담당)
  │                          │
  │ RPCs...                  │ ← RPC 데이터도 같은 패킷에 실림
  ├──────────────────────────┤
  │ End Tag                  │
  └──────────────────────────┘

이후 복제 패킷 (bNetInitial=false):
  ┌──────────────────────────┐
  │ NetGUID ObjRef           │ ← 어떤 오브젝트의 데이터인지
  ├──────────────────────────┤
  │ Properties...            │ ← 바뀐 프로퍼티만
  │ RPCs...                  │
  └──────────────────────────┘
```

프로퍼티 복제와 RPC가 **같은 ActorChannel, 같은 패킷** 안에 실린다.  
이 때문에 RPC 전송 코드에서도 `ActorChannel`을 먼저 찾는 것이다.

---

## 생성 — SetChannelActor

`UActorChannel::SetChannelActor()` (DataChannel.cpp:2789)

```cpp
void UActorChannel::SetChannelActor(AActor* InActor, ESetChannelActorFlags Flags)
{
    Actor = InActor;

    // NetConnection의 Actor→Channel 맵에 등록
    Connection->AddActorChannel(Actor, this);  // DataChannel.cpp:2851

    // 이 Actor의 FObjectReplicator 생성 (Shadow Buffer 포함)
    ActorReplicator = FindOrCreateReplicator(Actor);  // DataChannel.cpp:2858
}
```

`FindOrCreateReplicator()` (DataChannel.cpp:5487):

```cpp
TSharedRef<FObjectReplicator>& UActorChannel::FindOrCreateReplicator(UObject* Obj, ...)
{
    // ReplicationMap에 이미 있으면 재사용 (Dormancy에서 깨어날 때)
    TSharedRef<FObjectReplicator>* ReplicatorRefPtr = FindReplicator(Obj);

    if (!ReplicatorRefPtr)
        ReplicatorRefPtr = &CreateReplicator(Obj);  // Shadow Buffer 초기화

    return *ReplicatorRefPtr;
}
```

컴포넌트(SubObject)도 복제 대상이면 별도의 `FObjectReplicator`가 `ReplicationMap`에 추가된다.

---

## FObjectReplicator — 실제 복제 담당

`UActorChannel`은 관리자 역할이고, **실제 프로퍼티 Diff와 직렬화는 `FObjectReplicator`가 한다**.

```
UActorChannel
  ├─ ActorReplicator (FObjectReplicator) — Actor 본체 프로퍼티
  └─ ReplicationMap
       ├─ HealthComponent → FObjectReplicator — 컴포넌트 프로퍼티
       └─ WeaponComponent → FObjectReplicator
```

각 `FObjectReplicator`는:
- 해당 오브젝트의 **Shadow Buffer** 보유 (지난번에 보낸 값 복사본)
- `CompareProperties()` 로 변경 감지
- 변경된 것만 직렬화

---

## 닫힘 — Close와 EChannelCloseReason

`UActorChannel::Close()` (DataChannel.cpp:2397)

```cpp
int64 UActorChannel::Close(EChannelCloseReason Reason)
{
    if (Reason == EChannelCloseReason::Dormancy)
    {
        // Dormancy: 채널은 닫히지만 클라이언트의 Actor는 유지
        // bKeepReplicators=true → Shadow Buffer 보존 (나중에 깨어날 때 재사용)
        bKeepReplicators = true;
        Connection->Driver->NotifyActorFullyDormantForConnection(Actor, Connection);
    }

    Connection->RemoveActorChannel(Actor);
    ReleaseReferences(bKeepReplicators);
}
```

채널이 닫히는 이유별 동작:

```cpp
// CoreNetTypes.h:48
enum class EChannelCloseReason : uint8
{
    Destroyed,      // Actor 파괴 → 클라이언트에서도 DestroyActor
    Dormancy,       // Actor가 잠듦 → 클라이언트 Actor는 유지, 채널만 닫힘
    LevelUnloaded,  // 레벨 언로드
    Relevancy,      // Relevancy 범위 벗어남 → 클라이언트에서 Actor 제거
    TearOff,        // TearOff — 채널 끊고 클라이언트가 독립적으로 시뮬레이션
};
```

| CloseReason | 클라이언트 Actor 운명 |
|-------------|----------------------|
| `Destroyed` | 파괴됨 |
| `Dormancy` | **살아있음** — 채널만 닫힘, 나중에 다시 열 수 있음 |
| `Relevancy` | 파괴됨 (다시 relevant해지면 재스폰) |
| `TearOff` | 살아있음 — 서버와 연결 끊고 클라이언트 로컬로만 존재 |

---

## OpenPacketId — 최초 복제 여부 판단

```cpp
// Channel.h
FPacketIdRange OpenPacketId;  // 최초 open 패킷의 ID 범위
```

`OpenPacketId.First == INDEX_NONE`이면 아직 이 Actor가 클라이언트에 한 번도 복제되지 않은 상태다.

RPC 코드에서 이걸 확인하는 이유:

```cpp
// NetDriver.cpp:3078
if (Ch->OpenPacketId.First == INDEX_NONE)
{
    // 아직 최초 복제가 안 됐으면
    // RPC 보내기 전에 먼저 Actor 복제(스폰 정보)를 해야 함
    Ch->ReplicateActor();  // SpawnInfo + 초기 프로퍼티 전송
}
// 그 다음 RPC 전송
```

클라이언트가 Actor를 모르는 상태에서 RPC만 받으면 실행 대상이 없어 처리 불가하기 때문이다.

---

## 전체 생명주기 요약

```
[Actor가 처음 Relevant해질 때]
  ActorChannel 생성
  SetChannelActor(Actor)
    → Connection에 Actor→Channel 등록
    → FObjectReplicator 생성 (Shadow Buffer 초기화)

[최초 복제]
  ReplicateActor() — bNetInitial=true
    → SerializeNewActor() — 클래스/위치/NetGUID 전송
    → 모든 초기 프로퍼티 직렬화
    → OpenPacketId 기록

[이후 매 복제 주기]
  ReplicateActor() — bNetInitial=false
    → CompareProperties() — Shadow Buffer와 비교
    → 변경된 것만 직렬화 전송

[RPC 발생 시]
  OpenPacketId 확인 → 최초 복제 안 됐으면 먼저 ReplicateActor()
  RPC 파라미터 직렬화 → 같은 채널로 전송

[Actor가 Relevant 범위 벗어나거나 파괴될 때]
  Close(Relevancy 또는 Destroyed)
    → Connection에서 Actor→Channel 매핑 제거
    → FObjectReplicator 해제 (또는 Dormancy면 보존)
    → 클라이언트에 Close 패킷 전송
```
