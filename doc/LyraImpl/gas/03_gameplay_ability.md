# ULyraGameplayAbility

> 출처: `Source/LyraGame/AbilitySystem/Abilities/LyraGameplayAbility.h/.cpp`

---

## 개요

`UGameplayAbility`를 상속해 Lyra 전용 기능을 추가한 베이스 클래스. 모든 Lyra GA는 이 클래스를 상속한다.

추가된 핵심 기능:
- **활성화 정책** (`ELyraAbilityActivationPolicy`) — 언제 활성화할지
- **활성화 그룹** (`ELyraAbilityActivationGroup`) — 다른 어빌리티와의 관계
- **추가 비용** (`TArray<ULyraAbilityCost*>`) — GE 외 커스텀 비용
- **BP 이벤트 3종** — OnAbilityAdded / OnPawnAvatarSet / OnAbilityRemoved
- **카메라 모드** 오버라이드

---

## 활성화 정책 (ActivationPolicy)

```cpp
// LyraGameplayAbility.h
UENUM(BlueprintType)
enum class ELyraAbilityActivationPolicy : uint8
{
    OnInputTriggered,   // 입력 태그가 트리거될 때 한 번 활성화
    WhileInputActive,   // 입력 태그가 눌린 동안 계속 활성화 시도
    OnSpawn,            // 아바타가 할당되는 즉시 자동 활성화
};
```

| 정책 | 사용 예 | 동작 |
|---|---|---|
| `OnInputTriggered` | ADS, 수류탄 | 버튼을 누르면 한 번 활성화, 자동 재활성화 없음 |
| `WhileInputActive` | 샷건 발사 | 입력이 유지되는 동안 반복 활성화 시도 |
| `OnSpawn` | 자동 재장전 | 폰 빙의 즉시 활성화, 빙의 해제 전까지 유지 |

`OnSpawn`은 `TryActivateAbilityOnSpawn()`에서 처리된다:

```cpp
// LyraGameplayAbility.cpp
void ULyraGameplayAbility::TryActivateAbilityOnSpawn(
    const FGameplayAbilityActorInfo* ActorInfo,
    const FGameplayAbilitySpec& Spec) const
{
    const bool bIsPredicting = (Spec.ActivationInfo.ActivationMode == EGameplayAbilityActivationMode::Predicting);
    if (ActorInfo && !Spec.IsActive() && !bIsPredicting
        && (ActivationPolicy == ELyraAbilityActivationPolicy::OnSpawn))
    {
        ASC->TryActivateAbility(Spec.Handle);
    }
}
```

---

## 활성화 그룹 (ActivationGroup)

```cpp
UENUM(BlueprintType)
enum class ELyraAbilityActivationGroup : uint8
{
    Independent,          // 다른 어빌리티와 무관하게 자유롭게 실행
    Exclusive_Replaceable, // 다른 Exclusive 어빌리티가 활성화되면 취소됨
    Exclusive_Blocking,   // 실행 중 다른 Exclusive 어빌리티 활성화 차단
};
```

| 그룹 | 사용 예 |
|---|---|
| `Independent` | 대부분의 액션 어빌리티 — 사격, 점프 |
| `Exclusive_Replaceable` | 취소 가능한 전용 행동 |
| `Exclusive_Blocking` | 순위표, 인게임 메뉴 — 열려 있는 동안 다른 전용 어빌리티 차단 |

동시성과 취소는 **TagRelationshipMapping**으로 추가 제어한다. (→ [04_tag_systems.md](04_tag_systems.md))

---

## 추가 비용 (AdditionalCosts)

기본 GAS는 GE 하나만 비용으로 지정 가능. Lyra는 `ULyraAbilityCost` 배열로 복수 비용을 지원한다.

```cpp
// LyraGameplayAbility.h
UPROPERTY(EditDefaultsOnly, Instanced, Category = Costs)
TArray<TObjectPtr<ULyraAbilityCost>> AdditionalCosts;
```

표준 `CheckCost` / `ApplyCost` 흐름에 통합되어 있어, 기존 비용 확인/커밋 노드로 그대로 사용된다.

### 구현체

| 클래스 | 동작 |
|---|---|
| `ULyraAbilityCost_ItemTagStack` | 장비 아이템의 특정 GameplayTag 스택 소모. 탄약 소모/재장전에 사용. `Lyra.ShooterGame.Weapon.MagazineAmmo` 스택을 발사마다 감소 |
| `ULyraAbilityCost_InventoryItem` | 인벤토리에서 아이템 소모. 소모품에 사용 |
| `ULyraAbilityCost_PlayerTagStack` | PlayerState의 GameplayTag 스택 소모 |

---

## Blueprint 이벤트 3종

기존 GAS의 `ActivateAbility` / `EndAbility`와 별개로, Lyra가 추가한 생명주기 훅이다.

```cpp
// LyraGameplayAbility.h

// 어빌리티가 ASC에 부여될 때 (아직 Avatar/InputComponent 없을 수 있음)
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnAbilityAdded")
void K2_OnAbilityAdded();

// 폰이 완전히 초기화되고 Avatar + InputComponent 모두 유효할 때
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnPawnAvatarSet")
void K2_OnPawnAvatarSet();

// ASC에서 어빌리티가 제거될 때 (폰 파괴, 빙의 해제 등)
UFUNCTION(BlueprintImplementableEvent, DisplayName = "OnAbilityRemoved")
void K2_OnAbilityRemoved();
```

**사용 패턴**:
- `OnAbilityAdded` → UI 위젯 등록 (익스텐션 핸들 저장)
- `OnPawnAvatarSet` → 폰 의존 초기화 (입력 바인딩, 카메라 설정)
- `OnAbilityRemoved` → UI 위젯 등록 해제, 클린업

---

## 카메라 모드 오버라이드

```cpp
// LyraGameplayAbility.h
void SetCameraMode(TSubclassOf<ULyraCameraMode> CameraMode);
void ClearCameraMode();  // EndAbility 시 자동 호출

TSubclassOf<ULyraCameraMode> ActiveCameraMode;
```

**예시**: `GA_Hero_Death` — 사망 애니메이션 중 특별한 카메라 모드 적용

---

## 주요 네이티브 서브클래스

| 클래스 | 역할 |
|---|---|
| `ULyraGameplayAbility_Death` | 사망 이벤트 트리거, 모든 어빌리티 취소 후 HealthComponent에 사망 시작 알림 |
| `ULyraGameplayAbility_Jump` | 유효한 로컬 제어 폰인지 확인 후 CharacterMovement에 Jump 입력 |
| `ULyraGameplayAbility_Reset` | 폰을 초기 스폰 상태로 즉시 리셋, 모든 어빌리티 취소 |
| `ULyraGameplayAbility_FromEquipment` | 장비 시스템 접근, 관련 아이템 검색 |
| `ULyraGameplayAbility_RangedWeapon` | 발사 원뿔 계산, 레이캐스팅, 탄약 추적 |

---

## 블루프린트 명명 규칙

| 접두사 | 의미 |
|---|---|
| `GA_` | GameplayAbility |
| `GE_` | GameplayEffect |
| `GCN_` | GameplayCueNotify (UGameplayCueNotify 서브클래스) |
| `GCNL_` | Latent GameplayCueNotify (AGameplayCueNotify_Actor) |
| `Phase_` | 게임 페이즈 어빌리티 |
| `AbilitySet_` | ULyraAbilitySet 에셋 |
