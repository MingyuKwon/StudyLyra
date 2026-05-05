# Player 프레임워크 — PlayerController · LocalPlayer

> 소스: `Source/LyraGame/Character/LyraHeroComponent.cpp`

PlayerController와 LocalPlayer는 "플레이어"를 표현하는 두 레이어다.
둘이 분리된 이유는 **생존 범위**와 **목적**이 다르기 때문이다.

---

## PlayerController vs LocalPlayer

| | PlayerController | LocalPlayer |
|---|---|---|
| **존재 위치** | 게임 월드 안 (Actor) | 엔진/플랫폼 레이어 (UObject) |
| **생존 범위** | 레벨 전환 시 소멸/재생성 | 게임 실행 내내 유지 |
| **복제(Replication)** | 서버↔클라이언트 복제됨 | 복제 안 됨 (로컬 전용) |
| **역할** | Pawn 조종, 게임 로직 | 뷰포트, 입력 장치, 저장 데이터 |

**PlayerController**는 "게임 세계에서 플레이어의 의지"를 표현한다.
맵이 바뀌면 새로 생성된다.

**LocalPlayer**는 "물리적으로 이 컴퓨터 앞에 앉아 있는 사람"을 표현한다.
맵이 바뀌어도 사라지지 않는다.

---

## 왜 분리했나

### 1. 스플릿스크린

한 머신에 LocalPlayer가 2개 존재할 수 있다.
각 LocalPlayer는 자신의 PlayerController를 따로 가진다.

### 2. 레벨 전환 시 데이터 유지

PC는 레벨 전환 시 소멸되지만 LocalPlayer는 살아있다.
따라서 레벨을 넘어 유지해야 할 설정·데이터는 LocalPlayer에 붙인다.

### 3. 서버에는 LocalPlayer가 없음

전용 서버는 뷰포트가 없으므로 LocalPlayer가 존재하지 않는다.
PC는 서버에도 있지만 LocalPlayer는 로컬 클라이언트 전용이다.

---

## Lyra 코드에서의 사용 예시

```cpp
// LyraHeroComponent.cpp
const ULyraLocalPlayer* LP = Cast<ULyraLocalPlayer>(PC->GetLocalPlayer());
```

PC에서 LocalPlayer를 꺼내는 이유는, **이 머신에서만 존재하는 데이터**
(Enhanced Input 컨텍스트, 입력 설정 등)에 접근하기 위해서다.
그 데이터가 PC가 아닌 LocalPlayer에 붙어 있기 때문이다.

---

## 내 노트

PlayerController 안에서 LocalPlayer를 꺼내는 패턴이 자주 보이면,
그 코드는 "게임 로직"이 아니라 "로컬 머신 전용 데이터"에 접근하는 신호다.
