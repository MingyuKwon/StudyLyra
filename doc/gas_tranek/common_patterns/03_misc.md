# 기타 구현 패턴

> **GASDoc**: 5.5 / 5.7~9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-random"></a>
### 5.5 클라이언트와 서버에서 동일한 난수 생성

총기 반동이나 탄퍼짐처럼 GameplayAbility 내부에서 "무작위" 값이 필요한 경우가 있다. 클라이언트와 서버 모두 동일한 난수를 생성해야 한다. 이를 위해 GameplayAbility 활성화 시점에 random seed를 동일하게 설정해야 한다. 클라이언트가 활성화를 예측 실패(mispredict)하면 난수 시퀀스가 서버와 어긋날 수 있으므로, 활성화마다 seed를 재설정해야 한다.

| seed 설정 방법 | 설명 |
| ------------ | ---- |
| activation prediction key 사용 | GameplayAbility 활성화 prediction key는 int16 값으로, 클라이언트와 서버 양쪽 `Activation()` 시점에 동기화되어 있음을 보장한다. 이를 random seed로 사용할 수 있다. 단점은 prediction key가 게임 시작 시마다 0부터 순차 증가하므로, 매 매치의 난수 시퀀스가 항상 동일해진다는 것이다. 낮은 수준의 랜덤성으로 충분하다면 이 방법이 적합하다. |
| GameplayAbility 활성화 시 이벤트 페이로드로 seed 전송 | GameplayAbility를 이벤트로 활성화하고, 클라이언트가 생성한 무작위 seed를 복제되는 이벤트 페이로드에 담아 서버로 전달한다. 랜덤성은 높지만, 클라이언트가 게임을 해킹해 매번 동일한 seed 값을 보낼 수 있다는 취약점이 있다. 또한 이벤트로 GameplayAbility를 활성화하면 입력 바인딩을 통한 활성화가 불가능해진다. |

난수 편차가 크지 않다면 activation prediction key 방식으로 충분하다. 해킹 방지가 필요하고 더 복잡한 구현이 필요한 경우, Server Initiated GameplayAbility를 활용하여 서버가 seed를 생성하고 이벤트 페이로드로 전달하는 방식을 고려한다.

<a name="cae-nonstackingge"></a>
### 5.7 Non-Stacking GameplayEffect — 가장 강한 크기만 실제로 적용

Paragon의 슬로우 효과는 중첩되지 않았다. 각 슬로우 인스턴스는 고유한 수명을 유지하며 정상적으로 추적되지만, 실제로 캐릭터에 적용되는 것은 크기가 가장 큰 슬로우 효과 하나뿐이었다. GAS는 `AggregatorEvaluateMetaData`를 통해 이 시나리오를 기본적으로 지원한다. 상세 구현은 `AggregatorEvaluateMetaData()`를 참조한다.

<a name="cae-paused"></a>
### 5.8 게임 일시 정지 중 TargetData 생성

플레이어의 `WaitTargetData` AbilityTask가 실행 중인 상태에서 게임을 일시 정지해야 한다면, pause 대신 **`slomo 0`** 사용을 권장한다.

<a name="cae-onebuttoninteractionsystem"></a>
### 5.9 원버튼 상호작용 시스템

GASShooter에는 'E' 키를 누르거나 길게 눌러 상호작용 가능한 오브젝트(플레이어 소생, 무기 상자 열기, 슬라이딩 도어 개폐 등)와 상호작용하는 원버튼 인터랙션 시스템이 구현되어 있다.

---

