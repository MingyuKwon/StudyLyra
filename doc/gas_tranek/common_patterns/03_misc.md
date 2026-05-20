# 기타 구현 패턴

> **GASDoc**: 5.5 / 5.7~9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="cae-random"></a>
### GA 내에서 클라이언트와 서버가 동일한 난수를 생성해야 할 때 어떤 방법을 쓰는가?

총기 반동·탄퍼짐처럼 GA 내부에서 클라이언트와 서버가 동일한 난수를 생성해야 할 때는 활성화 시점에 동일한 random seed를 설정해야 한다.

| 방법 | 설명 | 단점 |
| --- | --- | --- |
| Activation Prediction Key 사용 | 클라이언트와 서버 `Activation()` 시점에 동기화된 int16 값. random seed로 사용 가능 | 게임 시작 시마다 0부터 순차 증가하여 매 매치 난수 시퀀스가 동일함 |
| 이벤트 페이로드로 seed 전송 | 클라이언트가 무작위 seed를 생성해 복제 이벤트 페이로드에 담아 서버로 전달 | 클라이언트가 고정 seed를 반복 전송하는 방식으로 해킹 가능. 이벤트 활성화이므로 입력 바인딩 불가 |

난수 편차가 크지 않다면 Activation Prediction Key 방식으로 충분하다. 해킹 방지가 필요하면 Server Initiated GameplayAbility로 서버가 seed를 생성해 이벤트 페이로드로 전달하는 방식을 고려한다.

<a name="cae-nonstackingge"></a>
### 여러 슬로우 효과 중 가장 강한 것만 실제로 적용되는 Non-Stacking 패턴은 어떻게 구현하는가?

각 슬로우 인스턴스는 고유한 수명을 유지하며 정상적으로 추적하되, 실제로 캐릭터에 적용되는 것은 크기가 가장 큰 슬로우 하나뿐이다. GAS는 `AggregatorEvaluateMetaData`를 통해 이 시나리오를 기본 지원한다. 상세 구현은 `AggregatorEvaluateMetaData()`를 참조한다.

<a name="cae-paused"></a>
### WaitTargetData 실행 중 게임을 일시 정지하려면 pause 대신 어떤 방법을 써야 하는가?

`WaitTargetData` AbilityTask가 실행 중인 상태에서는 pause 대신 **`slomo 0`** 을 사용한다.

<a name="cae-onebuttoninteractionsystem"></a>
### 원버튼으로 여러 오브젝트와 상호작용하는 시스템은 GAS에서 어떻게 구현하는가?

GASShooter에서 구현된 방식: `E` 키를 누르거나 길게 눌러 플레이어 소생, 무기 상자 열기, 슬라이딩 도어 개폐 등 다양한 오브젝트와 상호작용한다. GASShooter의 인터랙션 시스템 구현을 참고하라.

---
