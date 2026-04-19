# 핵심 클래스 — ASC / PlayerState / GameState

> 출처:  
> `Source/LyraGame/AbilitySystem/LyraAbilitySystemComponent.h/.cpp`  
> `Source/LyraGame/Player/LyraPlayerState.h/.cpp`  
> `Source/LyraGame/GameModes/LyraGameState.h`

---

## 소유 구조 한눈에

```
ALyraPlayerState  ──owns──▶  ULyraAbilitySystemComponent  (Owner)
ALyraCharacter    ──────────────────────────────────────── (Avatar)
ALyraGameState    ──owns──▶  ULyraAbilitySystemComponent  (게임 전역 Cue 전용)
```

ASC가 둘 있다.
- **PlayerState ASC**: 플레이어/봇의 모든 어빌리티·어트리뷰트·이펙트 담당
- **GameState ASC**: GameplayCue 전용 — 게임 전체에 영향을 주는 Cue를 실행할 때 사용

---

## ALyraPlayerState — ASC 소유자

### 왜 Pawn이 아닌 PlayerState에 ASC를 두는가?

Pawn은 죽으면 소멸되고 리스폰 시 새로 생성된다. ASC를 Pawn에 두면 Pawn이 바뀔 때마다 어빌리티·이펙트가 사라진다.

PlayerState는 리스폰 후에도 유지된다. 덕분에:
- 부여된 어빌리티와 이펙트가 폰 교체 후에도 지속
- 게임 페이즈가 바뀌어도 GAS 상태 유지
- 폰이 아직 빙의되지 않은 상태에서도 어빌리티 부여 가능

### ASC 복제 설정

```cpp
// LyraPlayerState.cpp
AbilitySystemComponent->SetReplicationMode(EGameplayEffectReplicationMode::Mixed);
// Mixed: GE는 소유자에게만 전체 복제, 다른 클라이언트에는 최소 복제
// → 자신의 GE 정보만 자세히 받아 네트워크 최적화

SetNetUpdateFrequency(100.0f);  // ASC 상태 변화를 빠르게 반영
```

### Avatar 초기화 — 폰 빙의 시

폰 빙의 시 `ULyraPawnExtensionComponent::InitializeAbilitySystem()`이 Owner/Avatar를 연결한다:

```cpp
// LyraPawnExtensionComponent.cpp
void ULyraPawnExtensionComponent::InitializeAbilitySystem(
    ULyraAbilitySystemComponent* InASC, AActor* InOwnerActor)
{
    // Owner = PlayerState, Avatar = 현재 Pawn
    AbilitySystemComponent->InitAbilityActorInfo(InOwnerActor, GetOwner());
}
```

폰이 교체되거나 빙의 해제 시 `UninitializeAbilitySystem()`으로 Avatar를 해제한다.

---

## ALyraGameState — 게임 전역 ASC

```cpp
// LyraGameState.h
class ALyraGameState : public AModularGameStateBase, public IAbilitySystemInterface
{
    // 게임 페이즈 어빌리티 실행 + 전역 GameplayCue 전용
    UPROPERTY(VisibleAnywhere, Category = "Lyra|GameState")
    TObjectPtr<ULyraAbilitySystemComponent> AbilitySystemComponent;
};
```

`IAbilitySystemInterface`를 구현하므로 어디서든 접근 가능:

```cpp
UAbilitySystemBlueprintLibrary::GetAbilitySystemComponent(GameState);
// 또는
GameState->GetLyraAbilitySystemComponent();
```

**주요 용도:**
- **GameplayCue 브로드캐스트**: 특정 플레이어가 아닌 월드 전체에 Cue를 실행
- **게임 페이즈 어빌리티 실행**: `ULyraGamePhaseSubsystem::StartPhase()`가 이 ASC를 통해 페이즈 GA를 활성화

실제 `StartPhase()`에서 GameState ASC를 가져오는 코드:

```cpp
// LyraGamePhaseSubsystem.cpp
void ULyraGamePhaseSubsystem::StartPhase(TSubclassOf<ULyraGamePhaseAbility> PhaseAbility, ...)
{
    ULyraAbilitySystemComponent* GameState_ASC =
        World->GetGameState()->FindComponentByClass<ULyraAbilitySystemComponent>();

    FGameplayAbilitySpec PhaseSpec(PhaseAbility, 1, 0, this);
    FGameplayAbilitySpecHandle SpecHandle = GameState_ASC->GiveAbilityAndActivateOnce(PhaseSpec);
}
```
