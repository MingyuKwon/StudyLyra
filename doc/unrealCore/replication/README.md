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
| [00_network_stack.md](00_network_stack.md) | 네트워크 스택 구조 — NetDriver·Connection·Channel·Bunch 계층, 데이터 흐름, Bunch vs UDP 패킷 |
| [01_pipeline.md](01_pipeline.md) | 복제 전체 파이프라인 — NetDriver Tick → ConsiderList → 우선순위 → ActorChannel |
| [02_actor_replication.md](02_actor_replication.md) | Actor 복제 상세 — bReplicates, Relevancy, Priority, 프로퍼티 Diff, Shadow Buffer |
| [03_rpc.md](03_rpc.md) | RPC — ProcessEvent 흐름, Server/Client/Multicast, Reliable/Unreliable, Validation |
| [04_actor_channel.md](04_actor_channel.md) | UActorChannel — Channel 구조, FObjectReplicator, OpenPacketId, CloseReason별 동작 |
| [05_gas_prediction.md](05_gas_prediction.md) | GAS 네트워크 동기화 원칙 — 이벤트성(RPC+예측) vs 상태성(레플리케이션), 취소 방법별 RPC 경로 |
| [net_serialize/](net_serialize/README.md) | 직렬화/역직렬화 — FArchive·FBitWriter/Reader, NetSerialize, TStructOpsTypeTraits, FFastArraySerializer |

---

## 한 줄 요약

```
서버 매 틱
  → 복제할 Actor 목록 추림 (ConsiderList)
  → 각 클라이언트 연결마다 Relevancy + Priority 정렬
  → ActorChannel::ReplicateActor()
      → 현재값 vs Shadow Buffer 비교
      → 바뀐 프로퍼티만 직렬화 (NetSerialize / FBitWriter)
      → Bunch → Packet → UDP 전송
클라이언트 수신
  → FBitReader로 역직렬화
  → 프로퍼티 값 적용
  → OnRep_XXX 콜백 호출
```

---

## 직렬화 계층 요약

```
UPROPERTY 복제
  → RepLayout이 프로퍼티 목록 관리
  → 구조체면 NetSerialize 있으면 호출, 없으면 필드별 자동 직렬화
  → FBitWriter에 비트 단위로 기록 → Bunch → Packet

FFastArraySerializer (배열 델타)
  → 배열 항목별 ID·변경 여부 추적
  → 변경된 항목만 NetDeltaSerialize로 전송
  → 수신 측 Pre/PostReplicated 콜백으로 보조 캐시(TMap 등) 재건
```
