# UGameFrameworkComponent 클래스 계층

> 출처:  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponent.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/PawnComponent.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/ControllerComponent.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/PlayerStateComponent.h`  
> `Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameStateComponent.h`

---

## 클래스 계층

```
UActorComponent
  └─ UGameFrameworkComponent
        ├─ UPawnComponent
        ├─ UControllerComponent
        ├─ UPlayerStateComponent
        └─ UGameStateComponent
```

전체 구조가 동일한 패턴이다 — **"이 Actor에 붙는 컴포넌트라면 이 접근자들이 필요하다"** 를 미리 묶어둔 보일러플레이트 제거 레이어.

---

## UGameFrameworkComponent

**파일**: `GameFrameworkComponent.h`  
**역할**: 게임 프레임워크 Actor(PlayerState, GameState 등)에 붙는 컴포넌트들의 공통 베이스.

`UActorComponent`에서 추가된 것:

| 메서드 | 설명 |
|--------|------|
| `GetGameInstance<T>()` | Owner Actor를 통해 GameInstance에 접근 |
| `GetGameInstanceChecked<T>()` | null 불허 버전 (check() 포함) |
| `HasAuthority()` | Owner의 Role이 `ROLE_Authority`인지 확인 |
| `GetWorldTimerManager()` | 월드 타이머 매니저 반환 |

같은 헤더에 `TComponentIterator<T>` / `TConstComponentIterator<T>` 유틸리티도 정의돼 있다.  
`IsRegistered()` 조건을 걸며 Actor의 등록된 컴포넌트를 순회한다.

### 왜 GetGameInstance가 여기 있나?

`GetGameInstance<T>()`는 특별한 접근 권한을 부여하는 게 아니다. 단순히 긴 접근 체인의 축약형이다.

```cpp
// 원래 코드
GetOwner()->GetWorld()->GetGameInstance<UMyGameInstance>();

// 헬퍼 내부 구현 (그대로임)
AActor* Owner = GetOwner();
return Owner ? Owner->GetGameInstance<T>() : nullptr;
```

**`UActorComponent`에 없는 이유**: `UActorComponent`는 물리/렌더/충돌 등 GameInstance와 전혀 무관한 컴포넌트까지 전부 포함하는 범용 베이스다. 거기에 게임 프레임워크 전용 헬퍼를 넣으면 책임 분리 위반이다.

> **수명 관계**: GameInstance는 레벨 전환에도 살아있는 유일한 전역 객체다. 이 컴포넌트들이 붙는 PlayerState, GameState, Pawn은 모두 GameInstance보다 수명이 짧다. 이 헬퍼는 "수명이 짧은 컴포넌트에서 수명이 긴 전역 객체로 안전하게 올라가는" 관용구를 감싼 것이다.

---

## 서브클래스 전체 목록

| 클래스 | 파일 | Owner 타입 | 추가 접근자 |
|--------|------|-----------|------------|
| `UPawnComponent` | `PawnComponent.h` | `APawn` | `GetPawn`, `GetPlayerState`, `GetController` |
| `UControllerComponent` | `ControllerComponent.h` | `AController` | `GetController`, `GetPawn`, `GetViewTarget`, `GetPlayerState`, `GetPlayer` |
| `UPlayerStateComponent` | `PlayerStateComponent.h` | `APlayerState` | `GetPlayerState`, `GetPawn` |
| `UGameStateComponent` | `GameStateComponent.h` | `AGameStateBase` | `GetGameState`, `GetGameMode` |

---

## UPawnComponent

**파일**: `PawnComponent.h`  
**Owner**: `APawn`

`UGameFrameworkComponent`에서 추가된 것 (모두 template, `TPointerIsConvertibleFromTo` static_assert로 컴파일 타임 타입 안전성 보장):

| 메서드 | 설명 |
|--------|------|
| `GetPawn<T>()` / `GetPawnChecked<T>()` | Owner를 Pawn으로 접근 |
| `GetPlayerState<T>()` | Pawn의 PlayerState 접근. 클라이언트 복제 전 null 가능 |
| `GetController<T>()` | Pawn의 Controller 접근. 클라이언트에서는 보통 null |

---

## UControllerComponent

**파일**: `ControllerComponent.h`  
**Owner**: `AController` (PlayerController / AIController 모두 해당)

접근자 외에 **이벤트 virtual 함수** 두 개:

```cpp
virtual void ReceivedPlayer() {}     // PlayerController의 뷰포트/넷 연결이 완료된 시점
virtual void PlayerTick(float DeltaTime) {}  // PlayerInput이 있는 로컬 PC에서만 매 틱 호출
```

`GetPawnOrViewTarget<T>()` 헬퍼도 있다 — Pawn을 빙의 중이면 Pawn, 아니면 ViewTarget 반환.

---

## UPlayerStateComponent

**파일**: `PlayerStateComponent.h`  
**Owner**: `APlayerState`

접근자 외에 **PlayerState 생명주기 virtual 함수** 두 개:

```cpp
virtual void Reset() {}  // 속성 초기화 (리스폰 등)
virtual void CopyProperties(UPlayerStateComponent* Target) {}  // 비활성 PlayerState로 속성 복사
```

`GetPawn<T>()`은 `GetPlayerStateChecked()->GetPawn<T>()`로 구현되어 있다. 클라이언트에서 복제가 완료되기 전에는 null이다.

---

## UGameStateComponent

**파일**: `GameStateComponent.h`  
**Owner**: `AGameStateBase`

`GetGameMode<T>()`는 `GetOwner()->GetGameMode()`가 아닌 `World->GetAuthGameMode<T>()`를 쓴다. 주석에 이유가 명시돼 있다:

> *"GameState 초기화 중에 GameMode가 null일 수 있어 World에서 직접 가져온다"*

접근자 외에 **매치 생명주기 virtual 함수** 두 개:

```cpp
virtual void HandleMatchHasStarted() {}  // 게임플레이 시작
virtual void HandleMatchHasEnded() {}    // 게임플레이 종료
```
