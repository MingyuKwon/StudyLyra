# Stun / Sprint / ADS 구현

> **GASDoc**: 5.1~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-stun"></a>
### 5.1 Stun

일반적으로 Stun 구현 시에는 Stun 지속 시간 동안 캐릭터의 모든 활성 GameplayAbility를 취소하고, 새로운 GameplayAbility 활성화를 막으며, 이동을 차단하는 세 가지 처리가 필요하다. 샘플 프로젝트의 Meteor GameplayAbility는 피격 대상에 Stun을 적용하는 예시를 보여준다.

대상의 활성 GameplayAbility를 취소하려면, Stun GameplayTag가 추가되는 시점에 `AbilitySystemComponent->CancelAbilities()`를 호출한다.

Stun 상태에서 새로운 GameplayAbility 활성화를 막으려면, 각 GameplayAbility의 `Activation Blocked Tags` GameplayTagContainer에 Stun GameplayTag를 등록한다.

Stun 중 이동을 차단하려면, `CharacterMovementComponent`의 `GetMaxSpeed()` 함수를 오버라이드하여, 소유자에게 Stun GameplayTag가 존재할 경우 0을 반환하도록 한다.

<a name="cae-sprint"></a>
### 5.2 Sprint

샘플 프로젝트는 `Left Shift`를 누르는 동안 더 빠르게 달리는 Sprint 구현 예시를 제공한다.

이동 속도 증가는 `CharacterMovementComponent`가 네트워크를 통해 서버로 플래그를 전송하는 방식으로 예측(predictively) 처리된다. 상세 구현은 `GDCharacterMovementComponent.h/cpp`를 참조한다.

GameplayAbility(`GA_Sprint_BP`)는 `Left Shift` 입력에 반응하고, CMC에 Sprint 시작·종료를 지시하며, `Left Shift`가 눌려 있는 동안 스태미나를 예측 소모하는 역할을 담당한다. 상세 내용은 `GA_Sprint_BP`를 참조한다.

<a name="cae-ads"></a>
### 5.3 ADS (Aim Down Sights)

샘플 프로젝트는 Sprint와 동일한 방식으로 ADS를 처리하되, 이동 속도를 높이는 대신 **감소**시킨다.

이동 속도를 예측 방식으로 감소시키는 상세 구현은 `GDCharacterMovementComponent.h/cpp`를 참조한다.

입력 처리는 `GA_AimDownSight_BP`를 참조한다. ADS에는 스태미나 소모가 없다.

---

