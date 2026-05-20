# Prediction 미래 & Network Prediction Plugin

> **GASDoc**: 4.10.4~5 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-p-future"></a>
#### 현재 GAS 예측 시스템의 한계는 무엇이며 앞으로 개선이 예고된 기능은?

현재 예측되지 않는 두 가지 핵심 기능이 향후 추가될 수 있다고 `GameplayPrediction.h`에 명시되어 있다:
- `GameplayEffect` 제거(removal) 예측
- 주기적(periodic) `GameplayEffect` 예측

또한 Epic의 Dave Ratti는 쿨다운 예측의 **레이턴시 보정(latency reconciliation)** 문제 — 레이턴시가 높은 플레이어가 낮은 플레이어에 비해 불리해지는 문제 — 를 수정하는 데 관심을 표명한 바 있다.

<a name="concepts-p-npp"></a>
#### Network Prediction Plugin은 GAS의 예측 시스템을 어떻게 대체할 것으로 기대되는가?

Epic이 `CharacterMovementComponent`를 대체하기 위해 개발 중인 새로운 `Network Prediction` 플러그인이다. 과거 `CharacterMovementComponent`가 GAS와 상호운용되었듯, 이 플러그인도 GAS와 완전히 상호운용(interoperable)될 것으로 기대된다. 현재는 매우 초기 단계로 Unreal Engine GitHub에서 얼리 액세스로 이용할 수 있으며, 어느 버전에서 정식 실험적 베타로 데뷔할지는 아직 미정이다.

---
