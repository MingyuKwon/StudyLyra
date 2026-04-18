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
