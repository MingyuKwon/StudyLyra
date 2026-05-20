# Cue 이벤트 & 신뢰성

> **GASDoc**: 4.8.8~9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-events"></a>
#### OnActive, WhileActive, Removed, Executed의 차이는 무엇이며 각각 언제 사용해야 하는가?

| `EGameplayCueEvent` | 호출 시점 | 사용 용도 |
| --- | --- | --- |
| `OnActive` | GameplayCue가 활성화(추가)될 때 | 초기 폭발 파티클·사운드처럼 늦게 접속한 플레이어가 놓쳐도 되는 시작 효과 |
| `WhileActive` | 활성 상태일 때 (방금 적용된 것이 아니어도). Tick이 아닌 단발 호출 | 잔류 불꽃·루핑 사운드처럼 늦게 접속한 플레이어도 봐야 하는 지속 효과 |
| `Removed` | GameplayCue가 제거될 때 (`OnRemove` 블루프린트 함수) | `OnActive`/`WhileActive`에서 추가한 모든 것 정리 |
| `Executed` | Instant/Periodic GameplayCue 실행 시 (`OnExecute` 블루프린트 함수) | 즉발·주기적 효과 처리 |

**설계 지침**: `OnActive`는 시작 시 한 번만 필요한 효과, `WhileActive`는 늦게 접속해도 보여야 하는 효과에 배치한다. `WhileActive`는 Actor가 GameplayCueNotify_Actor의 관련성 범위에 들어올 때마다 호출되며, `OnRemove`는 관련성 범위를 벗어날 때마다 호출된다.

<a name="concepts-gc-reliability"></a>
#### GameplayCue의 이벤트별 복제 신뢰성은 어떻게 다르며 신뢰성 있는 Cue 효과가 필요할 때 어떻게 해야 하는가?

GameplayCue는 기본적으로 **비신뢰성**으로 취급해야 하며, 게임플레이에 직접 영향을 주는 로직에는 사용하지 않는다.

| 적용 방식 | Proxy 유형 | 신뢰성 있는 이벤트 |
| --- | --- | --- |
| 실행된(Executed) GC | 모두 | 없음 (항상 비신뢰성 멀티캐스트) |
| GE를 통해 적용된 GC | Autonomous proxy | `OnActive`, `WhileActive`, `OnRemove` |
| GE를 통해 적용된 GC | Simulated proxy | `WhileActive`, `OnRemove` (`OnActive`는 비신뢰성) |
| GE 없이 적용된 GC | Autonomous proxy | `OnRemove` (`OnActive`, `WhileActive`는 비신뢰성) |
| GE 없이 적용된 GC | Simulated proxy | `WhileActive`, `OnRemove` (`OnActive`는 비신뢰성) |

**신뢰성 있는 효과가 필요하다면**: GameplayEffect를 통해 GC를 적용하고, `WhileActive`에서 FX를 추가하고 `OnRemove`에서 FX를 제거하는 방식을 사용한다.

---
