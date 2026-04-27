# 언리얼 직렬화 / 역직렬화

> 소스:  
> `Engine/Source/Runtime/Core/Public/Serialization/Archive.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitWriter.h`  
> `Engine/Source/Runtime/Core/Public/Serialization/BitReader.h`  
> `Engine/Source/Runtime/Engine/Public/Net/RepLayout.h`  
> `Engine/Source/Runtime/Engine/Public/GameFramework/FastArraySerializer.h`

서버가 프로퍼티 변경을 감지해서 비트 스트림에 기록하고,
클라이언트가 그 비트 스트림을 읽어 값을 복원하는 전 과정.

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_archive.md](01_archive.md) | FArchive / FBitWriter / FBitReader — 비트 스트림의 기반 추상화 |
| [02_net_serialize.md](02_net_serialize.md) | NetSerialize & TStructOpsTypeTraits — 구조체가 직렬화를 직접 제어하는 방법 |
| [03_rep_layout.md](03_rep_layout.md) | RepLayout & Shadow Buffer — UPROPERTY 자동 복제의 내부 동작 |
| [04_fast_array.md](04_fast_array.md) | FFastArraySerializer — 배열 델타 직렬화, Pre/PostReplicated 콜백 |

---

## 전체 파이프라인 한눈에

```
[서버]
  UPROPERTY 값 변경
    ↓
  RepLayout::CompareProperties()
    현재값 vs Shadow Buffer → 변경된 프로퍼티 목록 작성
    ↓
  각 프로퍼티 직렬화
    ├─ 기본 타입 (int, float, bool ...) → FBitWriter에 직접 기록
    ├─ 구조체 (NetSerialize 있음)       → struct::NetSerialize(Writer, ...)
    ├─ 구조체 (NetSerialize 없음)       → 필드별 재귀 직렬화
    └─ 배열 (FFastArraySerializer)      → FastArrayDeltaSerialize — 변경된 항목만
    ↓
  FOutBunch → UNetConnection → UDP 패킷 전송

[클라이언트]
  UDP 패킷 수신
    ↓
  FInBunch → FBitReader
    ↓
  각 프로퍼티 역직렬화
    ├─ 기본 타입                        → FBitReader에서 직접 읽기
    ├─ 구조체 (NetSerialize 있음)       → struct::NetSerialize(Reader, ...)
    ├─ 구조체 (NetSerialize 없음)       → 필드별 재귀 역직렬화
    └─ 배열 (FFastArraySerializer)      → PreReplicatedRemove / PostReplicatedAdd / PostReplicatedChange 콜백
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
| `NetSerialize` | 구조체가 직접 구현하는 직렬화 함수. `TStructOpsTypeTraits`로 활성화 |
| `FRepLayout` | UPROPERTY(Replicated) 목록 관리, Shadow Buffer 비교, 변경 감지 |
| `FFastArraySerializer` | 배열 항목에 ID를 부여해 변경된 항목만 델타 전송 |
| Pre/PostReplicated | 수신 측 콜백 — 복제 배열로부터 로컬 캐시(TMap 등)를 재건 |
