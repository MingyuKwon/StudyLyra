# GA 정의

> **GASDoc**: 4.6.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-definition"></a>
#### GA란 무엇이며, 어떤 행동을 GA로 구현해야 하고 어떤 것은 피해야 하는가?

GA(`GameplayAbility`)는 Actor가 게임 내에서 수행할 수 있는 행동이나 스킬이다. Blueprint 또는 C++로 제작하며, 달리기와 총 발사처럼 동시에 여러 GA가 활성화될 수 있다.

| 구분 | 예시 |
|---|---|
| 적합 | 점프, 달리기, 총 발사, 패시브 차단, 물약 사용, 문 열기, 자원 수집, 건물 건설 |
| 부적합 | 기본 이동 입력, 상점 아이템 구매 같은 UI 상호작용 |

이는 규칙이 아닌 권고사항이다. GA는 기본적으로 레벨을 가지며, 이를 통해 Attribute 변화량이나 동작 방식을 조절한다.

GA는 `Net Execution Policy`에 따라 owning client 및/또는 서버에서 실행된다. **Simulated proxy에서는 실행되지 않는다.** 시각적 변경 사항은 AbilityTask와 GameplayCue를 통해 simulated proxy에 전달된다.

모든 GA는 `ActivateAbility()`를 오버라이드해 게임플레이 로직을 구현하고, `EndAbility()`에 완료·취소 시 실행할 추가 로직을 넣는다.

단순한 GA 흐름도:
![Simple GameplayAbility Flowchart](https://github.com/tranek/GASDocumentation/raw/master/Images/abilityflowchartsimple.png)

복잡한 GA 흐름도:
![Complex GameplayAbility Flowchart](https://github.com/tranek/GASDocumentation/raw/master/Images/abilityflowchartcomplex.png)

<a name="concepts-ga-definition-reppolicy"></a>
#### GA의 Replication Policy는 왜 사용하지 말아야 하는가?

사용하지 말 것. `GameplayAbilitySpec`은 기본적으로 서버에서 owning client로 자동 복제된다. GA는 simulated proxy에서 실행되지 않으므로 이 옵션이 필요하지 않다. Epic의 Dave Ratti도 향후 제거할 의향을 밝혔다.

<a name="concepts-ga-definition-remotecancel"></a>
#### "Server Respects Remote Ability Cancellation" 옵션이 득보다 실이 많은 이유는?

클라이언트의 GA가 취소되거나 자연 종료되면, 완료 여부와 관계없이 서버의 GA도 강제 종료시킨다. 레이턴시가 높은 플레이어의 로컬 예측 GA에서 특히 문제가 두드러진다. 일반적으로 비활성화를 권장한다.

<a name="concepts-ga-definition-repinputdirectly"></a>
#### "Replicate Input Directly" 대신 Epic이 권장하는 대안은 무엇인가?

이 옵션은 입력 press/release 이벤트를 항상 서버로 복제한다. Epic은 대신 ASC에 입력이 바인딩된 경우 기존 입력 관련 AbilityTask에 내장된 `Generic Replicated Events`를 활용하도록 권장한다.

```c++
/** Direct Input state replication. These will be called if bReplicateInputDirectly is true on the ability and is generally not a good thing to use. (Instead, prefer to use Generic Replicated Events). */
UAbilitySystemComponent::ServerSetInputPressed()
```

---

### GA의 GameplayAbilitySpec은 왜 owning client에게만 복제하고 simulated proxy에는 보내지 않는가?

#### 각 주체가 실제로 필요한 정보

GA가 복제되는 단위는 `FGameplayAbilitySpec`이다. 서버가 보유한 스펙 배열(`ActivatableAbilities`)은 `COND_OwnerOnly`로 owning client에게만 복제된다.

| 주체 | 필요한 정보 | 공급 수단 |
|---|---|---|
| Server | 어떤 어빌리티를 갖고 있는가, 발동 가능한가, 쿨다운/코스트 상태 | `ActivatableAbilities` 직접 보유 |
| Owning Client | 내 어빌리티 목록, 쿨다운/코스트 UI, 입력 바인딩, 예측 실행 | `ActivatableAbilities` 복제 (COND_OwnerOnly) |
| Simulated Proxy | 저 캐릭터가 지금 어떻게 보이는가 | GameplayCue, ASC 몽타주 복제, bSimulatedTask |

Owning client는 자기 캐릭터의 플레이어이므로 어빌리티 목록과 쿨다운 상태를 알아야 UI를 그리고 입력을 처리할 수 있다. Simulated proxy는 남의 캐릭터를 보는 관찰자이므로 어빌리티 스펙이 아닌 시각적 결과만 필요하다.

#### GA 스펙을 모든 클라에 복제하면 대역폭에 어떤 문제가 생기는가?

`FGameplayAbilitySpec`에는 어빌리티 클래스, 레벨, 입력 ID, 핸들, 활성화 카운트, 인스턴스 목록 등 상당한 양의 데이터가 들어있다. 64인 멀티플레이어 게임에서 전체 복제하면 각 클라이언트가 63명분의 스펙을 받아야 한다. `COND_OwnerOnly`로 제한하면 이 비용을 owning client 1명에게만 부과한다.

#### Simulated proxy는 GA 스펙 없이 어떤 채널로 필요한 정보를 받는가?

```
애니메이션  → ASC::RepAnimMontageInfo (COND_None — 모든 클라에게)
이펙트/사운드 → GameplayCue (COND_None — 모든 클라에게)
이동 효과   → bSimulatedTask (COND_SkipOwner — simulated proxy에게)
```

"GA 스펙을 owning client에게만 복제한다"는 것은 제약이 아니라 **각 주체에게 필요한 것만 보낸다**는 설계 원칙이다.
