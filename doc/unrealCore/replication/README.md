# 언리얼 엔진 복제(Replication) 시스템

> 출처:  
> `Engine/Source/Runtime/Engine/Private/NetDriver.cpp`  
> `Engine/Source/Runtime/Engine/Private/DataChannel.cpp`  
> `Engine/Source/Runtime/Engine/Private/DataReplication.cpp`  
> `Engine/Source/Runtime/Engine/Private/RepLayout.cpp`  
> `Engine/Source/Runtime/Engine/Private/ActorReplication.cpp`  
> `Engine/Source/Runtime/Engine/Private/Actor.cpp`

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_pipeline.md](01_pipeline.md) | 복제 전체 파이프라인 — NetDriver Tick → ConsiderList → 우선순위 → ActorChannel |
| [02_actor_replication.md](02_actor_replication.md) | Actor 복제 상세 — bReplicates, Relevancy, Priority, 프로퍼티 Diff, Shadow Buffer |
| [03_rpc.md](03_rpc.md) | RPC — ProcessEvent 흐름, Server/Client/Multicast, Reliable/Unreliable, Validation |
| [04_actor_channel.md](04_actor_channel.md) | UActorChannel — Channel 구조, FObjectReplicator, OpenPacketId, CloseReason별 동작 |

---

## 한 줄 요약

```
서버 매 틱
  → 복제할 Actor 목록 추림 (ConsiderList)
  → 각 클라이언트 연결마다 Relevancy + Priority 정렬
  → ActorChannel::ReplicateActor()
      → 현재값 vs Shadow Buffer 비교
      → 바뀐 프로퍼티만 직렬화 → 패킷 전송
클라이언트 수신
  → 프로퍼티 값 적용
  → OnRep_XXX 콜백 호출
```
