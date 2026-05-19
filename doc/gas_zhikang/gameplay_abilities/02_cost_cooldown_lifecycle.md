# 비용·쿨다운과 어빌리티 생명주기

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 어빌리티 비용과 쿨다운

어빌리티에는 `CostGameplayEffectClass`와 `CooldownGameplayEffectClass`를 설정할 수 있다.
예를 들어 게임에 `Energy` 리소스 Attribute가 있다면, Energy를 차감하는 GE 클래스를 만들어 비용 GE로 지정한다.

### 비용 검사 시점

활성화 시도 시: 비용 GE의 모든 Attribute Modifier를 적용했을 때 결과가 음수가 되지 않아야 한다.
CommitAbility 호출 시: 다시 한 번 검사하고 통과하면 실제로 적용한다.

### CommitAbility

비용·쿨다운이 있는 어빌리티는 반드시 `CommitAbility`를 호출해야 한다.
호출하지 않으면 비용·쿨다운이 적용되지 않는다.
CommitAbility는 비용 지불 가능 여부를 다시 확인한다. 활성화 이후 리소스가 변했을 경우 실패할 수 있으므로 **반환값을 반드시 확인**해야 한다.

### 쿨다운 동작 방식

쿨다운 GE가 성공적으로 CommitAbility된 후 소유자에게 적용된다.
쿨다운 GE 클래스가 부여하는 GameplayTag와 동일한 태그를 부여하는 GE가 소유자에게 적용되어 있으면 쿨다운 중으로 판단한다.
`GetCooldownTimeRemaining()`으로 현재 쿨다운 남은 시간을 조회할 수 있다.

쿨다운 GE 클래스 설정 요구사항:
- `Grant Tags to Target Actor` 컴포넌트를 추가해 태그를 부여해야 한다.
- `Duration Policy`가 `Duration` 또는 `Infinite`여야 한다.

### 예측적 CommitAbility

클라이언트 측에서 CommitAbility를 호출할 때 비용·쿨다운이 예측적으로 적용되는지 여부는
**Scoped Prediction Window 내에서 호출되는지**에 따라 결정된다.
`ActivateAbility` 중 즉시 호출하거나 특정 AbilityTask의 콜백에서 호출하는 경우 해당된다.

---

## 어빌리티 종료와 취소

활성화 후 어빌리티는 명시적으로 종료 또는 취소될 때까지 활성 상태를 유지한다.
이는 전적으로 어빌리티 디자이너의 책임이다.

`Retrigger Instanced Ability` 값에 따라 이미 활성화된 어빌리티의 재활성화 허용 여부가 결정된다.
어빌리티가 종료되면 진행 중인 모든 AbilityTask도 함께 종료되고 정리된다.

- **`EndAbility`**: 설계상 완료되었을 때 호출한다.
- **`CancelAbility`**: 취소할 때 언제든 호출할 수 있다.
- **`OnEndAbility` 이벤트**: 완료인지 취소인지 구분하는 인수가 포함된다.

> **참고**  
> 어빌리티 종료가 비용·쿨다운을 자동으로 적용하지 않는다. CommitAbility를 별도로 호출해야 한다.

무한히 활성 상태인 어빌리티도 허용된다.
Gameplay Debugger와 Visual Logger로 어빌리티 활성화 상태를 확인할 수 있다.

---

## ASC가 어빌리티를 활성화할 수 있는 시점

`InitAbilityActorInfo`가 호출되어 ASC의 Owner와 (선택적으로) Avatar가 전달되어야 한다.
Avatar(Pawn 등)가 필요한 어빌리티는 해당 Avatar가 스폰되고 ASC에 전달된 이후에만 활성화할 수 있다.

네트워크 게임에서 **Local Predicted 어빌리티**는 두 조건을 모두 만족해야 활성화 가능하다:
1. `InitAbilityActorInfo` 호출 완료
2. `FGameplayAbilityActorInfo::InitFromActor()`에서 PlayerController가 성공적으로 캐시됨

### Lyra의 ActivateOnSpawn 처리

Lyra에는 최대한 빨리 활성화되어야 하는 어빌리티("ActivateOnSpawn" 어빌리티)가 있다.
`ULyraAbilitySystemComponent::TryActivateAbilitiesOnSpawn()`이 두 시점에 호출된다:

1. `ULyraAbilitySystemComponent::InitAbilityActorInfo()` 오버라이드 끝 — Owner 또는 Avatar가 변경될 때마다 호출
2. `ALyraPlayerController::OnRep_PlayerState()` — 클라이언트 측에서 PlayerController가 사용 가능해진 시점. ASC가 PlayerState에 소유되어 있기 때문에 이 시점을 재시도 지점으로 선택함. `RefreshAbilityActorInfo()`도 함께 호출해 ASC가 PlayerController를 캐시하게 함

자신의 프로젝트에서도 동일하게 구현할 수 있다.
자동 활성화 대상 `FGameplayAbilitySpec` 목록을 갖고, `InitAbilityActorInfo()` 이후 및 로컬 플레이어의 PlayerController가 사용 가능해진 시점에 각각 활성화를 시도한다.
