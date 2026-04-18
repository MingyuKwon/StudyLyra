# 언리얼 네트워크 스택 구조

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/NetDriver.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/NetConnection.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/Channel.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/ActorChannel.h`  
> `Engine/Source/Runtime/Engine/Public/Net/DataBunch.h`

---

## 전체 계층 구조

```
UNetDriver
  ├─ ServerConnection  (클라이언트 입장 — 서버와의 연결 1개)
  └─ ClientConnections (서버 입장 — 연결된 클라이언트들)
       ├─ UNetConnection  [클라이언트 A]
       │    ├─ Channels[0]  UControlChannel   연결 제어
       │    ├─ Channels[1]  UVoiceChannel      음성
       │    ├─ Channels[2]  UActorChannel  ── PlayerCharacter
       │    ├─ Channels[3]  UActorChannel  ── Enemy_A
       │    └─ Channels[N]  UActorChannel  ── ...
       │
       └─ UNetConnection  [클라이언트 B]
            ├─ Channels[0]  UControlChannel
            ├─ Channels[2]  UActorChannel  ── PlayerCharacter
            └─ ...
```

각 계층이 하는 일:

| 계층 | 클래스 | 역할 |
|------|--------|------|
| NetDriver | `UNetDriver` | 전체 네트워크 흐름 관리. 매 틱 복제 주도 |
| Connection | `UNetConnection` | 특정 클라이언트와의 연결 1개. 패킷 송수신 |
| Channel | `UChannel` / `UActorChannel` | 연결 안의 논리 레인. Actor 하나 담당 |
| Bunch | `FOutBunch` / `FInBunch` | Channel이 보내는 데이터 단위 |

---

## UNetDriver

```cpp
// NetDriver.h:951
TObjectPtr<UNetConnection> ServerConnection;       // 클라이언트 → 서버 연결
TArray<TObjectPtr<UNetConnection>> ClientConnections; // 서버 → 각 클라이언트 연결들
```

서버 입장에서 `ClientConnections`에 연결된 클라이언트가 쌓인다.  
클라이언트 입장에서 `ServerConnection` 하나만 존재한다.

매 틱 `TickFlush()` → `ServerReplicateActors()`를 호출해서 모든 Connection에 대해 복제를 수행한다.

---

## UNetConnection

```cpp
// NetConnection.h:309
TArray<TObjectPtr<UChannel>> OpenChannels;  // 현재 열려있는 채널 목록

// NetConnection.h:650
TArray<TObjectPtr<UChannel>> Channels;      // ChIndex 기반 인덱스 배열

// NetConnection.h:772
FActorChannelMap ActorChannels;             // Actor → ActorChannel 빠른 조회
```

하나의 Connection은 특정 클라이언트와의 연결 전체를 나타낸다.  
패킷 송수신의 실제 끝점(소켓 레벨)이 여기에 있다.

```cpp
// NetConnection.h:1045
virtual void LowLevelSend(void* Data, int32 CountBits, FOutPacketTraits& Traits);
// FlushNet()이 쌓인 데이터를 UDP 패킷으로 묶어 이 함수로 실제 전송
```

`MaxPacket` — 한 번에 보낼 수 있는 최대 패킷 크기 (기본 약 1400 bytes, MTU 기반).  
Bunch들은 이 크기에 맞게 패킷에 묶인다.

---

## UChannel / UActorChannel

```cpp
// Channel.h:86
int32 ChIndex;          // 이 채널의 인덱스 (Connection 내 고유 번호)

// Channel.h:87
FPacketIdRange OpenPacketId;  // 채널이 열린 패킷 ID (INDEX_NONE = 아직 미개통)

// Channel.h:91
FInBunch* InRec;   // 수신된 신뢰 데이터 큐
FOutBunch* OutRec; // 미확인 송신 신뢰 데이터 큐
```

Channel 타입:

```cpp
// Channel.h:24
enum EChannelType
{
    CHTYPE_Control = 1,  // 연결 제어 (핸드셰이크, 맵 이동 등)
    CHTYPE_Actor   = 2,  // Actor 프로퍼티 + RPC
    CHTYPE_Voice   = 4,  // 음성
};
```

`UActorChannel`은 Actor 1개를 담당한다.  
동일 Actor라도 **Connection마다 별도의 ActorChannel**이 존재한다.

---

## FOutBunch / FInBunch

```cpp
// DataBunch.h:23
class FOutBunch : public FNetBitWriter
{
    int32   ChIndex;      // 어느 채널 소속인지
    int32   ChSequence;   // 이 채널에서의 순서 번호 (Reliable 재전송용)
    int32   PacketId;     // 실제로 실린 UDP 패킷 ID

    uint8   bOpen:1;      // 채널을 여는 Bunch (첫 번째 Bunch)
    uint8   bClose:1;     // 채널을 닫는 Bunch (마지막 Bunch)
    uint8   bReliable:1;  // 신뢰 전송 여부 (ACK 기반 재전송)
    uint8   bPartial:1;   // 분할된 Bunch의 일부 (MTU 초과 시)
};
```

Bunch는 Channel이 전송하는 **논리적 데이터 단위**다.  
실제 UDP 패킷과 1:1이 아니다 — 여러 Bunch가 하나의 UDP 패킷에 묶이거나,  
큰 Bunch 하나가 여러 UDP 패킷으로 분할(`bPartial`)될 수 있다.

---

## 계층 간 데이터 흐름

```
[서버에서 복제/RPC 발생]

UNetDriver::ServerReplicateActors()
  └─ [각 UNetConnection 순회]
       └─ UActorChannel::ReplicateActor()
            └─ FOutBunch 생성 (프로퍼티 직렬화)
                 └─ UChannel::SendBunch()
                      └─ UNetConnection에 누적
                           └─ FlushNet()
                                └─ LowLevelSend()  ← 실제 UDP 전송

[클라이언트에서 수신]

LowLevelReceive() → UDP 패킷 수신
  └─ ReceivedPacket()
       └─ [패킷 안의 Bunch들 파싱]
            └─ ChIndex로 채널 찾기
                 └─ UChannel::ReceivedBunch()
                      └─ UActorChannel::ProcessBunch()
                           ├─ 프로퍼티 적용 + OnRep 호출
                           └─ RPC 실행
```

---

## Bunch와 UDP 패킷의 관계

Bunch와 UDP 패킷은 다른 개념이다.

```
UDP 패킷 (MaxPacket ≈ 1400 bytes)
  ├─ [패킷 헤더]
  ├─ Bunch A  (ChIndex=2, 프로퍼티 복제)
  ├─ Bunch B  (ChIndex=2, RPC)
  └─ Bunch C  (ChIndex=3, 프로퍼티 복제)
```

같은 틱에 여러 채널의 Bunch가 하나의 UDP 패킷에 묶여 전송된다.  
반대로 Bunch가 `MaxPacket`을 초과하면 `bPartial` 플래그로 분할된다.

`FlushNet()`이 누적된 Bunch들을 MTU에 맞게 패킷으로 조립해 `LowLevelSend()`로 보낸다.

---

## Reliable vs Unreliable — Bunch 레벨의 처리

```cpp
// Channel.h:91
FOutBunch* OutRec;  // Reliable Bunch의 미확인 목록
```

Reliable Bunch는 ACK를 받을 때까지 `OutRec`에 보관된다.  
ACK 없이 패킷 로스가 감지되면 `OutRec`의 Bunch를 재전송한다.

Unreliable Bunch는 `OutRec`에 쌓지 않는다. 보내고 끝.

---

## 프로퍼티 복제와 RPC — 같은 채널, 다른 Bunch

자주 생기는 의문: "프로퍼티 복제와 RPC가 같은 채널에 있으면 같은 패킷에 실리나?"

```cpp
// ReplicateActor() 내부 — DataChannel.cpp:3695
FOutBunch Bunch(this, 0);   // 프로퍼티 복제용 Bunch

// ProcessRemoteFunctionForChannelPrivate() 내부 — NetDriver.cpp:3131
FOutBunch Bunch(Ch, 0);     // RPC용 Bunch (별도 생성)
```

**각자 별도의 FOutBunch를 생성한다.**  
같은 `ChIndex`를 달고 같은 Connection에 누적되지만, Bunch 자체는 분리돼 있다.

같은 UDP 패킷에 묶일 수도 있고 아닐 수도 있다 — `FlushNet()`이 MTU에 맞게 조립하는 시점에 결정된다.

```
같은 틱에 발생한 경우 (같은 UDP 패킷에 묶일 가능성):
  Bunch #1 [ChIndex=2, bOpen=1, bReliable=1]  SpawnInfo + 초기 프로퍼티
  Bunch #2 [ChIndex=2, bReliable=1]            RPC "ClientPlayEffect"

다른 틱에 발생한 경우:
  틱 N   UDP 패킷 → Bunch [프로퍼티 변경]
  틱 N+1 UDP 패킷 → Bunch [RPC]
```

> "같은 채널" = 같은 ChIndex를 공유  
> "같은 Bunch" = 같은 FOutBunch 인스턴스  
> 둘은 다른 개념이다.
