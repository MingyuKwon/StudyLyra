# 언리얼 직렬화 / 역직렬화

> 소스:  
> `Engine/Source/Runtime/Core/Public/Serialization/Archive.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitWriter.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitReader.h`  
> `Engine/Source/Runtime/Engine/Public/Net/RepLayout.h`  
> `Engine/Source/Runtime/Engine/Public/GameFramework/FastArraySerializer.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyBaseObject.cpp`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/PropertyStruct.cpp`

서버가 프로퍼티 변경을 감지해서 비트 스트림에 기록하고,
클라이언트가 그 비트 스트림을 읽어 값을 복원하는 전 과정.

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_archive.md](01_archive.md) | FArchive / FBitWriter / FBitReader — 비트 스트림의 기반 추상화 |
| [02_net_serialize.md](02_net_serialize.md) | NetSerialize & TStructOpsTypeTraits — 구조체가 직렬화를 직접 제어하는 방법, UPROPERTY 없는 필드도 직렬화 가능한 이유 |
| [03_rep_layout.md](03_rep_layout.md) | FRepLayout & Shadow Buffer — Cmds[] 구조, 변경 감지, 핸들 번호 |
| [04_actor_replication.md](04_actor_replication.md) | Actor 복제 호출 체인 — GetLifetimeReplicatedProps, OnRep, 사용자 제어 포인트, Actor에 NetSerialize가 없는 이유, Actor vs UObject 서브오브젝트 채널 차이 |
| [05_fast_array.md](05_fast_array.md) | FFastArraySerializer — 배열 델타 직렬화, Pre/PostReplicated 콜백 |

---

## USTRUCT vs UObject — 직렬화 방식의 근본 차이

`NetSerialize`는 **값 타입(USTRUCT)** 전용이다.
UObject는 이 메커니즘이 없고 항상 **참조(GUID)** 로 전송된다.

### USTRUCT — 값 인라인 직렬화

구조체는 데이터 자체가 Bunch 안에 직접 쓰인다.

```
[FOutBunch 스트림]
  ...
  [Health: 4바이트]
  [Position.X: 4바이트]
  [Position.Y: 4바이트]
  [Position.Z: 4바이트]
  ...
```

커스텀 `NetSerialize`가 있으면 함수가 직접 비트를 제어한다.
없으면 RepLayout이 UPROPERTY 필드를 재귀 전개해 리프 타입별로 직렬화한다.

### UObject 포인터 — GUID 참조

`UPROPERTY() AActor* Target`처럼 UObject 포인터가 UPROPERTY 프로퍼티로 있을 때,
전송되는 것은 Target의 내용이 아니라 **FNetworkGUID(32비트 ID)** 하나다.

```cpp
// PropertyBaseObject.cpp:169
bool FObjectPropertyBase::NetSerializeItem(FArchive& Ar, UPackageMap* Map, void* Data, ...) const
{
    UObject* Object = GetObjectPropertyValue(Data);
    Map->SerializeObject(Ar, PropertyClass, Object);
    // 쓰기: Object 포인터 → GUID 변환 후 Ar에 기록
    // 읽기: Ar에서 GUID 읽기 → 로컬에서 오브젝트 재조회 → Object 포인터 설정
}
```

```
[FOutBunch 스트림]
  ...
  [Target GUID: 4바이트]   ← Target->Health, Position 등은 없음
  ...
```

받는 쪽은 GUID로 자신의 로컬 오브젝트 테이블에서 해당 Actor를 찾아 포인터를 채운다.
GUID가 아직 알려지지 않은 오브젝트를 가리키면 포인터는 null로 처리되다가 나중에 매핑된다.

### Actor/UObject 인스턴스 — 별도 채널

Actor 자신의 UPROPERTY(Replicated) 필드들은 위 두 방식과 별개다.
Actor는 자신만의 `UActorChannel`을 가지고, 거기서 자신의 RepLayout으로 독립적으로 복제된다.

```
UNetConnection
  ├─ UActorChannel [PlayerCharacter]
  │    → PlayerCharacter의 UPROPERTY(Replicated) 필드들을 자체 RepLayout으로 복제
  │       Health, Position 등이 여기서 처리됨
  │
  └─ UActorChannel [Enemy_A]
       → Enemy_A의 UPROPERTY(Replicated) 필드들을 자체 RepLayout으로 복제
```

PlayerCharacter가 다른 Actor에게 `UPROPERTY() AActor* Target = Enemy_A`를 복제할 때:
- `Target` 포인터 자체 → Enemy_A의 GUID(4바이트)로 전송 (PlayerCharacter 채널)
- Enemy_A의 체력·위치 등 → 별도로 Enemy_A 채널에서 전송

### 세 가지 방식 비교

| | USTRUCT 값 | UObject 포인터 | Actor 인스턴스 |
|---|---|---|---|
| 전송 단위 | 구조체 필드 값 | GUID 4바이트 | 각 채널의 RepLayout |
| 내용 인라인 전송 | O | X | X (채널 분리) |
| 커스텀 직렬화 | `NetSerialize` | 불가 | 불가 (프로퍼티 단위만 가능) |
| 전송 주체 | 소유 Actor의 채널 | 소유 Actor의 채널 | 해당 Actor 자체 채널 |

---

## 전체 파이프라인 한눈에

```
[서버]
  UPROPERTY 값 변경
    ↓
  RepLayout::CompareProperties()
    현재값 vs Shadow Buffer → 변경된 프로퍼티 목록 작성
    ↓
  각 프로퍼티 직렬화 (FProperty::NetSerializeItem 가상함수 디스패치)
    ├─ 기본 타입 (int, float, bool ...)  → FBitWriter에 직접 기록
    ├─ UObject 포인터                    → PackageMap::SerializeObject → GUID
    ├─ USTRUCT (NetSerialize 있음)       → struct::NetSerialize(Writer, ...)
    ├─ USTRUCT (NetSerialize 없음)       → UPROPERTY 필드별 재귀 직렬화
    └─ 배열 (FFastArraySerializer)       → FastArrayDeltaSerialize — 변경 항목만
    ↓
  FOutBunch → UNetConnection → UDP 패킷 전송
  (Actor 호출 체인 상세 → 04_actor_replication.md)

[클라이언트]
  UDP 패킷 수신
    ↓
  FInBunch → FBitReader
    ↓
  각 프로퍼티 역직렬화
    ├─ 기본 타입                         → FBitReader에서 직접 읽기
    ├─ UObject 포인터                    → GUID → 로컬 오브젝트 재조회
    ├─ USTRUCT (NetSerialize 있음)       → struct::NetSerialize(Reader, ...)
    ├─ USTRUCT (NetSerialize 없음)       → UPROPERTY 필드별 재귀 역직렬화
    └─ 배열 (FFastArraySerializer)       → PreReplicatedRemove / PostReplicatedAdd / PostReplicatedChange
    ↓
  Shadow Buffer 갱신
  OnRep_XXX 콜백 호출
```

---

## 핵심 개념 한 줄씩

| 개념 | 역할 |
|------|------|
| `FArchive` | 읽기/쓰기 양방향 스트림 추상화. `IsLoading()`으로 방향 구분 |
| `FBitWriter` | 비트 단위 쓰기 버퍼. bool 1비트, 작은 정수 최소 비트 |
| `FBitReader` | 비트 단위 읽기 버퍼. 서버가 쓴 것과 같은 순서·크기로 읽어야 함 |
| `NetSerialize` | USTRUCT가 직접 구현하는 직렬화 함수. `TStructOpsTypeTraits`로 활성화 |
| `FNetworkGUID` | UObject 참조를 네트워크로 전달할 때 쓰는 32비트 ID. PackageMap이 관리 |
| `FRepLayout` | UPROPERTY(Replicated) 목록 관리, Shadow Buffer 비교, 변경 감지 |
| `FFastArraySerializer` | 배열 항목에 ID를 부여해 변경된 항목만 델타 전송 |
| Pre/PostReplicated | 수신 측 콜백 — 복제 배열로부터 로컬 캐시(TMap 등)를 재건 |
