# GA 정의

> **GASDoc**: 4.6.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-definition"></a>
#### 4.6.1 GameplayAbility 정의

[`GameplayAbilities`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/UGameplayAbility/index.html)(`GA`)는 Actor가 게임 내에서 수행할 수 있는 모든 행동이나 스킬을 의미한다. 예를 들어 달리기와 총 발사처럼 동시에 여러 GA가 활성화될 수 있다. Blueprint 또는 C++로 제작할 수 있다.

GA로 구현하기 적합한 예시:
* 점프
* 달리기
* 총 발사
* X초마다 공격을 패시브로 차단하기
* 물약 사용
* 문 열기
* 자원 수집
* 건물 건설

GA로 구현하지 말아야 할 것:
* 기본 이동 입력
* UI와의 일부 상호작용 — 상점에서 아이템 구매 등에 GA를 사용하지 말 것

이는 규칙이 아닌 권고사항이다. 설계와 구현 방식은 프로젝트마다 다를 수 있다.

GA는 기본적으로 레벨을 가지며, 이를 통해 Attribute의 변화량이나 GA의 동작 방식을 조절할 수 있다.

GA는 `Net Execution Policy`에 따라 owning client 및/또는 서버에서 실행되지만, **simulated proxy에서는 실행되지 않는다.** Net Execution Policy는 GA가 로컬에서 예측(Prediction)될지 여부를 결정한다. GA는 선택적인 코스트와 쿨다운 GameplayEffect를 기본 지원한다. 시간이 걸리는 동작(이벤트 대기, Attribute 변화 대기, 플레이어 타겟 선택, Root Motion Source를 이용한 캐릭터 이동 등)에는 `AbilityTask`를 사용한다. **Simulated client는 GA를 실행하지 않는다.** 대신 서버가 어빌리티를 실행할 때, simulated proxy에서 시각적으로 재생되어야 하는 것(예: 애니메이션 몽타주)은 AbilityTask를 통해 복제되거나 RPC로 전달되며, 사운드·파티클 같은 코스메틱 요소는 `GameplayCue`를 통해 처리된다.

모든 GA는 `ActivateAbility()` 함수를 오버라이드하여 게임플레이 로직을 구현한다. GA가 완료되거나 취소될 때 실행되는 추가 로직은 `EndAbility()`에 넣는다.

단순한 GA 흐름도:
![Simple GameplayAbility Flowchart](https://github.com/tranek/GASDocumentation/raw/master/Images/abilityflowchartsimple.png)

복잡한 GA 흐름도:
![Complex GameplayAbility Flowchart](https://github.com/tranek/GASDocumentation/raw/master/Images/abilityflowchartcomplex.png)

복잡한 어빌리티는 여러 GA가 서로 활성화하거나 취소하는 방식으로 상호작용하며 구현할 수 있다.

<a name="concepts-ga-definition-reppolicy"></a>
#### 4.6.1.1 Replication Policy

이 옵션은 사용하지 말 것. 이름이 오해를 유발하지만 실제로는 필요하지 않다. `GameplayAbilitySpec`은 기본적으로 서버에서 owning client로 자동 복제된다. 앞서 언급했듯이, **GA는 simulated proxy에서 실행되지 않는다.** 시각적 변경 사항은 AbilityTask와 GameplayCue를 통해 simulated proxy로 복제하거나 RPC한다. Epic의 Dave Ratti는 이 옵션을 [향후 제거할 의향](https://epicgames.ent.box.com/s/m1egifkxv3he3u3xezb9hzbgroxyhx89)을 밝힌 바 있다.

<a name="concepts-ga-definition-remotecancel"></a>
#### 4.6.1.2 Server Respects Remote Ability Cancellation

이 옵션은 득보다 실이 많다. 클라이언트의 GA가 취소되거나 자연스럽게 종료될 경우, 완료 여부와 관계없이 서버의 GA도 강제로 종료시킨다. 특히 레이턴시가 높은 플레이어가 사용하는 로컬 예측 GA에서 후자의 문제가 두드러진다. 일반적으로 이 옵션은 비활성화하는 것을 권장한다.

<a name="concepts-ga-definition-repinputdirectly"></a>
#### 4.6.1.3 Replicate Input Directly

이 옵션을 활성화하면 입력 press/release 이벤트가 항상 서버로 복제된다. Epic은 이 방식 대신, ASC에 입력이 바인딩되어 있는 경우 기존 입력 관련 `AbilityTask`에 내장된 `Generic Replicated Events`를 활용하도록 권장한다.

Epic의 주석:
```c++
/** Direct Input state replication. These will be called if bReplicateInputDirectly is true on the ability and is generally not a good thing to use. (Instead, prefer to use Generic Replicated Events). */
UAbilitySystemComponent::ServerSetInputPressed()
```

---

## 내 분석
