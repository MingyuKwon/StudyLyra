# World 프레임워크 — UWorld · AWorldSettings · GameMode · GameState

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/WorldSettings.h`  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/GameModeBase.h`  
> `Engine/Source/Runtime/Engine/Classes/GameFramework/GameStateBase.h`  
> `Source/LyraGame/GameModes/LyraWorldSettings.h`  
> `Source/LyraGame/GameModes/LyraGameMode.cpp`  
> `Source/LyraGame/GameModes/LyraGameState.h`

---

## 전체 구조

```
UWorld
  ├─ PersistentLevel
  │    └─ AWorldSettings      ← 레벨 당 하나 존재하는 Actor (설정값 보관함)
  │
  ├─ AuthorityGameMode        ← AGameModeBase  (서버 전용 — 클라이언트에 없음)
  └─ GameState                ← AGameStateBase (서버→클라 복제 — 모두가 가짐)
```

---

## UWorld

월드 그 자체. Actor들의 컨테이너이자 실행 환경.

| 역할 | 설명 |
|------|------|
| Actor 관리 | 모든 Actor를 보유, 틱 실행 |
| 물리 | PhysicsScene 소유 |
| 네트워크 | NetDriver 소유 (복제, RPC) |
| 타이머 | TimerManager 소유 |
| 레벨 스트리밍 | PersistentLevel + StreamingLevels 관리 |

```cpp
GetWorld();                      // UWorld*
GetWorld()->GetWorldSettings();  // AWorldSettings*
GetWorld()->GetAuthGameMode();   // AGameModeBase* (서버에서만 유효)
GetWorld()->GetGameState();      // AGameStateBase*
```

`UWorld`는 `UObject`다 — `AActor`가 아니다. 직접 레벨에 배치되는 것이 아니라 엔진이 내부적으로 생성/소유한다.

---

## AWorldSettings

레벨 당 하나 존재하는 Actor. 에디터의 **World Settings 패널**에서 보이는 값들이 모두 여기에 저장된다.

**담는 것:**
- 중력 스케일, KillZ (낙사 높이)
- 시간 배율 (TimeDilation)
- Lightmass 설정
- 기본 GameMode 클래스 (`DefaultGameMode`)
- Replication 관련 설정 (패킷 손실 시뮬레이션 등)

**핵심 특징:**
- 레벨에 자동으로 배치됨 (직접 배치하는 게 아님)
- `PersistentLevel` 안에 있으며 `GetWorldSettings()`으로 접근
- 서브클래스화해서 게임 전용 설정 추가 가능

---

### AWorldSettings — 이름이 오해를 준다

이름이 "Settings"라 데이터 모음처럼 보이지만, 실제 역할은 **레벨당 하나인 대표 Actor**다.

| 역할 | 내용 |
|------|------|
| 설정값 보관 | 중력, KillZ, TimeDilation 등 |
| 레벨 대표 | 레벨 범위 작업(BeginPlay 트리거 등) 실행 |

`UWorld`는 엔진 내부 클래스라 게임 코드에서 서브클래싱하지 않는다.  
`AWorldSettings`가 "레벨 범위 커스터마이징의 진입점" 역할을 하기 때문에 로직도 들어간다.

---

### 복제(Replicated)되는 프로퍼티

> 출처: `Engine/Source/Runtime/Engine/Private/WorldSettings.cpp:378` (`GetLifetimeReplicatedProps`)

`AWorldSettings` 자체가 `bReplicates = true`인 Actor다.

```cpp
DOREPLIFETIME(AWorldSettings, PauserPlayerState);     // 게임 일시정지한 플레이어
DOREPLIFETIME(AWorldSettings, TimeDilation);          // 월드 시간 배율 (슬로우모션)
DOREPLIFETIME(AWorldSettings, CinematicTimeDilation); // 시퀀서 슬로우모션 배율
DOREPLIFETIME(AWorldSettings, WorldGravityZ);         // 현재 적용 중인 중력값
DOREPLIFETIME(AWorldSettings, bHighPriorityLoading);  // 백그라운드 로딩 우선순위
DOREPLIFETIME_WITH_PARAMS_FAST(AWorldSettings, NaniteSettings, ...); // Nanite 설정
```

이것들은 레벨 파일에서 읽는 정적 설정값이 아니라 **런타임에 서버가 바꾸면 클라이언트에 전파되는 상태**다(`transient` 플래그).

---

### NotifyBeginPlay — 월드 전체 BeginPlay 진입점

> 출처: `Engine/Source/Runtime/Engine/Private/WorldSettings.cpp:353`

```cpp
void AWorldSettings::NotifyBeginPlay()
{
    UWorld* World = GetWorld();
    if (!World->GetBegunPlay())  // 한 번만 실행
    {
        World->OnWorldPreBeginPlay.Broadcast();

        for (FActorIterator It(World); It; ++It)
        {
            It->DispatchBeginPlay(bFromLevelLoad);  // 모든 Actor BeginPlay 호출
        }

        World->SetBegunPlay(true);
    }
}
```

**누가 호출하나** — `AGameStateBase`가 결정하고 `AWorldSettings`가 실행한다:

```cpp
// GameStateBase.cpp

// 서버: 직접 호출
void AGameStateBase::HandleBeginPlay()
{
    bReplicatedHasBegunPlay = true;           // 클라이언트에 복제
    GetWorldSettings()->NotifyBeginPlay();    // 서버 Actor BeginPlay 실행
    GetWorldSettings()->NotifyMatchStarted();
}

// 클라이언트: bReplicatedHasBegunPlay 복제 수신 시 OnRep 콜백
void AGameStateBase::OnRep_ReplicatedHasBegunPlay()
{
    if (bReplicatedHasBegunPlay && GetLocalRole() != ROLE_Authority)
    {
        GetWorldSettings()->NotifyBeginPlay();    // 클라이언트 Actor BeginPlay 실행
        GetWorldSettings()->NotifyMatchStarted();
    }
}
```

흐름:

```
서버: GameStateBase::HandleBeginPlay()
  → WorldSettings::NotifyBeginPlay()
       → 모든 Actor::DispatchBeginPlay()   ← 서버 BeginPlay 실행
  → bReplicatedHasBegunPlay = true → 클라이언트에 복제

클라이언트: bReplicatedHasBegunPlay OnRep 수신
  → WorldSettings::NotifyBeginPlay()
       → 모든 Actor::DispatchBeginPlay()   ← 클라이언트 BeginPlay 실행
```

**왜 WorldSettings가 하는가:**
- `GameStateBase`는 "언제 시작할지" 결정 (게임 타이밍)
- `WorldSettings`는 "어떻게 이 레벨 Actor들을 깨울지" 실행 (레벨 실행)
- 관심사 분리 + 게임 코드에서 `NotifyBeginPlay()`를 오버라이드해 커스터마이징 가능

---

## AGameModeBase (GameMode)

**게임의 규칙을 정의**하는 클래스.

```
서버 전용 — 클라이언트에 존재하지 않는다.
```

| 담당 | 예시 |
|------|------|
| 어떤 Pawn을 스폰할지 | `GetDefaultPawnClassForController()` |
| 어디서 스폰할지 | `ChoosePlayerStart()` |
| 플레이어가 참가할 수 있는지 | `PlayerCanRestart()` |
| GameState 클래스 | `GameStateClass` 멤버로 지정 |
| PlayerState 클래스 | `PlayerStateClass` 멤버로 지정 |

**GameMode 클래스가 결정되는 시점:**  
서버가 맵을 로드할 때 `AWorldSettings::DefaultGameMode`를 읽어 해당 클래스를 인스턴스화한다.

```cpp
// 클라이언트에서 GameMode 접근 → nullptr
AGameModeBase* GM = GetWorld()->GetAuthGameMode();  // 클라이언트면 nullptr
```

---

## AGameStateBase (GameState)

**게임의 현재 상태**를 담는 클래스. 서버가 만들고 모든 클라이언트에 복제된다.

```
서버 + 모든 클라이언트가 보유.
```

| 담당 | 예시 |
|------|------|
| 현재 점수 | `Score`, `TeamScore` |
| 남은 시간 | `RemainingTime` |
| 참가 플레이어 목록 | `PlayerArray` |
| 게임 진행 상태 | 로비/게임중/종료 |

```cpp
AGameStateBase* GS = GetWorld()->GetGameState();  // 서버/클라 모두 유효
```

---

## GameMode vs GameState — 왜 나뉘어 있나

GameMode가 서버 전용인 이유: **게임 규칙은 클라이언트가 알 필요 없다**.  
클라이언트가 "어디서 스폰할지", "누가 참가할 수 있는지"를 알면 치트가 가능하다.

GameState가 복제되는 이유: **현재 상태는 클라이언트도 알아야 한다**.  
점수판, 남은 시간, 팀 정보는 모든 클라이언트 화면에 표시돼야 한다.

```
서버만 필요한 정보  → GameMode
모두가 알아야 하는 정보 → GameState (복제)
```

---

## WorldSettings → GameMode → GameState 생성 체인

```
서버가 맵 로드
  → AWorldSettings::DefaultGameMode 읽음
  → 해당 클래스로 AGameModeBase 인스턴스 생성
  → AGameModeBase::InitGameState()
       → GameStateClass로 AGameStateBase 인스턴스 생성
       → 클라이언트에 복제
  → AGameModeBase::InitGame()
       → 게임 초기화 시작
```

---

## Lyra의 확장 — WorldSettings → Experience 연결

Lyra는 `AWorldSettings`를 서브클래스화해서 **레벨별 기본 Experience**를 설정한다.

```cpp
// ALyraWorldSettings.h
class ALyraWorldSettings : public AWorldSettings
{
    // 이 맵을 열면 기본으로 사용할 Experience (에디터에서 설정)
    TSoftClassPtr<ULyraExperienceDefinition> DefaultGameplayExperience;
};
```

`ALyraGameMode::InitGame()` 에서 Experience를 결정하는 우선순위:

```cpp
// LyraGameMode.cpp:88
void ALyraGameMode::HandleMatchAssignmentIfNotExpectingOne()
{
    // 1순위: URL 파라미터 (?Experience=XXX)        ← 서버 실행 옵션
    // 2순위: DeveloperSettings (PIE 오버라이드)     ← 개발 편의
    // 3순위: 커맨드라인 인자 (-Experience=XXX)      ← 자동화 테스트
    // 4순위: ALyraWorldSettings::DefaultGameplayExperience ← 레벨 설정
    // 5순위: B_LyraDefaultExperience (하드코딩 폴백)

    if (!ExperienceId.IsValid())
    {
        if (ALyraWorldSettings* TypedWorldSettings = Cast<ALyraWorldSettings>(GetWorldSettings()))
            ExperienceId = TypedWorldSettings->GetDefaultGameplayExperience();
    }
}
```

`ALyraGameState`는 `ULyraExperienceManagerComponent`를 들고 있어서, 결정된 Experience를 로드하고 GameFeature 플러그인들을 활성화한다.

```
ALyraWorldSettings::DefaultGameplayExperience
  → ALyraGameMode가 읽어 ExperienceId 결정
  → ALyraGameState::ExperienceManagerComponent가 로드
       → GameFeature 플러그인 활성화
            → ModularGameplay로 컴포넌트 주입
```

---

## 한눈에 비교

| | UWorld | AWorldSettings | AGameModeBase | AGameStateBase |
|--|--------|---------------|--------------|----------------|
| **무엇** | 월드 컨테이너 | 레벨 설정값 | 게임 규칙 | 게임 현재 상태 |
| **타입** | UObject | AActor | AActor | AActor |
| **개수** | 1개 / 게임 | 1개 / 레벨 | 1개 / 서버 | 1개 / 월드 |
| **클라이언트** | 있음 | 있음 | **없음** | 있음 (복제) |
| **결정 시점** | 엔진 시작 시 | 레벨 에디터 | 맵 로드 시 | GameMode가 생성 |
