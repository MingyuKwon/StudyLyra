# Root Motion Source Task

> **GASDoc**: 4.7.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-at-rms"></a>
### RootMotionSource AbilityTask는 어떤 동작을 처리하며, 멀티플레이어에서 Prediction 버그가 있는 버전은?

GAS는 `CharacterMovementComponent`에 연결된 `Root Motion Source`를 활용해 넉백, 복잡한 점프, 끌어당기기, 대시 같이 시간에 걸쳐 캐릭터를 이동시키는 AbilityTask를 기본으로 제공한다.

**엔진 버전별 Prediction 상태:**

| 버전 | 상태 |
|---|---|
| 4.19 | 정상 동작 |
| 4.20 ~ 4.24 | Prediction 버그 있음 (태스크 자체는 동작하나 네트워크 보정 발생, 싱글플레이어는 문제없음) |
| 4.25 이상 | 정상 동작 |

4.20~4.24 커스텀 엔진을 사용하는 경우 4.25의 [prediction fix](https://github.com/EpicGames/UnrealEngine/commit/94107438dd9f490e7b743f8e13da46927051bf33#diff-65f6196f9f28f560f95bd578e07e290c) 커밋을 cherry-pick으로 적용할 수 있다.
