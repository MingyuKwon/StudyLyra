# Target Actors

> **GASDoc**: 4.11.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting-actors"></a>
#### TargetActor란 무엇이며 WaitTargetData Task와 어떻게 함께 사용하는가?

`TargetActor`(`AGameplayAbilityTargetActor`)는 월드에서 타게팅 정보를 시각화하고 수집하는 Actor다. `WaitTargetData` AbilityTask가 스폰하며, 확인(confirmation) 시 수집한 정보를 `TargetData`로 반환해 GameplayEffect에 전달한다.

`TargetActor`는 `AActor` 기반이므로 어떤 시각 컴포넌트도 사용할 수 있다:
- 스태틱 메시 → 건설 오브젝트 배치 시각화
- 데칼 → 지면 AoE 범위 표시
- 없음 → 즉각 히트스캔처럼 시각 표현이 불필요한 경우

`Instant` 외의 확인 타입에서는 `TargetActor`가 `Tick()`에서 트레이스/오버랩을 수행해 타겟을 갱신한다. 틱이 발생하므로 성능 부담이 있다면 틱 속도를 낮추는 것을 고려한다.

타겟 확인 시점은 `EGameplayTargetingConfirmation::Type`으로 제어한다:

| 타입 | 확인 시점 |
| --- | --- |
| `Instant` | 즉시 발생. Tick 없음, TargetActor 즉시 스폰·파괴 |
| `UserConfirmed` | `Confirm` 입력 또는 `UAbilitySystemComponent::TargetConfirm()` 호출 시 |
| `Custom` | `UGameplayAbility::ConfirmTaskByInstanceName()` 호출 시 |
| `CustomMulti` | `ConfirmTaskByInstanceName()` 호출 시. AbilityTask를 종료하지 않아 여러 번 데이터 반환 가능 |

`WaitTargetData`는 `AGameplayAbilityTargetActor` 클래스를 파라미터로 받아 활성화 시마다 인스턴스를 스폰하고 종료 시 파괴한다. 매 발사마다 스폰·파괴가 발생하므로, 자동 소총처럼 지속적으로 TargetData를 생성해야 하는 경우에는 TargetActor를 재사용하는 커스텀 구현이 필요하다.

`ShouldProduceTargetDataOnServer` 속성에 따라 네트워크 동작이 달라진다:

| 값 | 동작 |
|---|---|
| `false` (기본) | 클라이언트가 확인 시 TargetData를 `CallServerSetReplicatedTargetData()`로 서버에 RPC 전송 |
| `true` | 클라이언트는 `GenericConfirm` 이벤트만 서버에 전송. 서버가 직접 트레이스/오버랩으로 TargetData 생성 |

기본 TargetActor는 트레이스/오버랩 범위 안에 있을 때만 타겟이 유효하다. 범위를 벗어나면 타겟이 사라진다. 마지막으로 유효했던 타겟을 유지하는 "persistent target" 기능이 필요하면 커스텀 TargetActor를 구현해야 한다.

일반 TargetActor 파라미터:

| 파라미터 | 설명 |
| --- | --- |
| `Debug` | non-shipping 빌드에서 트레이스/오버랩 디버그 정보 표시 |
| `Filter` | Actor 필터링 구조체. 플레이어 Pawn 제외, 특정 클래스만 허용 등 |
| `Reticle Class` | 스폰할 `AGameplayAbilityWorldReticle` 서브클래스 |
| `Reticle Parameters` | Reticle 설정값 |
| `Start Location` | 트레이스 시작 위치 (시점, 총구, Pawn 위치 등) |

---
