# Cue 이벤트 & 신뢰성

> **GASDoc**: 4.8.8~9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gc-events"></a>
#### 4.8.8 GameplayCue 이벤트

`GameplayCue`는 특정 `EGameplayCueEvent`에 반응한다:

| `EGameplayCueEvent` | 설명 |
| --- | --- |
| `OnActive` | `GameplayCue`가 활성화(추가)될 때 호출된다. |
| `WhileActive` | `GameplayCue`가 방금 적용된 것이 아니더라도(인게임 진입 등) 활성 상태일 때 호출된다. `Tick`이 아니다! `GameplayCueNotify_Actor`가 추가되거나 관련성이 생길 때 `OnActive`처럼 한 번만 호출된다. `Tick()`이 필요하다면 `GameplayCueNotify_Actor`의 `Tick()`을 그냥 사용하면 된다. 어차피 `AActor`이기 때문이다. |
| `Removed` | `GameplayCue`가 제거될 때 호출된다. 이 이벤트에 반응하는 블루프린트 `GameplayCue` 함수는 `OnRemove`다. |
| `Executed` | `GameplayCue`가 실행될 때 호출된다: 즉발(instant) 효과 또는 주기적(Periodic) `Tick()`. 이 이벤트에 반응하는 블루프린트 `GameplayCue` 함수는 `OnExecute`다. |

`GameplayCue` 시작 시 발생하는 것들 중 늦게 접속한 플레이어가 놓쳐도 괜찮은 것들은 `OnActive`에 배치하라. `GameplayCue`의 지속 효과 중 늦게 접속한 플레이어도 봐야 하는 것들은 `WhileActive`에 배치하라. 예를 들어 MOBA에서 타워 구조물이 폭발하는 `GameplayCue`가 있다면, 초기 폭발 파티클 시스템과 폭발 사운드는 `OnActive`에 넣고, 잔류하는 불꽃 파티클이나 사운드는 `WhileActive`에 넣는다. 이 시나리오에서 늦게 접속한 플레이어는 `OnActive`의 초기 폭발을 다시 재생할 필요가 없지만, 폭발 이후 바닥에서 계속 타오르는 불꽃 효과는 `WhileActive`에서 볼 수 있어야 한다. `OnRemove`는 `OnActive`와 `WhileActive`에서 추가한 모든 것을 정리해야 한다. `WhileActive`는 Actor가 `GameplayCueNotify_Actor`의 관련성 범위에 들어올 때마다 호출된다. `OnRemove`는 Actor가 `GameplayCueNotify_Actor`의 관련성 범위를 벗어날 때마다 호출된다.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-gc-reliability"></a>
#### 4.8.9 GameplayCue 신뢰성

`GameplayCue`는 일반적으로 비신뢰성으로 취급해야 하며, 게임플레이에 직접 영향을 주는 모든 것에 적합하지 않다.

**실행된(Executed) `GameplayCue`:** 비신뢰성 멀티캐스트로 적용되므로 항상 비신뢰성이다.

**`GameplayEffect`에서 적용된 `GameplayCue`:**
* Autonomous proxy는 `OnActive`, `WhileActive`, `OnRemove`를 신뢰성 있게 수신한다.  
`FActiveGameplayEffectsContainer::NetDeltaSerialize()`가 `UAbilitySystemComponent::HandleDeferredGameplayCues()`를 호출하여 `OnActive`와 `WhileActive`를 호출한다. `FActiveGameplayEffectsContainer::RemoveActiveGameplayEffectGrantedTagsAndModifiers()`가 `OnRemoved`를 호출한다.
* Simulated proxy는 `WhileActive`와 `OnRemove`를 신뢰성 있게 수신한다.  
`UAbilitySystemComponent::MinimalReplicationGameplayCues`의 복제가 `WhileActive`와 `OnRemove`를 호출한다. `OnActive` 이벤트는 비신뢰성 멀티캐스트로 호출된다.

**`GameplayEffect` 없이 적용된 `GameplayCue`:**
* Autonomous proxy는 `OnRemove`를 신뢰성 있게 수신한다.  
`OnActive`와 `WhileActive` 이벤트는 비신뢰성 멀티캐스트로 호출된다.
* Simulated proxy는 `WhileActive`와 `OnRemove`를 신뢰성 있게 수신한다.  
`UAbilitySystemComponent::MinimalReplicationGameplayCues`의 복제가 `WhileActive`와 `OnRemove`를 호출한다. `OnActive` 이벤트는 비신뢰성 멀티캐스트로 호출된다.

`GameplayCue`에서 '신뢰성 있는' 무언가가 필요하다면, `GameplayEffect`를 통해 적용하고 `WhileActive`에서 FX를 추가하고 `OnRemove`에서 FX를 제거하는 방식을 사용하라.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
