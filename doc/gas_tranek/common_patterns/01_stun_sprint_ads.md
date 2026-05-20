# Stun / Sprint / ADS 구현

> **GASDoc**: 5.1~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-stun"></a>
### Stun 구현 시 GA 취소·활성화 차단·이동 제한을 각각 어떻게 처리하는가?

세 가지를 각각 별도로 처리한다:

| 목적 | 구현 방법 |
|---|---|
| 활성 GA 취소 | Stun GameplayTag가 추가되는 시점에 `AbilitySystemComponent->CancelAbilities()` 호출 |
| 새 GA 활성화 차단 | 각 GA의 `Activation Blocked Tags` 컨테이너에 Stun GameplayTag 등록 |
| 이동 차단 | `CharacterMovementComponent::GetMaxSpeed()`를 오버라이드하여 Stun 태그 보유 시 0 반환 |

<a name="cae-sprint"></a>
### 달리기(Sprint) 중 이동 속도 증가를 예측적으로 적용하려면 어떻게 구현하는가?

이동 속도 증가는 `CharacterMovementComponent`가 네트워크를 통해 서버로 플래그를 전송하는 방식으로 예측 처리한다. 상세 구현은 `GDCharacterMovementComponent.h/cpp`를 참조한다.

`GA_Sprint_BP`는 `Left Shift` 입력에 반응하고, CMC에 Sprint 시작·종료를 지시하며, 눌려 있는 동안 스태미나를 예측 소모하는 역할을 담당한다.

<a name="cae-ads"></a>
### ADS(조준 사격) 중 이동 속도 감소는 Sprint와 어떻게 동일한 방식으로 구현되는가?

Sprint와 동일한 CMC 플래그 방식을 사용하되, 이동 속도를 **증가** 대신 **감소**시킨다. 상세 구현은 `GDCharacterMovementComponent.h/cpp`를 참조한다. 입력 처리는 `GA_AimDownSight_BP`를 참조한다. ADS에는 스태미나 소모가 없다.

---
