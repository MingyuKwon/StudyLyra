# FRepLayout & Shadow Buffer

> 소스:  
> `Engine/Source/Runtime/Engine/Public/Net/RepLayout.h`  
> `Engine/Source/Runtime/Engine/Private/Net/RepLayout.cpp`

`UPROPERTY(Replicated)`를 선언하면 엔진이 자동으로 복제한다.
FRepLayout이 프로퍼티 목록을 관리하고, Shadow Buffer가 변경을 감지한다.

---

## FRepLayout — 복제 프로퍼티 레이아웃

클래스마다 `FRepLayout` 하나가 생성된다.
"어떤 프로퍼티를, 어떤 순서로, 어떤 방식으로 직렬화할지"를 담는 메타데이터 구조체다.

```
FRepLayout
  ├─ Parents[]  — 최상위 UPROPERTY 목록 (Health, Position 등)
  ├─ Cmds[]     — 실제 직렬화 명령 목록 (중첩 구조체는 리프 필드로 재귀 전개됨)
  └─ Offsets    — 각 프로퍼티의 메모리 오프셋
```

`Cmds[]`에 들어가는 커맨드 타입:

| 타입 | 직렬화 방식 |
|------|------------|
| `REPCMD_Property` | 기본 타입 (int, float 등) |
| `REPCMD_PropertyBool` | bool — 1비트 |
| `REPCMD_PropertyObject` | UObject 포인터 — PackageMap GUID |
| `REPCMD_PropertyString` | FString — 가변 길이 |
| `REPCMD_PropertyNetSerialize` | `WithNetSerializer = true` 구조체 — 커스텀 NetSerialize |
| `REPCMD_DynamicArray` | TArray — 배열 전용 처리 |
| `REPCMD_Return` | 구조체/배열 끝 마커 |

엔진 시작 시 클래스별 `FRepLayout`이 한 번 빌드되고, 이후 모든 복제에서 재사용된다.

---

## Shadow Buffer — 변경 감지

`FObjectReplicator`는 각 클라이언트 연결마다 복제 프로퍼티의 **이전 값 복사본**을 보관한다.
이것이 Shadow Buffer다.

```
실제 Actor 메모리:  Health = 80,  Position = (100, 200, 0)
Shadow Buffer:      Health = 90,  Position = (100, 200, 0)
                           ↑ 다름  → 이 틱에 Health 전송
```

매 틱 `CompareProperties()`가 실제 메모리와 Shadow Buffer를 비교한다.

```cpp
// RepLayout.cpp (간략화)
for (const FRepLayoutCmd& Cmd : Cmds)
{
    if (memcmp(Data + Cmd.Offset, Shadow + Cmd.Offset, Cmd.ElementSize) != 0)
    {
        Tracker.MarkChanged(Cmd.RelativeHandle);  // 바뀐 것만 표시
    }
}
```

변경된 핸들만 `FBitWriter`에 기록해서 전송한다.
전송 후 Shadow Buffer를 현재값으로 갱신한다. 다음 틱에는 이 값과 비교한다.

Shadow Buffer는 **연결(Connection)마다 독립적으로** 존재한다.
클라이언트 A가 느린 연결이면 그쪽 Shadow가 더 오래된 값을 들고 있고,
A에게는 더 많은 변경이 누적되어 다음 전송 때 더 많이 보낼 수 있다.

---

## 핸들 번호 — 어떤 프로퍼티인지 식별

`FRepLayout`은 각 Cmd에 **핸들 번호**를 부여한다.
네트워크로는 프로퍼티 이름이 아닌 핸들 번호를 전송한다.

```
핸들 1: Health        (4바이트 float)
핸들 2: Stamina       (4바이트 float)
핸들 3: Position.X    (4바이트 float)
핸들 4: Position.Y    (4바이트 float)
핸들 5: Position.Z    (4바이트 float)
핸들 6: bIsAlive      (1비트 bool)
```

`Health`만 바뀌었다면: `[핸들=1][값=80][종료 핸들=0]` — 이름 문자열 없이 몇 비트만 전송.

핸들 번호는 클래스의 UPROPERTY 선언 순서와 구조에서 결정론적으로 생성된다.
서버/클라이언트가 같은 코드로 빌드됐다면 양쪽의 핸들 번호가 일치한다.
빌드가 다르면 핸들이 어긋나 엉뚱한 프로퍼티에 값이 적용된다.
