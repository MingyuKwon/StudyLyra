# GAS 최적화

> **GASDoc**: 7 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="optimizations"></a>
## GAS 멀티플레이어 프로젝트에서 네트워크 비용을 줄이는 주요 최적화 기법은?

<a name="optimizations-abilitybatching"></a>
### 단일 프레임에서 활성화·종료가 이루어지는 GA의 RPC를 어떻게 배칭하는가?

활성화 → TargetData 전송 → 종료가 단일 프레임 내에 모두 완료되는 GA는 2~3개의 RPC를 1개로 묶을 수 있다. 히트스캔 총기류가 대표적인 적용 사례다.

<a name="optimizations-gameplaycuebatching"></a>
### 여러 GameplayCue가 동시에 발생할 때 RPC를 줄이는 방법은?

동시에 여러 GameplayCue를 발생시킨다면 하나의 RPC로 배칭한다. GameplayCue는 unreliable NetMulticast로 전송되므로 RPC 수와 전송 데이터를 최소화하는 것이 목표다.

<a name="optimizations-ascreplicationmode"></a>
### 플레이어 ASC와 AI ASC에 각각 어떤 Replication Mode를 설정해야 하며 그 이유는?

| 대상 | 권장 모드 | 효과 |
|---|---|---|
| 플레이어 소유 ASC | Mixed | GE를 해당 플레이어의 오너 클라이언트에만 복제 |
| AI 제어 캐릭터 ASC | Minimal | GE를 클라이언트에 전혀 복제하지 않음 |

GameplayTag 복제와 GameplayCue의 unreliable NetMulticast 전달은 Replication Mode와 무관하게 동작한다. 기본값인 `Full` 모드는 모든 GE를 모든 클라이언트에 복제하므로 멀티플레이어에서 불필요한 네트워크 데이터를 유발한다. 프로젝트 초기에 설정할수록 좋다.

<a name="optimizations-attributeproxyreplication"></a>
### Fortnite는 대규모 플레이어의 Attribute 복제 병목을 어떻게 Proxy Struct로 해결했는가?

PlayerState는 항상 relevant이므로 100명 규모에서 모든 ASC가 Attribute를 직접 복제하면 병목이 된다. Fortnite의 해결 방법:

1. `PlayerState::ReplicateSubobjects()`에서 simulated proxy의 ASC와 AttributeSet을 복제 대상에서 완전히 제외한다.
2. 플레이어 Pawn에 별도의 proxy struct를 두고, 서버 ASC의 Attribute가 변경될 때 proxy struct에도 동기화한다.
3. 클라이언트는 proxy struct에서 Attribute를 수신해 로컬 ASC에 반영한다.

이를 통해 Attribute 복제가 PlayerState의 relevancy 대신 Pawn의 relevancy와 NetUpdateFrequency를 따르게 된다.

> Replication Graph 등 이후 서버 최적화로 인해 여전히 필요한지는 불확실하며, 유지보수 측면에서도 최선의 패턴은 아니다. — Dave Ratti (Epic Games)

<a name="optimizations-asclazyloading"></a>
### 월드에 대량의 ASC 보유 오브젝트가 있을 때 메모리를 줄이려면 어떻게 지연 로드하는가?

Fortnite의 파괴 가능한 오브젝트(나무, 건물 등)처럼 ASC가 대량으로 존재하는 경우, 처음 플레이어에게 데미지를 받는 시점에 ASC를 생성한다. 한 매치에서 데미지를 입지 않는 오브젝트의 ASC는 아예 생성되지 않으므로 전체 메모리 사용량이 크게 줄어든다.

---
