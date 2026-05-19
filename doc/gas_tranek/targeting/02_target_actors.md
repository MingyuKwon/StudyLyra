# Target Actors

> **GASDoc**: 4.11.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting-actors"></a>
#### 4.11.2 Target Actors

`GameplayAbility`는 `WaitTargetData` `AbilityTask`와 함께 [`TargetActors`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/AGameplayAbilityTargetActor/index.html)를 스폰하여 월드에서 타게팅 정보를 시각화하고 수집한다. `TargetActor`는 선택적으로 `GameplayAbilityWorldReticles`를 사용하여 현재 타겟을 표시할 수 있다. 확인(confirmation) 시 타게팅 정보는 `TargetData`로 반환되어 `GameplayEffect`에 전달된다.

`TargetActor`는 `AActor` 기반이므로 스태틱 메시나 데칼처럼 **어디서**, **어떻게** 타게팅하는지를 나타내는 어떤 종류의 시각 컴포넌트도 사용할 수 있다. 스태틱 메시는 캐릭터가 건설할 오브젝트의 배치를 시각화하는 데 사용될 수 있다. 데칼은 지면 위의 범위 효과(area of effect)를 표시하는 데 사용할 수 있다. 샘플 프로젝트는 Meteor 어빌리티의 데미지 범위를 나타내기 위해 지면 데칼이 있는 [`AGameplayAbilityTargetActor_GroundTrace`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/AGameplayAbilityTargetActor_Grou-/index.html)를 사용한다. 아무것도 표시하지 않아도 된다. 예를 들어 [GASShooter](https://github.com/tranek/GASShooter)에서처럼 즉각적으로 타겟까지 라인을 추적하는 히트스캔 총기라면 아무것도 표시하는 것이 의미가 없다.

TargetActor는 기본 트레이스나 콜리전 오버랩을 사용하여 타게팅 정보를 수집하고, `TargetActor` 구현에 따라 결과를 `FHitResult` 또는 `AActor` 배열로 `TargetData`에 변환한다. `WaitTargetData` `AbilityTask`는 `TEnumAsByte<EGameplayTargetingConfirmation::Type> ConfirmationType` 파라미터를 통해 타겟이 언제 확인되는지를 결정한다. `TEnumAsByte<EGameplayTargetingConfirmation::Type::Instant`을 **사용하지 않는** 경우, `TargetActor`는 일반적으로 `Tick()`에서 트레이스/오버랩을 수행하고 구현에 따라 `FHitResult`로 위치를 업데이트한다. `Tick()`에서 트레이스/오버랩을 수행하지만, 복제되지 않고 일반적으로 한 번에 하나(그 이상일 수도 있음)의 `TargetActor`만 실행되므로 크게 나쁘지는 않다. 다만 `Tick()`을 사용한다는 점과 GASShooter의 로켓 런처 보조 어빌리티처럼 복잡한 `TargetActor`는 `Tick()`에서 많은 작업을 수행할 수 있다는 점을 인식해야 한다. `Tick()`에서의 트레이스는 클라이언트에게 매우 반응적이지만, 성능 부담이 크다면 `TargetActor`의 틱 속도를 낮추는 것도 고려할 수 있다. `TEnumAsByte<EGameplayTargetingConfirmation::Type::Instant`의 경우, `TargetActor`는 즉시 스폰되어 `TargetData`를 생성하고 파괴된다. `Tick()`은 절대 호출되지 않는다.

| `EGameplayTargetingConfirmation::Type` | 타겟 확인 시점 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Instant` | 타게팅이 즉시 발생하며, 특별한 로직이나 '발사' 시점을 결정하는 사용자 입력이 없다. |
| `UserConfirmed` | 어빌리티가 `Confirm` 입력에 바인딩되어 있거나 `UAbilitySystemComponent::TargetConfirm()`을 호출할 때 타게팅이 발생한다. `TargetActor`는 바인딩된 `Cancel` 입력이나 `UAbilitySystemComponent::TargetCancel()` 호출에도 응답하여 타게팅을 취소한다. |
| `Custom` | GameplayTargeting Ability가 `UGameplayAbility::ConfirmTaskByInstanceName()`을 호출하여 타게팅 데이터가 준비됐을 때를 직접 결정한다. `TargetActor`는 `UGameplayAbility::CancelTaskByInstanceName()`에도 응답하여 타게팅을 취소한다. |
| `CustomMulti` | GameplayTargeting Ability가 `UGameplayAbility::ConfirmTaskByInstanceName()`을 호출하여 타게팅 데이터가 준비됐을 때를 직접 결정한다. `TargetActor`는 `UGameplayAbility::CancelTaskByInstanceName()`에도 응답하여 타게팅을 취소한다. 데이터가 생성될 때 `AbilityTask`를 종료하지 않아야 한다. |

모든 `TargetActor`가 모든 `EGameplayTargetingConfirmation::Type`을 지원하는 것은 아니다. 예를 들어, `AGameplayAbilityTargetActor_GroundTrace`는 `Instant` 확인을 지원하지 않는다.

`WaitTargetData` `AbilityTask`는 `AGameplayAbilityTargetActor` 클래스를 파라미터로 받아 `AbilityTask`가 활성화될 때마다 인스턴스를 스폰하고, `AbilityTask`가 종료될 때 `TargetActor`를 파괴한다. `WaitTargetDataUsingActor` `AbilityTask`는 이미 스폰된 `TargetActor`를 받지만, `AbilityTask`가 종료될 때 여전히 파괴한다. 두 `AbilityTask` 모두 사용할 때마다 새로 스폰된 `TargetActor`를 필요로 한다는 점에서 비효율적이다. 프로토타이핑에는 좋지만, 자동 소총처럼 지속적으로 `TargetData`를 생성해야 하는 경우에는 프로덕션에서 최적화를 고려해야 한다. GASShooter는 `TargetActor`를 파괴하지 않고 재사용할 수 있도록 처음부터 작성한 [`AGameplayAbilityTargetActor`](https://github.com/tranek/GASShooter/blob/master/Source/GASShooter/Public/Characters/Abilities/GSGATA_Trace.h) 커스텀 서브클래스와 새로운 [`WaitTargetDataWithReusableActor`](https://github.com/tranek/GASShooter/blob/master/Source/GASShooter/Public/Characters/Abilities/AbilityTasks/GSAT_WaitTargetDataUsingActor.h) `AbilityTask`를 보유하고 있다.

`TargetActor`는 기본적으로 복제되지 않지만, 다른 플레이어에게 로컬 플레이어가 어디를 타게팅하는지 보여주는 것이 게임에 의미가 있다면 복제하도록 만들 수 있다. `WaitTargetData` `AbilityTask`의 RPC를 통해 서버와 통신하는 기본 기능을 포함하고 있다. `TargetActor`의 `ShouldProduceTargetDataOnServer` 속성이 `false`로 설정되어 있으면, 클라이언트는 `UAbilityTask_WaitTargetData::OnTargetDataReadyCallback()`의 `CallServerSetReplicatedTargetData()`를 통해 확인 시 `TargetData`를 서버에 RPC로 전송한다. `ShouldProduceTargetDataOnServer`가 `true`이면, 클라이언트는 `UAbilityTask_WaitTargetData::OnTargetDataReadyCallback()`에서 일반 확인 이벤트 `EAbilityGenericReplicatedEvent::GenericConfirm` RPC를 서버에 전송하고, 서버는 RPC를 받으면 트레이스 또는 오버랩 체크를 수행하여 서버에서 데이터를 생성한다. 클라이언트가 타게팅을 취소하면, `UAbilityTask_WaitTargetData::OnTargetDataCancelledCallback`에서 일반 취소 이벤트 `EAbilityGenericReplicatedEvent::GenericCancel` RPC를 서버에 전송한다. `TargetActor`와 `WaitTargetData` `AbilityTask` 모두에 수많은 델리게이트가 있다. `TargetActor`는 입력에 응답하여 `TargetData` 준비, 확인, 취소 델리게이트를 생성하고 브로드캐스트한다. `WaitTargetData`는 `TargetActor`의 `TargetData` 준비, 확인, 취소 델리게이트를 수신하고 해당 정보를 `GameplayAbility`와 서버에 중계한다. `TargetData`를 서버에 전송하는 경우, 치트를 방지하기 위해 서버에서 `TargetData`가 합리적인지 검증하는 것이 좋다. 서버에서 직접 `TargetData`를 생성하면 이 문제를 완전히 피할 수 있지만, owning 클라이언트에서 오예측이 발생할 가능성이 있다.

사용하는 `AGameplayAbilityTargetActor`의 특정 서브클래스에 따라 `WaitTargetData` `AbilityTask` 노드에 다양한 `ExposeOnSpawn` 파라미터가 노출된다. 일반적인 파라미터에는 다음이 포함된다:

| 일반 `TargetActor` 파라미터 | 설명 |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Debug | `true`이면 비-쉬핑(non-shipping) 빌드에서 `TargetActor`가 트레이스를 수행할 때마다 디버그 트레이스/오버랩 정보가 그려진다. `Instant`가 아닌 `TargetActor`는 `Tick()`에서 트레이스를 수행하므로 이 디버그 드로우 호출도 `Tick()`에서 발생한다. |
| Filter | [선택] 트레이스/오버랩이 발생할 때 `Actor`를 타겟에서 필터링(제거)하기 위한 특수 구조체. 일반적인 사용 사례는 플레이어의 `Pawn`을 필터링하거나 특정 클래스의 타겟만 필요로 하는 것이다. 고급 사용 사례는 Target Data Filters를 참고한다. |
| Reticle Class | [선택] `TargetActor`가 스폰할 `AGameplayAbilityWorldReticle`의 서브클래스. |
| Reticle Parameters | [선택] Reticle을 설정한다. Reticles 참고. |
| Start Location | 트레이스가 시작되어야 하는 위치를 나타내는 특수 구조체. 일반적으로 플레이어의 시점(viewpoint), 무기 총구, 또는 `Pawn`의 위치가 된다. |

기본 `TargetActor` 클래스에서는 `Actor`가 트레이스/오버랩 범위 안에 직접 있을 때만 유효한 타겟으로 인정된다. 트레이스/오버랩 범위를 벗어나면(이동하거나 시선을 돌리면) 더 이상 유효하지 않다. `TargetActor`가 마지막으로 유효했던 타겟을 기억하게 하려면, 커스텀 `TargetActor` 클래스에 이 기능을 추가해야 한다. 이를 "persistent target"이라고 부르는데, `TargetActor`가 확인 또는 취소를 받거나, `TargetActor`가 트레이스/오버랩에서 새로운 유효 타겟을 찾거나, 타겟이 더 이상 유효하지 않을 때(파괴될 때)까지 유지된다. GASShooter는 로켓 런처의 보조 어빌리티 유도 로켓 타게팅에 persistent target을 사용한다.

---

