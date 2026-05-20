# Cost & Cooldown GE

> **GASDoc**: 4.5.13~15 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-car"></a>
#### Custom Application Requirement(CAR)는 태그 체크보다 어떤 고급 조건이 필요할 때 사용하는가?

CAR는 GE의 단순한 GameplayTag 체크보다 더 정교한 적용 가능 여부 제어가 필요할 때 사용한다. Blueprint에서는 `CanApplyGameplayEffect()`, C++에서는 `CanApplyGameplayEffect_Implementation()`을 오버라이드한다.

사용 예:
- Target이 특정 수치 이상의 Attribute를 보유해야 하는 경우
- Target에 특정 GE가 특정 스택 수만큼 쌓여 있어야 하는 경우
- 이미 적용된 인스턴스의 지속시간을 변경하고 새 인스턴스를 적용하지 않는 경우 (`CanApplyGameplayEffect()`에서 false를 반환)

<a name="concepts-ge-cost"></a>
#### GA의 Cost GE는 어떻게 구현하며, 여러 GA에서 하나의 Cost GE를 재사용하는 방법은?

Cost GE는 Attribute에서 값을 차감하는 Modifier를 포함하는 `Instant` GE여야 한다. 예측 가능하게 유지하도록 설계하며 `ExecutionCalculations`를 사용하지 않는 것이 권장된다. 복잡한 비용 계산에는 MMC가 적합하다.

Cost GE를 여러 GA에서 재사용하는 두 가지 방법 (**Instanced 어빌리티에서만 동작**):

**1. MMC 사용:**

```c++
float UPGMMC_HeroAbilityCost::CalculateBaseMagnitude_Implementation(const FGameplayEffectSpec& Spec) const
{
    const UPGGameplayAbility* Ability = Cast<UPGGameplayAbility>(Spec.GetContext().GetAbilityInstance_NotReplicated());
    if (!Ability) return 0.0f;
    return Ability->Cost.GetValueAtLevel(Ability->GetAbilityLevel());
}
```

GA 서브클래스에 비용 값을 `FScalableFloat`로 정의하고 MMC에서 읽는다.

**2. `GetCostGameplayEffect()` 오버라이드:** 런타임에 GA의 비용 값을 읽는 GE를 직접 생성해 반환한다.

<a name="concepts-ge-cooldown"></a>
#### GA의 Cooldown GE는 어떻게 구현하며, GA가 Cooldown Tag의 존재로 쿨다운을 판단하는 이유는?

Cooldown GE는 Modifier가 없는 `Duration` GE여야 하며, `GrantedTags`에 어빌리티마다 고유한 `Cooldown Tag`를 지정해야 한다. GA는 Cooldown GE의 존재가 아닌 **Cooldown Tag의 존재**를 확인한다. 태그 기반으로 확인하면 GE 인스턴스를 직접 조회하지 않아도 되고, 예측된 쿨다운과 서버 보정된 쿨다운 모두 동일한 방식으로 처리된다.

Cooldown GE 재사용 방법 (**Instanced 어빌리티에서만 동작**):

**1. SetByCaller 사용:**

```c++
// GA 서브클래스에 정의
UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FScalableFloat CooldownDuration;

UPROPERTY(BlueprintReadOnly, EditAnywhere, Category = "Cooldown")
FGameplayTagContainer CooldownTags;
```

`GetCooldownTags()`를 오버라이드해서 GA의 CooldownTags와 GE 태그를 합쳐 반환하고, `ApplyCooldown()`을 오버라이드해서 Cooldown Tags와 SetByCaller Duration을 Spec에 주입한다.

```c++
void UPGGameplayAbility::ApplyCooldown(...) const
{
    UGameplayEffect* CooldownGE = GetCooldownGameplayEffect();
    if (CooldownGE)
    {
        FGameplayEffectSpecHandle SpecHandle = MakeOutgoingGameplayEffectSpec(CooldownGE->GetClass(), GetAbilityLevel());
        SpecHandle.Data.Get()->DynamicGrantedTags.AppendTags(CooldownTags);
        SpecHandle.Data.Get()->SetSetByCallerMagnitude(FGameplayTag::RequestGameplayTag(FName("Data.Cooldown")),
            CooldownDuration.GetValueAtLevel(GetAbilityLevel()));
        ApplyGameplayEffectSpecToOwner(Handle, ActorInfo, ActivationInfo, SpecHandle);
    }
}
```

**2. MMC 사용:** Duration을 `Custom Calculation Class`로 설정하고, `Spec.GetContext().GetAbilityInstance_NotReplicated()`로 GA 인스턴스에서 쿨다운 값을 읽는 MMC를 만든다.

<a name="concepts-ge-cooldown-tr"></a>
##### 쿨다운 남은 시간을 코드에서 어떻게 조회하며 복제 모드와의 관계는?

```c++
FGameplayEffectQuery const Query = FGameplayEffectQuery::MakeQuery_MatchAnyOwningTags(CooldownTags);
TArray<TPair<float, float>> DurationAndTimeRemaining =
    AbilitySystemComponent->GetActiveEffectsTimeRemainingAndDuration(Query);
```

**주의**: 클라이언트에서 쿨다운 남은 시간을 조회하려면 클라이언트가 복제된 GE를 수신할 수 있어야 한다. ASC의 복제 모드에 따라 달라진다.

<a name="concepts-ge-cooldown-listen"></a>
##### 쿨다운 시작과 종료를 감지할 때 GE 추가/제거 델리게이트보다 Cooldown Tag 이벤트를 권장하는 이유는?

- **쿨다운 시작 감지**: GE 추가 델리게이트가 더 유용하다 — 적용된 Spec에 접근할 수 있어 로컬 예측 쿨다운인지 서버 보정 쿨다운인지 구분할 수 있다.
- **쿨다운 종료 감지**: **Cooldown Tag 제거 이벤트를 권장한다** — 서버의 보정된 Cooldown GE가 들어오면 로컬 예측본이 먼저 제거되어 `OnAnyGameplayEffectRemovedDelegate()`가 발동되는데, 이때는 아직 쿨다운 중이다. Cooldown Tag는 예측본 제거 → 서버 보정본 적용 과정에서 변경되지 않으므로 올바른 종료 시점을 감지할 수 있다.

<a name="concepts-ge-cooldown-prediction"></a>
##### GAS에서 쿨다운은 왜 진정한 예측이 불가능하며, 레이턴시가 높은 플레이어에게 어떤 영향을 주는가?

쿨다운은 진정한 예측이 불가능하다. 로컬에서 예측된 쿨다운이 만료되어도 GA의 실제 쿨다운은 서버 쿨다운에 종속된다. 레이턴시가 높은 플레이어는 쿨다운이 짧은 어빌리티에서 레이턴시가 낮은 플레이어보다 발사 속도가 느려져 불리해진다. Fortnite는 이를 피하기 위해 GE 기반 쿨다운을 쓰지 않는 자체 방식을 채택했다.

---

### Cost/Cooldown GE 재사용 패턴이 Non-Instanced GA에서 동작하지 않는 두 가지 이유는?

> 소스: `GameplayAbility.cpp:1995`, `GameplayEffectTypes.cpp:226`

Non-Instanced 어빌리티에서 `this`는 CDO다. 모든 액터가 공유하는 싱글톤이다.

#### Non-Instanced GA에서 TempCooldownTags가 CDO에 쓰여 경쟁 조건이 발생하는 이유는?

`GetCooldownTags()`는 `TempCooldownTags` 필드를 런타임에 수정한다. Non-Instanced이면 `this` = CDO이므로 여러 액터가 동시에 같은 어빌리티를 활성화하면 전부 같은 CDO의 `TempCooldownTags`를 동시에 쓴다 — 경쟁 조건이다.

#### GetAbilityInstance_NotReplicated()가 복제되지 않아 Non-Instanced GA에서 MMC가 실패하는 이유는?

`AbilityInstanceNotReplicated`는 `NetSerialize`에서 직렬화되지 않는다. 서버가 Cost GE Spec을 생성할 때 이 포인터를 저장하지만, 클라이언트에 복제되면 null이 된다. Non-Instanced이면 `this`가 CDO라 네트워크로 의미 있게 전달되지 않는다.

> UE 5.5부터 `EGameplayAbilityInstancingPolicy::NonInstanced`는 제거됐다. 현재 버전에서 이 제약은 항상 충족된다.

---

### Lyra는 왜 Cost에 GE를 쓰지 않고 ULyraAbilityCost 추상 클래스를 도입했는가?

> 소스: `LyraAbilityCost.h`, `LyraGameplayAbility.cpp:202`

GE의 Modifier는 `FGameplayAttributeData` 위에서만 동작하므로 인벤토리를 건드릴 수 없다. Lyra의 Cost는 Attribute 수치가 아니라 **인벤토리 아이템과 TagStack**이다. `ULyraAbilityCost`로 추상화하면 GE Modifier 규칙에 묶이지 않고 임의의 게임 로직을 Cost로 표현할 수 있다.

| 클래스 | 차감 대상 |
|---|---|
| `LyraAbilityCost_ItemTagStack` | 장착 아이템의 TagStack (탄약 등) |
| `LyraAbilityCost_PlayerTagStack` | PlayerState의 TagStack |
| `LyraAbilityCost_InventoryItem` | 인벤토리 아이템 수량 |

세 구현체 모두 `ApplyCost`에서 `IsNetAuthority()` 체크를 먼저 한다 — 클라이언트에서는 실제 차감을 하지 않는다. 이 Cost는 예측되지 않는다.

**`bOnlyApplyCostOnHit`**: 히트가 확인된 경우에만 비용을 차감한다. 서버에서 TargetData의 HitResult 유무로 판단한다.

#### Lyra가 탄약 Cost를 예측하지 않는 의도적 타협은 무엇이며, 그 결과 RTT 사이에 어떤 동작이 발생하는가?

클라이언트에서 `CheckCost`는 복제된 TagStack 값을 읽어 통과 여부를 판단한다. 통과하면 능력을 로컬에서 발동한다. 하지만 `ApplyCost`는 서버에서만 실행되므로 클라이언트의 탄약 카운터는 그대로다.

결과적으로 RTT 동안 클라이언트의 탄약은 차감되지 않고 능력만 발동된다. 서버가 탄약 부족을 판단하면 해당 발사를 거부·롤백한다.

| | 예측함 | 예측 안 함 |
|---|---|---|
| 능력 발동 | 애니메이션, VFX, 히트 판정 | — |
| Cost 상태 | — | 탄약/TagStack 차감, 인벤토리 |

Lyra의 판단: 총구 화염이 입력 즉시 나오지 않으면 조작감이 망가지지만, 탄약 카운터 숫자가 0.1초 늦게 줄어드는 건 플레이어가 크게 인식하지 못한다.

---

### Lyra는 Cost와 달리 왜 Cooldown에는 표준 GE 방식을 그대로 사용하는가?

> 소스: `LyraGameplayAbility.cpp:36`

쿨다운은 "일정 시간 동안 태그를 보유한다"는 Duration GE의 본질적 기능이다. 인벤토리 조작도, Attribute 조작도 없으며, 태그 부여와 시간 경과만 있다. GE가 가장 직접적인 도구이므로 굳이 바꿀 이유가 없다.

`ULyraGameplayAbility`에 쿨다운 관련 커스텀 로직이 없고, 어빌리티별 고유 Cooldown GE를 `CooldownGameplayEffect` 필드에 블루프린트에서 할당하는 표준 방식을 사용한다.
