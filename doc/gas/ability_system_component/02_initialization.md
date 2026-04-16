# ASC 초기화 흐름

> 소스: `LyraPawnExtensionComponent.h/cpp`, `LyraPlayerState.cpp`, `LyraAbilitySystemComponent.cpp`

---

## InitAbilityActorInfo 호출 시점

GAS 기본 규칙: Owner와 Avatar를 연결하는 `InitAbilityActorInfo(Owner, Avatar)`를 반드시 호출해야 한다.

| 위치 | 시점 | 이유 |
|---|---|---|
| **서버** | `Possess()` 또는 `BeginPlay()` | 서버가 먼저 Pawn을 소유 |
| **클라이언트** | `OnRep_PlayerState()` | PlayerState는 복제로 도착하므로 OnRep에서 처리 |

---

## Lyra의 초기화 상태 머신

`ULyraPawnExtensionComponent`가 `IGameFrameworkInitStateInterface`를 구현해
여러 컴포넌트의 초기화 순서를 조율한다.

### 상태 체인 (StateChain)

```cpp
static const TArray<FGameplayTag> StateChain = {
    LyraGameplayTags::InitState_Spawned,
    LyraGameplayTags::InitState_DataAvailable,
    LyraGameplayTags::InitState_DataInitialized,
    LyraGameplayTags::InitState_GameplayReady
};
```

### 상태 전이 조건

```
[없음] → InitState_Spawned
    조건: Pawn이 유효하게 존재

Spawned → InitState_DataAvailable
    조건: PawnData가 설정됨
          Authority 또는 로컬 컨트롤: Controller가 있음

DataAvailable → InitState_DataInitialized
    조건: 모든 Feature(컴포넌트)가 DataAvailable에 도달
          (LyraHeroComponent, LyraHealthComponent 등 포함)

DataInitialized → InitState_GameplayReady
    조건: 항상 true (즉시 전이)
```

### 핵심 코드

```cpp
// LyraPawnExtensionComponent.cpp
void ULyraPawnExtensionComponent::BeginPlay()
{
    Super::BeginPlay();
    BindOnActorInitStateChanged(NAME_None, FGameplayTag(), false);  // 모든 Feature 변경 감시
    ensure(TryToChangeInitState(LyraGameplayTags::InitState_Spawned));
    CheckDefaultInitialization();
}

bool ULyraPawnExtensionComponent::CanChangeInitState(...) const
{
    if (CurrentState == Spawned && DesiredState == DataAvailable)
    {
        if (!PawnData) return false;   // PawnData 필수
        if (bHasAuthority || bIsLocallyControlled)
            if (!GetController<AController>()) return false;  // Controller 필수
        return true;
    }
    else if (CurrentState == DataAvailable && DesiredState == DataInitialized)
    {
        // 모든 Feature가 DataAvailable에 도달했는지 확인
        return Manager->HaveAllFeaturesReachedInitState(Pawn, DataAvailable);
    }
    // ...
}
```

---

## InitializeAbilitySystem() 호출

`DataInitialized` 상태 진입 시 `LyraHeroComponent`가 `InitializeAbilitySystem()`을 호출한다.

```cpp
// LyraPawnExtensionComponent::InitializeAbilitySystem()
void ULyraPawnExtensionComponent::InitializeAbilitySystem(
    ULyraAbilitySystemComponent* InASC, AActor* InOwnerActor)
{
    // 기존 Avatar 제거 (라그로 인한 중복 상황 처리)
    AActor* ExistingAvatar = InASC->GetAvatarActor();
    if (ExistingAvatar && ExistingAvatar != Pawn)
    {
        if (ULyraPawnExtensionComponent* OtherExt = FindPawnExtensionComponent(ExistingAvatar))
            OtherExt->UninitializeAbilitySystem();
    }

    AbilitySystemComponent = InASC;
    
    // 핵심: InitAbilityActorInfo 호출
    AbilitySystemComponent->InitAbilityActorInfo(InOwnerActor, Pawn);

    // PawnData에서 TagRelationshipMapping 설정
    if (ensure(PawnData))
        InASC->SetTagRelationshipMapping(PawnData->TagRelationshipMapping);

    OnAbilitySystemInitialized.Broadcast();
}
```

---

## InitAbilityActorInfo 실행 내용

```cpp
// LyraAbilitySystemComponent::InitAbilityActorInfo()
void ULyraAbilitySystemComponent::InitAbilityActorInfo(AActor* InOwnerActor, AActor* InAvatarActor)
{
    const bool bHasNewPawnAvatar = Cast<APawn>(InAvatarActor) && (InAvatarActor != ActorInfo->AvatarActor);
    
    Super::InitAbilityActorInfo(InOwnerActor, InAvatarActor);
    
    if (bHasNewPawnAvatar)
    {
        // 1. 모든 기존 GA 인스턴스에게 새 Pawn Avatar 알림
        for (const FGameplayAbilitySpec& AbilitySpec : ActivatableAbilities.Items)
        {
            for (UGameplayAbility* AbilityInstance : AbilitySpec.GetAbilityInstances())
            {
                ULyraGameplayAbility* LyraAbility = Cast<ULyraGameplayAbility>(AbilityInstance);
                if (LyraAbility)
                    LyraAbility->OnPawnAvatarSet();  // → K2_OnPawnAvatarSet() BP 이벤트
            }
        }
        
        // 2. GlobalAbilitySystem에 등록
        if (ULyraGlobalAbilitySystem* GlobalASys = GetWorld()->GetSubsystem<ULyraGlobalAbilitySystem>())
            GlobalASys->RegisterASC(this);
        
        // 3. AnimInstance 초기화
        if (ULyraAnimInstance* LyraAnimInst = Cast<ULyraAnimInstance>(ActorInfo->GetAnimInstance()))
            LyraAnimInst->InitializeWithAbilitySystem(this);
        
        // 4. OnSpawn 정책 GA 자동 활성화
        TryActivateAbilitiesOnSpawn();
    }
}
```

---

## UninitializeAbilitySystem() — 언제 호출되나

```cpp
// Pawn이 죽거나 리스폰될 때
void ULyraPawnExtensionComponent::UninitializeAbilitySystem()
{
    if (AbilitySystemComponent->GetAvatarActor() == GetOwner())
    {
        // 사망 생존 태그를 가진 GA는 취소하지 않음
        FGameplayTagContainer AbilityTypesToIgnore;
        AbilityTypesToIgnore.AddTag(LyraGameplayTags::Ability_Behavior_SurvivesDeath);
        
        AbilitySystemComponent->CancelAbilities(nullptr, &AbilityTypesToIgnore);
        AbilitySystemComponent->ClearAbilityInput();
        AbilitySystemComponent->RemoveAllGameplayCues();
        AbilitySystemComponent->SetAvatarActor(nullptr);
        
        OnAbilitySystemUninitialized.Broadcast();
    }
    AbilitySystemComponent = nullptr;
}
```
