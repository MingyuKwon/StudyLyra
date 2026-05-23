# Player 프레임워크 — ULocalPlayer · PlayerController

> 소스: `C:/UE_5.7/Engine/Source/Runtime/Engine/Classes/Engine/LocalPlayer.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/LocalPlayer.cpp`  
>        `Source/LyraGame/Character/LyraHeroComponent.cpp`

---

## ULocalPlayer란

```
/**
 * Each player that is active on the current client/listen server has a LocalPlayer.
 * It stays active across maps, and there may be several spawned in the case of splitscreen/coop.
 * There will be 0 spawned on dedicated servers.
 */
UCLASS(Within=Engine, config=Engine, transient)
class ULocalPlayer : public UPlayer
```

`ULocalPlayer`는 **물리적으로 이 머신 앞에 앉아있는 플레이어 한 명**을 나타내는 엔진 레이어 객체다.  
Actor가 아닌 `UObject`이며, 게임 월드 밖에 존재한다.

---

## PlayerController vs LocalPlayer

| | `ULocalPlayer` | `APlayerController` |
|---|---|---|
| **타입** | UObject (월드 밖) | AActor (월드 안) |
| **생존 범위** | 게임 실행 내내 유지 | 레벨 전환 시 소멸/재생성 |
| **복제** | 로컬 전용, 복제 안 됨 | 서버↔클라이언트 복제 |
| **담당** | 뷰포트, 입력 장치, Subsystem | Pawn 조종, 게임 로직, 카메라 |
| **서버 존재 여부** | 전용 서버에는 없음 | 서버에도 있음 |

---

## ULocalPlayer가 들고 있는 것

```cpp
// LocalPlayer.h
class ULocalPlayer : public UPlayer
{
    // 뷰포트 — 이 플레이어가 렌더링되는 화면
    TObjectPtr<UGameViewportClient> ViewportClient;

    // 스플릿스크린 화면 분할 영역 (0~1 비율)
    FVector2D Origin;  // 좌상단 좌표
    FVector2D Size;    // 영역 크기

    // 입력 장치 식별
    FPlatformUserId PlatformUserId;  // 어느 물리 유저인가 (패드1, 패드2 등)
    int32 ControllerId;              // 레거시 컨트롤러 ID

    // LocalPlayerSubsystem 모음 — Enhanced Input이 여기 들어있다
    FObjectSubsystemCollection<ULocalPlayerSubsystem> SubsystemCollection;
};
```

`UPlayer`(부모 클래스)가 `PlayerController` 포인터를 들고 있다. `LocalPlayer → PlayerController` 방향으로 접근한다.

---

## 왜 분리했나

### 스플릿스크린

한 머신에 `LocalPlayer`가 2개 존재할 수 있다. 각자 다른 화면 영역(`Origin`/`Size`)을 가지고, 각자의 `PlayerController`를 따로 가진다.

```
GameInstance
    ├─ LocalPlayer[0]   Origin=(0, 0),   Size=(0.5, 1.0)  ← 화면 왼쪽
    │       └─ PlayerController[0]
    └─ LocalPlayer[1]   Origin=(0.5, 0), Size=(0.5, 1.0)  ← 화면 오른쪽
            └─ PlayerController[1]
```

`UGameViewportClient::InputKey()`에서 `GetLocalPlayerFromInputDevice()`를 호출하는 이유가 여기 있다. 패드1 입력이 `LocalPlayer[0]`의 `PlayerController[0]`로 가야 한다.

### 레벨 전환

레벨이 바뀌면 PC는 소멸되고 새로 만들어지지만, `LocalPlayer`는 살아있다.  
레벨을 넘어 유지해야 할 설정·저장 데이터는 `LocalPlayer`에 붙인다.

### 서버에는 없음

전용 서버는 뷰포트가 없으므로 `LocalPlayer`가 없다. `PC`는 서버에도 있지만 `LocalPlayer`는 로컬 클라이언트 전용이다.

---

## ULocalPlayerSubsystem — LocalPlayer에 붙는 Subsystem

`LocalPlayer`는 `SubsystemCollection`을 통해 `ULocalPlayerSubsystem` 인스턴스를 소유한다.

```cpp
// 접근
auto* EnhancedInput = LocalPlayer->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
```

`UEnhancedInputLocalPlayerSubsystem`이 여기 산다. IMC(Input Mapping Context) 관리가 `LocalPlayer` 단위인 이유다 — 스플릿스크린에서 두 플레이어가 서로 다른 IMC 세트를 가질 수 있어야 하기 때문이다.

---

## 입력 장치 매핑

```cpp
// LocalPlayer.h
FPlatformUserId PlatformUserId;  // 물리 유저 식별 (패드 인덱스 등)

FPlatformUserId GetPlatformUserId() const { return PlatformUserId; }
int32 GetPlatformUserIndex() const;   // 0-based 인덱스
int32 GetLocalPlayerIndex() const;    // GameInstance 배열 내 인덱스
```

`PlayerController::InputKey()`에서 아래 필터링이 일어나는 이유:

```cpp
// PlayerController.cpp:2407
if (bFilterInputByPlatformUser &&
    IPlatformInputDeviceMapper::Get().GetUserForInputDevice(Params.InputDevice) != GetPlatformUserId())
    return false;
```

이 PC의 `LocalPlayer`가 소유한 기기에서 온 입력만 허용한다. 패드2 입력이 플레이어1 PC로 들어오는 것을 막는 것이다.

---

## PlayerController 생성 — SpawnPlayActor

`LocalPlayer`가 `PlayerController`를 직접 만든다.

```cpp
// LocalPlayer.cpp
bool ULocalPlayer::SpawnPlayActor(const FString& URL, FString& OutError, UWorld* InWorld)
{
    // GameMode에 요청해서 PC 스폰
    PlayerController = InWorld->SpawnPlayActor(this, ...);
}
```

레벨이 전환될 때마다 `SpawnPlayActor()`가 불려 새 PC가 만들어지고, `LocalPlayer`에 연결된다.

---

## Lyra에서의 사용 패턴

```cpp
// LyraHeroComponent.cpp — Enhanced Input 초기화
APlayerController* PC = GetController<APlayerController>();
const ULyraLocalPlayer* LP = Cast<ULyraLocalPlayer>(PC->GetLocalPlayer());
UEnhancedInputLocalPlayerSubsystem* Subsystem =
    LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();

// IMC 등록 (LocalPlayer 단위)
Subsystem->AddMappingContext(IMC, Priority);
```

`PC->GetLocalPlayer()`로 `LocalPlayer`를 꺼내는 코드가 보이면, "게임 로직"이 아니라 **이 머신 전용 데이터**에 접근하는 신호다.
