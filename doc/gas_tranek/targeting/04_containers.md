# GE Container Targeting

> **GASDoc**: 4.11.5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-targeting-containers"></a>
#### GE Container 타게팅은 TargetActor 방식과 비교해 어떤 장단점이 있는가?

`GameplayEffectContainer`에 내장된 타게팅 방식으로, CDO에서 실행되어 Actor 스폰·파괴가 없으므로 TargetActor보다 효율적이다.

| | GE Container 타게팅 | TargetActor 방식 |
|---|---|---|
| Actor 스폰 | 없음 (CDO에서 실행) | 매 사용마다 스폰·파괴 |
| 플레이어 입력 | 불가 | 가능 |
| 확인(confirm) | 즉시 자동 발생 | 지원 (`UserConfirmed` 등) |
| 취소 | 불가 | 가능 |
| 클라이언트→서버 데이터 전송 | 불가 (양쪽 독립 생성) | 가능 |
| 적합한 용도 | 즉각 트레이스, 콜리전 오버랩 | 플레이어 조준이 필요한 타게팅 |

Epic의 Action RPG Sample Project는 두 가지 타게팅 타입을 예시로 제공한다:
- 어빌리티 소유자를 타겟으로 하는 방식
- 이벤트에서 TargetData를 가져오는 방식

`URPGTargetType`을 C++ 또는 Blueprint에서 서브클래싱하면 커스텀 타게팅 타입을 만들 수 있다.

---
