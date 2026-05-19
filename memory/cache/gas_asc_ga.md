# GAS — ASC / GameplayAbility 핵심

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## 1. ASC 소유 구조

- **Owner**: `ALyraPlayerState` — `IAbilitySystemInterface` 구현, `ULyraAbilitySystemComponent` 를 `CreateDefaultSubobject`로 보유
- **Avatar**: `ALyraCharacter` — Owner와 별개. `ULyraPawnExtensionComponent::InitializeAbilitySystem()`에서 `InitAbilityActorInfo(Owner, Avatar)` 호출
- **복제 모드**: `EGameplayEffectReplicationMode::Mixed`
- **업데이트 주기**: `SetNetUpdateFrequency(100.0f)`

---

## 19. InitAbilityActorInfo / InitFromActor 내부 동작

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:140`  
> `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayAbilityTypes.cpp:23`

### InitAbilityActorInfo (AbilitySystemComponent_Abilities.cpp:140)

```cpp
void UAbilitySystemComponent::InitAbilityActorInfo(AActor* InOwnerActor, AActor* InAvatarActor)
{
    AbilityActorInfo->InitFromActor(InOwnerActor, InAvatarActor, this);  // 핵심
    SetOwnerActor(InOwnerActor);
    SetAvatarActor_Direct(InAvatarActor);

    // AvatarActor가 처음 설정된 경우 지연된 GameplayCue 실행
    if ((WasAbilityActorNull || PrevAvatarActor == nullptr) && InAvatarActor != nullptr)
        HandleDeferredGameplayCues(&ActiveGameplayEffects);

    // Avatar 변경 시 모든 GA에 OnAvatarSet 호출
    if (AvatarChanged)
        for (FGameplayAbilitySpec& Spec : ActivatableAbilities.Items)
            Spec.Ability->OnAvatarSet(AbilityActorInfo.Get(), Spec);
}
```

### InitFromActor (GameplayAbilityTypes.cpp:23) — 핵심

네트워크 커넥션을 초기화하는 것이 아니라 **PlayerController 포인터를 AbilityActorInfo에 캐싱**하는 함수.

```cpp
void FGameplayAbilityActorInfo::InitFromActor(AActor* InOwnerActor, AActor* InAvatarActor, ...)
{
    OwnerActor = InOwnerActor;
    AvatarActor = InAvatarActor;

    // OwnerActor에서 시작해 Owner 체인을 타고 올라가며 PlayerController 탐색
    AActor* TestActor = InOwnerActor;
    while (TestActor)
    {
        if (APlayerController* CastPC = Cast<APlayerController>(TestActor))
        {
            PlayerController = CastPC;
            break;
        }
        if (APawn* Pawn = Cast<APawn>(TestActor))
        {
            PlayerController = Cast<APlayerController>(Pawn->GetController());  // ← 핵심
            break;
        }
        TestActor = TestActor->GetOwner();
    }

    // PlayerController를 처음 찾은 경우 ASC에 알림
    if (OldPC == nullptr && PlayerController.IsValid())
        InAbilitySystemComponent->OnPlayerControllerSet();

    // AvatarActor에서 SkeletalMeshComponent, MovementComponent 캐시
    SkeletalMeshComponent = AvatarActorPtr->FindComponentByClass<USkeletalMeshComponent>();
    MovementComponent = AvatarActorPtr->FindComponentByClass<UMovementComponent>();
}
```

### 왜 Controller 설정 이후에 InitAbilityActorInfo를 호출해야 하는가

`PossessedBy()` 이전에 호출하면 `Pawn->GetController()`가 `nullptr` 반환
→ `AbilityActorInfo.PlayerController`가 `nullptr`로 캐시됨
→ 이후 `IsLocallyControlled()` 오작동:

```cpp
bool FGameplayAbilityActorInfo::IsLocallyControlled() const
{
    if (const APlayerController* PC = PlayerController.Get())  // nullptr이면 false 반환
        return PC->IsLocalController();
    ...
}
```

→ 클라이언트 예측 여부, GA 실행 주체 결정 등 GAS 전체 흐름 오작동  
→ `TryActivateAbilitiesOnSpawn()` 시점에도 잘못된 판단으로 OnSpawn GA 오발동 가능

재호출하면 그 시점의 `GetController()`가 유효하므로 캐시 갱신됨 — `OnRep_PlayerState`, `AcknowledgePossession`에서 재호출하는 이유.

### PlayerController 탐색 경로 — 서버와 클라이언트가 다름

**ASC가 Pawn에 있는 경우**  
`InitAbilityActorInfo(Pawn, Pawn)` → `InOwnerActor = Pawn`  
→ `Cast<APawn>(TestActor)` 성공 → `Pawn->GetController()` 로 탐색  
→ `PossessedBy()` 이후에야 `GetController()`가 유효하므로 그 시점에 초기화

**ASC가 PlayerState에 있는 경우**  
`InitAbilityActorInfo(PlayerState, Character)` → `InOwnerActor = PlayerState`  
→ PlayerState는 Pawn도 PlayerController도 아님 → `TestActor = TestActor->GetOwner()` 실행  
→ PlayerState의 `Owner`는 PlayerController (엔진이 PlayerState 생성 시 Controller가 소유)  
→ 한 단계 올라가면 바로 PlayerController 발견

클라이언트 접속 시 생성 순서:
```
1. 클라이언트 접속 요청
2. 서버: GameMode::Login() → 서버 측 PlayerController 생성 (Authority)
3. 서버 신호 → 클라이언트: 로컬 PlayerController 생성 (AutonomousProxy)
4. (한참 뒤) 서버: PlayerState 생성 → 전체 클라이언트에 복제
5. 서버: Pawn 생성 → 복제
```

PlayerController는 PlayerState보다 훨씬 먼저 생긴다.  
`OnRep_PlayerState()` 발동 시점 = PlayerState 복제 완료, 이때 PlayerController는 이미 존재.  
→ `OnRep_PlayerState`를 기다리는 이유는 PlayerState 때문이고, 이 시점에 두 조건 모두 자동 충족.

---

## 37. AbilitySystemGlobals — 역할, 접근, 서브클래싱

**출처**:
- `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AbilitySystemGlobals.h`
- `Source/LyraGame/AbilitySystem/LyraAbilitySystemGlobals.h/.cpp`

### 세 가지 역할

1. **프로젝트 전용 타입 주입** — 가장 중요한 역할
   - GAS 내부가 `FGameplayEffectContext`, `FGameplayAbilityActorInfo` 등을 `AllocXxx()` 가상함수로 new함
   - 서브클래스에서 오버라이드 → 프로젝트 전용 타입으로 교체

2. **공유 리소스 허브** — `GetGameplayCueManager()`, `GetGlobalCurveTable()`, `GetGameplayTagResponseTable()`, `TargetDataStructCache`, `EffectContextStructCache`

3. **전역 실패 태그** — `ActivateFailCooldownTag`, `ActivateFailCostTag`, `ActivateFailTagsBlockedTag` 등

### 접근

```cpp
UAbilitySystemGlobals& Globals = UAbilitySystemGlobals::Get();
// 내부: IGameplayAbilitiesModule::Get().GetAbilitySystemGlobals()
// 게임 전체 싱글톤
```

### Lyra 서브클래싱

`ULyraAbilitySystemGlobals : UAbilitySystemGlobals`
- `AllocGameplayEffectContext()` 하나만 오버라이드 → `new FLyraGameplayEffectContext()` 반환
- `FLyraGameplayEffectContext`는 CartridgeID 등 Lyra 전용 데이터 보유

### 등록 방법

- UE 5.4 이하: `DefaultGame.ini`의 `AbilitySystemGlobalsClassName`
- UE 5.5+: Project Settings → Gameplay Abilities Settings UI

### InitGlobalData()

- UE 5.2 이하: `TargetData` 사용 시 수동 호출 필수 (미호출 시 ScriptStructCache 오류)
- UE 5.3+: 자동 호출

---

## 38. GA Tags — Source / Owner / Target 구분 & 두 실행 경로

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent_Abilities.cpp:1786`
**상세 문서**: `doc/gas_tranek/gameplay_ability/06_tags.md`

### Source / Owner / Target 구분

```cpp
const FGameplayTagContainer* SourceTags = TriggerEventData ? &TriggerEventData->InstigatorTags : nullptr;
const FGameplayTagContainer* TargetTags = TriggerEventData ? &TriggerEventData->TargetTags : nullptr;
```

| 용어 | 실제 데이터 |
|---|---|
| Owner | `ASC->GetOwnedGameplayTags()` — GA 소유 캐릭터 자신의 태그 |
| Source | `FGameplayEventData::InstigatorTags` — 이벤트 발신자 태그 |
| Target | `FGameplayEventData::TargetTags` — 이벤트 대상 태그 |

### 두 실행 경로

**경로 1 — 직접 활성화** (`TryActivateAbilityByClass/Tag/Handle`):
- `InternalTryActivateAbility(..., nullptr, nullptr)` — TriggerEventData = nullptr
- Source/Target = nullptr → Required/Blocked 검사 생략
- 발동 주체가 자기 자신뿐인 경우 (점프, 대쉬, 기본 공격)

**경로 2 — 이벤트 트리거** (`SendGameplayEventToActor`):
- GA `Triggers[]` 배열에 GameplayTag + `TriggerSource = GameplayEvent` 등록 필요
- `SendGameplayEventToActor → HandleGameplayEvent → TriggerAbilityFromGameplayEvent → InternalTryActivateAbility(..., &TriggerEventData)`
- `FGameplayEventData`에 Instigator/Target/TargetData 포함
- Source/Target Required/Blocked Tags 검사 활성화
- 외부 컨텍스트(발신자+대상)가 있는 경우 (처형기, 콤보 연계, 무기 히트 반응)

---

## 25. ULyraAbilityTagRelationshipMapping 전체 흐름

> 출처: `AbilitySystem/LyraAbilityTagRelationshipMapping.h/cpp`, `LyraAbilitySystemComponent.cpp:356,379`, `Abilities/LyraGameplayAbility.cpp:316`, `Character/LyraPawnExtensionComponent.cpp:146`  
> 상세 문서: `doc/LyraImpl/gas/04_tag_systems.md`

### 구조
- DataAsset. 행마다: AbilityTag(키) + AbilityTagsToBlock + AbilityTagsToCancel + ActivationRequiredTags + ActivationBlockedTags
- `ULyraPawnData.TagRelationshipMapping` → `InitializeAbilitySystem()` → `ASC->SetTagRelationshipMapping()`

### 훅 A — CanActivateAbility 체크 (활성화 전)
`DoesAbilitySatisfyTagRequirements` (LyraGA 오버라이드)
→ `GetAdditionalActivationTagRequirements()` (LyraASC)
→ `Mapping.GetRequiredAndBlockedActivationTags(GA의 AbilityTags)`
→ GA 자체 Required/Blocked에 매핑 결과 합산 → ASC 보유 태그 대조

### 훅 B — PreActivate / EndAbility (Block/Cancel 실행)
엔진 `PreActivate()` → `ApplyAbilityBlockAndCancelTags(bEnable=true, bCancel=true)` (LyraASC 오버라이드)
→ `Mapping.GetAbilityTagsToBlockAndCancel(GA의 AbilityTags)` → BlockTags/CancelTags 확장
→ `Super()` → `BlockAbilitiesWithTags(+1)` + `CancelAbilities()`

엔진 `EndAbility()` → `ApplyAbilityBlockAndCancelTags(bEnable=false, bCancel=false)`
→ 동일 매핑 재조회 → `UnBlockAbilitiesWithTags(-1)` 카운터 감소, 취소는 없음
