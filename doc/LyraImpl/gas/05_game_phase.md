# 게임 페이즈 시스템

> 출처:  
> `Source/LyraGame/AbilitySystem/Phases/LyraGamePhaseSubsystem.h`  
> `Source/LyraGame/AbilitySystem/Phases/LyraGamePhaseAbility.h`  
> `Source/LyraGame/GameModes/LyraGameState.h`

---

## 개념

게임 페이즈(웜업 → 플레이 → 포스트게임)를 **GameplayAbility로 표현**한다.

- 페이즈 **시작** = 어빌리티 **활성화**
- 페이즈 **종료** = 어빌리티 **종료**

이 덕분에 페이즈 시작/종료에 GAS의 태그, 이펙트, 이벤트 시스템을 그대로 활용할 수 있다.

---

## 실행 주체

`ALyraGameState`가 보유한 **전용 ASC**에서 페이즈 어빌리티가 실행된다:

```cpp
// LyraGameState.h
class ALyraGameState : public AModularGameStateBase, public IAbilitySystemInterface
{
    TObjectPtr<ULyraAbilitySystemComponent> AbilitySystemComponent;  // 페이즈 GA 실행 주체
};
```

GameState는 서버/클라이언트 양쪽에 존재 → 페이즈 상태가 자연스럽게 복제된다.

---

## ULyraGamePhaseSubsystem

`UWorldSubsystem`을 상속한 월드 서브시스템. 페이즈 전환과 구독을 담당한다.

```cpp
// LyraGamePhaseSubsystem.h
UCLASS()
class ULyraGamePhaseSubsystem : public UWorldSubsystem
{
    // 현재 활성 페이즈: AbilitySpecHandle → (PhaseTag, EndCallback)
    TMap<FGameplayAbilitySpecHandle, FLyraGamePhaseEntry> ActivePhaseMap;

    // 페이즈 시작/종료 구독자
    TArray<FPhaseObserver> PhaseStartObservers;
    TArray<FPhaseObserver> PhaseEndObservers;
};
```

### 페이즈 전환 API

```cpp
// 새 페이즈 시작 (서버 전용)
void StartPhase(TSubclassOf<ULyraGamePhaseAbility> PhaseAbility,
                FLyraGamePhaseDelegate PhaseEndedCallback);

// 페이즈 시작 또는 이미 활성 상태일 때 콜백
void WhenPhaseStartsOrIsActive(FGameplayTag PhaseTag,
                               EPhaseTagMatchType MatchType,
                               const FLyraGamePhaseTagDelegate& WhenPhaseActive);

// 페이즈 종료 시 콜백
void WhenPhaseEnds(FGameplayTag PhaseTag,
                   EPhaseTagMatchType MatchType,
                   const FLyraGamePhaseTagDelegate& WhenPhaseEnd);

bool IsPhaseActive(const FGameplayTag& PhaseTag) const;
```

---

## 태그 계층으로 표현하는 중첩 페이즈

페이즈 태그는 GameplayTag 계층을 그대로 활용한다:

```
GamePhase.Playing              ← 부모 페이즈
  GamePhase.Playing.NormalPlay ← 자식 페이즈
  GamePhase.Playing.SuddenDeath
```

**규칙**: 새 페이즈 시작 시, **조상이 아닌 활성 페이즈는 모두 종료**한다.

```
현재 활성: [GamePhase.Playing, GamePhase.Playing.NormalPlay]
StartPhase(GamePhase.Playing.SuddenDeath) 호출
  → GamePhase.Playing.NormalPlay 종료  (형제 페이즈)
  → GamePhase.Playing 유지             (조상 페이즈)
  → GamePhase.Playing.SuddenDeath 시작
```

---

## 매칭 방식 (EPhaseTagMatchType)

```cpp
UENUM(BlueprintType)
enum class EPhaseTagMatchType : uint8
{
    ExactMatch,   // "A.B" 구독 → "A.B"만 매칭
    PartialMatch, // "A.B" 구독 → "A.B", "A.B.C" 모두 매칭
};
```

---

## ShooterCore 3단계 예시

| 페이즈 | 태그 | 동작 |
|---|---|---|
| 웜업 | `GamePhase.Warmup` | 모든 플레이어에 대미지 면역 GE 적용, 카운트다운 후 종료 |
| 플레이 | `GamePhase.Playing` | 게임 시작, 점수/시간 추적, 조건 충족 시 PostGame 전환 |
| 포스트게임 | `GamePhase.PostGame` | 대미지 면역 재적용, 컨트롤 비활성화, 다음 라운드 전환 |

```
StartPhase(Phase_Warmup)
  → GE_PregameLobby 적용 (대미지 면역)
  → 카운트다운 타이머
  → 타이머 만료 → Phase_Warmup 종료
  → StartPhase(Phase_Playing)
    → GE_PregameLobby 제거
    → 게임 로직 시작
```
