# Root Motion Source Task

> **GASDoc**: 4.7.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-rms"></a>
### 4.7.4 Root Motion Source AbilityTask

GAS는 `CharacterMovementComponent`에 연결된 `Root Motion Source`를 활용해 넉백, 복잡한 점프, 끌어당기기, 대시 같은 동작을 위해 시간에 걸쳐 캐릭터를 이동시키는 `AbilityTask`를 기본으로 제공한다.

**참고:** `RootMotionSource` `AbilityTask`의 Prediction은 엔진 버전 4.19와 4.25 이상에서 정상 동작한다. 4.20~4.24 엔진 버전에서는 Prediction에 버그가 있다. 단, `AbilityTask` 자체는 멀티플레이어에서 소폭의 네트워크 보정을 동반하면서도 기능은 수행하며, 싱글플레이어에서는 완벽하게 동작한다. 4.20~4.24 커스텀 엔진을 사용하는 경우 4.25의 [prediction fix](https://github.com/EpicGames/UnrealEngine/commit/94107438dd9f490e7b743f8e13da46927051bf33#diff-65f6196f9f28f560f95bd578e07e290c) 커밋을 cherry-pick으로 적용하는 것도 가능하다.

---

## 내 분석
