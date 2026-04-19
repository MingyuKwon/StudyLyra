# 게임 페이즈 시스템

> 출처:  
> `Source/LyraGame/AbilitySystem/Phases/LyraGamePhaseSubsystem.h/.cpp`  
> `Source/LyraGame/AbilitySystem/Phases/LyraGamePhaseAbility.h`  
> `Source/LyraGame/GameModes/LyraGameState.h`

---

## 개념

게임 페이즈(웜업 → 플레이 → 포스트게임)를 **GameplayAbility로 표현**한다.

- 페이즈 **시작** = 어빌리티 **활성화**
- 페이즈 **종료** = 어빌리티 **종료**

이 덕분에 페이즈 시작/종료에 GAS의 태그, 이펙트, 이벤트 시스템을 그대로 활용할 수 있다.

---

## 실행 주체 — GameState ASC

`ALyraGameState`가 보유한 전용 ASC에서 페이즈 어빌리티가 실행된다:

```cpp
// LyraGamePhaseSubsystem.cpp
void ULyraGamePhaseSubsystem::StartPhase(
    TSubclassOf<ULyraGamePhaseAbility> PhaseAbility,
    FLyraGamePhaseDelegate PhaseEndedCallback)
{
    // GameState에서 ASC 가져옴
    ULyraAbilitySystemComponent* GameState_ASC =
        World->GetGameState()->FindComponentByClass<ULyraAbilitySystemComponent>();

    // 페이즈 어빌리티를 부여하고 즉시 활성화
    FGameplayAbilitySpec PhaseSpec(PhaseAbility, 1, 0, this);
    FGameplayAbilitySpecHandle SpecHandle = GameState_ASC->GiveAbilityAndActivateOnce(PhaseSpec);

    if (FoundSpec && FoundSpec->IsActive())
    {
        FLyraGamePhaseEntry& Entry = ActivePhaseMap.FindOrAdd(SpecHandle);
        Entry.PhaseEndedCallback = PhaseEndedCallback;
    }
    else
    {
        PhaseEndedCallback.ExecuteIfBound(nullptr);  // 활성화 실패 시 콜백
    }
}
```

GameState는 서버/클라이언트 양쪽에 존재하므로 페이즈 상태가 자연스럽게 복제된다.

---

## 태그 계층을 이용한 중첩 페이즈

페이즈 태그는 GameplayTag 계층을 그대로 활용한다:

```
GamePhase.Playing              ← 부모 페이즈
  GamePhase.Playing.NormalPlay ← 자식 페이즈
  GamePhase.Playing.SuddenDeath
```

**규칙**: 새 페이즈 시작 시, **조상이 아닌 활성 페이즈는 모두 종료**한다.

실제 구현:

```cpp
// LyraGamePhaseSubsystem.cpp
void ULyraGamePhaseSubsystem::OnBeginPhase(
    const ULyraGamePhaseAbility* PhaseAbility,
    const FGameplayAbilitySpecHandle PhaseAbilityHandle)
{
    const FGameplayTag IncomingPhaseTag = PhaseAbility->GetGamePhaseTag();

    // 현재 활성 페이즈 전부 순회
    for (const FGameplayAbilitySpec* ActivePhase : ActivePhases)
    {
        const FGameplayTag ActivePhaseTag = CastChecked<ULyraGamePhaseAbility>(ActivePhase->Ability)->GetGamePhaseTag();

        // 새 페이즈 태그가 기존 태그의 부모가 아니면 → 종료
        // 예: 새로 Game.Playing.SuddenDeath가 오면
        //   Game.Playing.NormalPlay → 형제이므로 종료 (MatchesTag 실패)
        //   Game.Playing           → 조상이므로 유지 (MatchesTag 성공)
        if (!IncomingPhaseTag.MatchesTag(ActivePhaseTag))
        {
            FGameplayAbilitySpecHandle HandleToEnd = ActivePhase->Handle;
            GameState_ASC->CancelAbilitiesByFunc([HandleToEnd](
                const ULyraGameplayAbility* LyraAbility,
                FGameplayAbilitySpecHandle Handle)
            {
                return Handle == HandleToEnd;
            }, true);
        }
    }

    // 새 페이즈 등록
    FLyraGamePhaseEntry& Entry = ActivePhaseMap.FindOrAdd(PhaseAbilityHandle);
    Entry.PhaseTag = IncomingPhaseTag;

    // 구독자들에게 페이즈 시작 알림
    for (const FPhaseObserver& Observer : PhaseStartObservers)
    {
        if (Observer.IsMatch(IncomingPhaseTag))
            Observer.PhaseCallback.ExecuteIfBound(IncomingPhaseTag);
    }
}
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

실제 `IsMatch()` 구현:

```cpp
// LyraGamePhaseSubsystem.cpp
bool ULyraGamePhaseSubsystem::FPhaseObserver::IsMatch(const FGameplayTag& ComparePhaseTag) const
{
    switch(MatchType)
    {
    case EPhaseTagMatchType::ExactMatch:
        return ComparePhaseTag == PhaseTag;           // 정확히 같은 태그
    case EPhaseTagMatchType::PartialMatch:
        return ComparePhaseTag.MatchesTag(PhaseTag);  // 부모 태그도 매칭
    }
    return false;
}
```

---

## 페이즈 구독 API

```cpp
// 페이즈가 시작될 때 (또는 이미 활성 상태면 즉시) 콜백
void WhenPhaseStartsOrIsActive(FGameplayTag PhaseTag, EPhaseTagMatchType MatchType, ...);

// 페이즈가 종료될 때 콜백
void WhenPhaseEnds(FGameplayTag PhaseTag, EPhaseTagMatchType MatchType, ...);
```

`WhenPhaseStartsOrIsActive()`는 **이미 활성 상태면 즉시 콜백**한다 — 늦게 구독해도 놓치지 않음:

```cpp
// LyraGamePhaseSubsystem.cpp
void ULyraGamePhaseSubsystem::WhenPhaseStartsOrIsActive(
    FGameplayTag PhaseTag, EPhaseTagMatchType MatchType,
    const FLyraGamePhaseTagDelegate& WhenPhaseActive)
{
    FPhaseObserver Observer;
    Observer.PhaseTag = PhaseTag;
    Observer.MatchType = MatchType;
    Observer.PhaseCallback = WhenPhaseActive;
    PhaseStartObservers.Add(Observer);

    if (IsPhaseActive(PhaseTag))          // 이미 활성 상태면
        WhenPhaseActive.ExecuteIfBound(PhaseTag);  // 즉시 콜백
}
```

---

## 페이즈 종료 처리

```cpp
// LyraGamePhaseSubsystem.cpp
void ULyraGamePhaseSubsystem::OnEndPhase(
    const ULyraGamePhaseAbility* PhaseAbility,
    const FGameplayAbilitySpecHandle PhaseAbilityHandle)
{
    const FGameplayTag EndedPhaseTag = PhaseAbility->GetGamePhaseTag();

    // StartPhase 호출자가 등록한 종료 콜백 실행
    const FLyraGamePhaseEntry& Entry = ActivePhaseMap.FindChecked(PhaseAbilityHandle);
    Entry.PhaseEndedCallback.ExecuteIfBound(PhaseAbility);

    ActivePhaseMap.Remove(PhaseAbilityHandle);

    // 페이즈 종료 구독자들에게 알림
    for (const FPhaseObserver& Observer : PhaseEndObservers)
    {
        if (Observer.IsMatch(EndedPhaseTag))
            Observer.PhaseCallback.ExecuteIfBound(EndedPhaseTag);
    }
}
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
  → GiveAbilityAndActivateOnce(Phase_Warmup, GameState_ASC)
  → Phase_Warmup::ActivateAbility()
      → GlobalAbilitySystem::ApplyEffectToAll(GE_PregameLobby)  // 전원 면역
      → 카운트다운 타이머
  → 타이머 만료 → Phase_Warmup::EndAbility()
      → OnEndPhase() 호출
  → StartPhase(Phase_Playing)
      → OnBeginPhase() → Phase_Warmup이 조상 아님 → 이미 종료됨
      → Phase_Playing 시작
```
