# Dave Ratti Q&A

> **GASDoc**: 11 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="resources-daveratti"></a>
### Epic Games Dave Ratti가 GAS 설계·예측·최적화에 대해 어떤 입장을 밝혔는가?

아래는 Dave Ratti(Epic Games)가 커뮤니티 질문에 직접 답변한 내용을 주제별로 요약한 것이다.

<a name="resources-daveratti-community1"></a>
#### 커뮤니티 질문 1 — 예측·WaitNetSync 보안·Replication Mode·GE 제거·ASC 배치에 대한 Dave Ratti의 답변은?

**1. fire-and-forget 발사체 피격 시 데미지 GE를 로컬 예측할 수 있는가?**

PredictionKey 시스템은 이 용도로 설계되지 않았다. 발사체에는 Non-Replicated GameplayCue를 사용하는 것이 Paragon/Fortnite의 방식이다. `UGameplayCueManager::HandleGameplayCue`를 ASC를 거치지 않고 직접 호출하므로 prediction key 검사가 없다. 단점은 복제가 되지 않으므로 BeginPlay·충돌·폭발 이벤트처럼 모든 클라이언트에서 동일한 코드 경로가 실행되어야 한다.

**2. WaitNetSync(OnlyServerWait)를 쓰는 어빌리티는 패킷 지연 치트에 취약한가?**

타당한 우려다. Paragon은 즉발 타겟팅 어빌리티에 클라이언트 대기 최대 시간(timeout)을 두었고, 시간 초과 시 서버에서 직접 타겟 데이터를 생성하거나 어빌리티를 취소했다. Fortnite의 무기 어빌리티는 활성화·TargetData·종료를 단일 RPC로 배칭하므로 구조적으로 이 취약점에 노출되지 않는다. WaitNetSync에 최대 지연 시간을 추가하는 수정은 합리적이지만 당장 구현 계획은 없다.

**3. Paragon/Fortnite의 Replication Mode 설정은?**

플레이어 제어 캐릭터는 Mixed, AI 제어 캐릭터는 Minimal. 멀티플레이어 게임의 기본 권장 설정이며 프로젝트 초기에 설정할수록 좋다.

**4. GE 제거 레이턴시(이동 속도 슬로우 제거 후 위치 튐)를 줄이는 방법이 있는가?**

딱 떨어지는 답이 없다. 일반적으로 허용 오차와 스무딩으로 회피했다. GE 예측적 제거를 시도했지만 CharacterMovementComponent 내부의 saved move 버퍼가 GE를 모르기 때문에 수정 피드백 루프 문제가 남는다. 절박하다면 이동 속도 GE를 억제하는 GE를 예측적으로 추가하는 방법을 이론적으로 검토할 수 있다.

**5. ASC를 PlayerState와 Character 중 어디에 두어야 하는가?**

| 상황 | 권장 배치 |
|---|---|
| 리스폰 없는 액터 (AI 적, 건물, 월드 프롭) | Owner Actor = Avatar Actor (동일) |
| 리스폰이 필요한 플레이어 | PlayerState에 배치 — 리스폰 후 ASC 재생성 불필요 |

PlayerState는 모든 클라이언트에 복제되므로 논리적 선택이다. 단, PlayerState는 항상 relevant이므로 100명 이상 게임에서는 별도 최적화(Proxy Struct 등)가 필요하다.

**6. 같은 Owner에 여러 ASC를 두는 것이 실용적인가?**

복잡해질 수 있다. `IGameplayTagAssetInterface` 구현 시 여러 ASC의 태그를 집계해야 하고, `IAbilitySystemInterface`는 어느 ASC가 권위를 갖는지 결정하기 어렵다. Pawn과 무기에 각각 별도 ASC를 두는 것은(태그 분리 목적으로) 가능하지만, 같은 Owner 아래 여러 ASC 구조는 복잡도가 상당히 높아진다.

**7. 레이턴시가 높은 플레이어의 쿨다운 불이익을 막을 방법이 있는가?**

없다. Paragon도 레이턴시가 높은 연결에서 기본 공격의 분당 공격 횟수가 더 낮았다. "GE reconciliation"(레이턴시를 반영해 GE 지속 시간 조정)을 시도했지만 출시 가능한 수준으로 구현하지 못했다. Fortnite는 무기 발사 속도에 GE를 사용하지 않는 자체 방식을 사용한다. 심각한 문제라면 이 방식을 권장한다.

**8. GAS의 향후 로드맵은?**

현재 시스템은 안정적이며 주요 신기능 개발 인원이 없다. 장기적으로 "V2"를 고려 중이며 업그레이드 경로를 제공할 것이다.

우선순위 높은 수정 사항:
- 캐릭터 이동 시스템과의 상호 운용성 개선, 클라이언트 예측 통합
- GE 제거 예측
- GE 레이턴시 reconciliation
- RPC 배칭·proxy 구조 등 일반화된 네트워크 최적화

고려 중인 리팩터링:
- GE가 커브 테이블 행에 강하게 결합되는 문제 해결 → 파라미터화 시스템 도입
- `ReplicationPolicy`와 `InstancingPolicy` 제거, `FGameplayAbilitySpec`의 서브클래싱 가능한 UObject로 대체
- "filtered GE application container", "Overlapping volume support" 등 중간 레벨 구성 요소 기본 제공
- 보일러플레이트 감소를 위한 선택적 모듈 ("Ex library")
- GameplayCue를 Ability System과 분리된 별도 모듈로 이동

---

<a name="resources-daveratti-community2"></a>
#### 커뮤니티 질문 2 — Network Prediction Plugin의 GAS 통합 계획과 비동기 물리 틱에 대한 Dave Ratti의 답변은?

**1. 렌더링 프레임 속도와 Game Thread 틱을 분리할 계획이 있는가?**

렌더링과 Game Thread 틱을 분리할 계획은 없다. 대신 Game Thread와 독립적으로 고정 틱 속도로 실행되는 비동기 "Physics Thread"를 두는 방향으로 나아가고 있다. Network Prediction은 Independent Ticking(가변 프레임, 고전적 모델)과 Fixed Ticking(async 물리 활용, 다른 클라이언트 Actor도 예측 가능) 두 모드를 지원한다.

**2. Network Prediction을 GAS에 통합할 계획이 있는가?**

있다. ASC의 prediction key 시스템을 재작성하고 Network Prediction 구조로 대체할 계획이다. 핵심 아이디어는 명시적인 클라이언트→서버 Prediction Key 교환을 없애고, 모든 것을 NetworkPrediction 프레임 기준으로 앵커링하는 것이다. 이렇게 되면 어빌리티 활성화·종료·GE 적용 제거·Attribute 값을 특정 프레임 기준으로 일치시킬 수 있다. 다만 이동·물리 기반이 탄탄해져야 상위 레벨 시스템을 변경할 수 있으므로 순서가 중요하다.

**3. Network Prediction을 메인 브랜치로 옮길 계획이 있는가?**

그 방향으로 작업 중이다. 현재는 async 물리 관련 내용(RewindData.h 등)이 이용 가능하다. 초기에는 "front end"(상태·시뮬레이션 정의 방식)에 집중했지만, 이제는 실제 작동하는 시스템을 먼저 완성한 뒤 front end를 개선하는 방식으로 접근하고 있다.

**4. 제거된 GameplayMessages 플러그인이 복원되는가?**

언젠가 돌아올 것 같다. API가 완성되지 않아 아직 공개 의도가 없었다. 모듈형 게임플레이 설계에 유용하다는 데 동의한다.

**5. async 고정 물리 틱의 현재 상태와 보일러플레이트 문제는?**

async 물리가 활성화되면 Game Thread는 가변 틱으로, 물리·핵심 게임플레이 시뮬레이션(캐릭터 이동, GAS 등)은 고정 속도로 실행할 수 있다. 활성화 cvar:
```
p.DefaultAsyncDt=0.03333
p.RewindCaptureNumFrames=64
```
물리 상태 보간은 Chaos가 제공하며(`p.AsyncInterpolationMultiplier` cvar 참고), 물리 이외의 상태 보간은 현재 직접 구현해야 한다. 보일러플레이트 문제는 인식하고 있으며, 결국 reflection 시스템을 활용해 NetSerialize·ShouldReconcile·Interpolate를 수동으로 작성하지 않아도 되는 방식을 제공할 예정이다. Async CharacterMovementComponent는 현재 네트워킹 지원이 없는 초기 프로토타입이므로 따르는 것을 권장하지 않는다.

---
