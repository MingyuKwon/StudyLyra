# GAS 최적화

> **GASDoc**: 7 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="optimizations"></a>
## 7. 최적화

<a name="optimizations-abilitybatching"></a>
### 7.1 Ability Batching

단일 프레임 안에서 활성화, 선택적으로 TargetData 서버 전송, 종료가 모두 이루어지는 GameplayAbility는 두세 개의 RPC를 하나의 RPC로 묶어(batch) 처리할 수 있다. 이런 유형의 GameplayAbility는 히트스캔 총기류에 주로 활용된다.

<a name="optimizations-gameplaycuebatching"></a>
### 7.2 Gameplay Cue Batching

동시에 여러 GameplayCue를 발생시키는 경우, 하나의 RPC로 묶는 배칭을 고려한다. GameplayCue는 unreliable NetMulticast로 전송되므로, RPC 수를 줄이고 전송 데이터를 최소화하는 것이 목표다.

<a name="optimizations-ascreplicationmode"></a>
### 7.3 AbilitySystemComponent Replication Mode

ASC의 기본 설정은 `Full Replication Mode`로, 모든 GameplayEffect를 모든 클라이언트에 복제한다(싱글플레이어 게임에서는 문제없다). 멀티플레이어 게임에서는 플레이어 소유 ASC를 `Mixed Replication Mode`로, AI 제어 캐릭터의 ASC를 `Minimal Replication Mode`로 설정하는 것을 권장한다. 이렇게 하면 플레이어 캐릭터에 적용된 GE는 해당 플레이어의 오너 클라이언트에만 복제되고, AI 제어 캐릭터에 적용된 GE는 클라이언트에 전혀 복제되지 않는다. GameplayTag는 여전히 복제되고, GameplayCue는 Replication Mode에 관계없이 모든 클라이언트에 unreliable NetMulticast로 전달된다. 이 설정으로 모든 클라이언트가 볼 필요 없는 GE 복제로 인한 네트워크 데이터를 크게 줄일 수 있다.

<a name="optimizations-attributeproxyreplication"></a>
### 7.4 Attribute Proxy Replication

Fortnite Battle Royale(FNBR)처럼 플레이어 수가 많은 대규모 게임에서는 PlayerState가 항상 relevant이므로, 많은 수의 ASC가 Attribute를 복제하는 병목이 발생한다. 이를 최적화하기 위해 Fortnite는 `PlayerState::ReplicateSubobjects()`에서 **simulated player-controlled proxy**의 ASC와 AttributeSet을 복제 대상에서 완전히 제외한다. Autonomous proxy와 AI 제어 Pawn은 각자의 Replication Mode에 따라 정상적으로 복제된다. 항상 relevant한 PlayerState의 ASC에서 Attribute를 복제하는 대신, FNBR은 플레이어 Pawn에 복제되는 proxy struct를 별도로 두고, 서버의 ASC에서 Attribute가 변경될 때 proxy struct에도 동기화한다. 클라이언트는 proxy struct에서 복제된 Attribute를 수신해 로컬 ASC에 반영한다. 이를 통해 Attribute 복제가 Pawn의 relevancy와 NetUpdateFrequency를 따르게 되며, 네트워크 전송 데이터를 줄이면서 Pawn relevancy의 이점을 활용할 수 있다. 이 proxy struct는 소량의 화이트리스트 GameplayTag도 bitmask로 복제한다. AI 제어 Pawn은 ASC가 Pawn에 직접 존재하여 이미 Pawn relevancy를 활용하고 있으므로 이 최적화가 필요 없다.

> 이후 추가된 서버 측 최적화(Replication Graph 등)로 인해 여전히 필요한지는 불확실하며, 유지보수 측면에서도 최선의 패턴은 아니다. — Dave Ratti (Epic Games)

<a name="optimizations-asclazyloading"></a>
### 7.5 ASC Lazy Loading

Fortnite Battle Royale(FNBR)의 월드에는 ASC를 가진 파괴 가능한 오브젝트(나무, 건물 등)가 대량으로 존재하여 메모리 비용이 상당하다. FNBR은 이를 해결하기 위해 처음 플레이어에게 데미지를 받는 시점에만 ASC를 지연 로드(lazy loading)한다. 이를 통해 한 매치에서 데미지를 입지 않는 오브젝트의 ASC는 아예 생성되지 않으므로 전체 메모리 사용량이 크게 줄어든다.

---

