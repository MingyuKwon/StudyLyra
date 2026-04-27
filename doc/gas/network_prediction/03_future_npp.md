# Prediction 미래 & Network Prediction Plugin

> **GASDoc**: 4.10.4~5 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-p-future"></a>
#### 4.10.4 GAS 예측의 미래

`GameplayPrediction.h`에는 향후 `GameplayEffect` 제거(removal) 예측 및 주기적(periodic) `GameplayEffect` 예측 기능이 추가될 수 있다는 내용이 명시되어 있다.

Epic의 Dave Ratti는 쿨다운 예측에서 발생하는 `latency reconciliation` 문제 — 레이턴시가 높은 플레이어가 낮은 플레이어에 비해 불리해지는 문제 — 를 수정하는 데 [관심을 표명](https://epicgames.ent.box.com/s/m1egifkxv3he3u3xezb9hzbgroxyhx89)한 바 있다.

새로운 `Network Prediction` 플러그인은 과거 `CharacterMovementComponent`가 그랬듯 GAS와 완전히 상호운용(interoperable)될 것으로 기대된다.

<a name="concepts-p-npp"></a>
#### 4.10.5 Network Prediction Plugin

Epic은 최근 `CharacterMovementComponent`를 대체하기 위한 새로운 `Network Prediction` 플러그인 개발 이니셔티브를 시작했다. 이 플러그인은 아직 매우 초기 단계이지만 Unreal Engine GitHub에서 얼리 액세스로 이용할 수 있다. 어느 미래 엔진 버전에서 실험적 베타로 정식 데뷔할지는 아직 판단하기 이르다.

---

## 내 분석
