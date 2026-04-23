# Prediction Window 생성 & 액터 스폰

> **GASDoc**: 4.10.2~3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-p-windows"></a>
#### 4.10.2 Ability 내에서 새 Prediction Window 생성

`AbilityTask` 콜백에서 추가 액션을 예측하려면 새로운 Scoped Prediction Key로 새로운 Scoped Prediction Window를 생성해야 한다. 이를 클라이언트와 서버 사이의 Synch Point라고 부르기도 한다. 입력 관련 AbilityTask들은 모두 새 Scoped Prediction Window를 생성하는 기능이 내장되어 있어, `AbilityTask` 콜백의 원자적 코드에서 유효한 Scoped Prediction Key를 사용할 수 있다. `WaitDelay` 태스크 같은 경우에는 콜백에 대한 새 Scoped Prediction Window를 생성하는 내장 코드가 없다. `WaitDelay`처럼 Scoped Prediction Window를 생성하는 내장 코드가 없는 `AbilityTask` 이후에 액션을 예측해야 한다면, `OnlyServerWait` 옵션으로 `WaitNetSync` `AbilityTask`를 사용해 수동으로 처리해야 한다. 클라이언트가 `OnlyServerWait` 상태의 `WaitNetSync`에 도달하면, `GameplayAbility`의 Activation Prediction Key를 기반으로 새로운 Scoped Prediction Key를 생성하고, 이를 서버에 RPC로 전송하며, 새로 적용하는 `GameplayEffect`에 추가한다. 서버가 `OnlyServerWait` 상태의 `WaitNetSync`에 도달하면, 클라이언트로부터 새로운 Scoped Prediction Key를 받을 때까지 대기한 후 계속 실행한다. 이 Scoped Prediction Key는 Activation Prediction Key와 동일한 방식으로 `GameplayEffect`에 적용되고 클라이언트에게 복제되어 stale 처리된다. Scoped Prediction Key는 스코프를 벗어나면 만료되어 Scoped Prediction Window가 닫힌다. 따라서 원자적 연산만 새 Scoped Prediction Key를 사용할 수 있으며, latent한 연산은 사용할 수 없다.

필요한 만큼 많은 Scoped Prediction Window를 생성할 수 있다.

자신의 커스텀 `AbilityTask`에 Synch Point 기능을 추가하고 싶다면, 입력 관련 AbilityTask가 `WaitNetSync` `AbilityTask` 코드를 어떻게 주입하는지 살펴보라.

**참고:** `WaitNetSync`를 사용하면 서버의 `GameplayAbility` 실행이 클라이언트에서 응답을 받을 때까지 **블로킹**된다. 게임을 해킹한 악의적인 사용자가 의도적으로 새로운 Scoped Prediction Key 전송을 지연시켜 이를 악용할 소지가 있다. Epic은 `WaitNetSync`를 최소한으로 사용하며, 보안이 우려된다면 클라이언트 응답 없이 일정 시간 후 자동으로 계속 진행하는 딜레이가 있는 새 버전의 `AbilityTask`를 빌드하는 것을 권장한다.

샘플 프로젝트는 Sprint `GameplayAbility`에서 스태미나 비용을 적용할 때마다 `WaitNetSync`를 사용하여 새로운 Scoped Prediction Window를 생성한다. 비용(Cost)과 쿨다운(Cooldown)을 적용할 때 유효한 Prediction Key를 갖추는 것이 이상적이다.

owning 클라이언트에서 예측된 `GameplayEffect`가 두 번 재생된다면, Prediction Key가 stale 상태인 "redo 문제"를 겪고 있는 것이다. `GameplayEffect`를 적용하기 직전에 `OnlyServerWait` 옵션의 `WaitNetSync` `AbilityTask`를 추가하여 새로운 Scoped Prediction Key를 생성하면 대개 해결할 수 있다.

<a name="concepts-p-spawn"></a>
#### 4.10.3 액터 예측 스폰

클라이언트에서 `Actor`를 예측적으로 스폰하는 것은 고급 주제다. GAS는 이에 대한 기능을 기본 제공하지 않는다(`SpawnActor` `AbilityTask`는 서버에서만 `Actor`를 스폰한다). 핵심 개념은 클라이언트와 서버 **양쪽에서 복제된 `Actor`를 스폰**하는 것이다.

`Actor`가 단순히 코스메틱이거나 게임플레이 목적이 없다면, 간단한 해결책은 `Actor`의 `IsNetRelevantFor()` 함수를 오버라이드하여 서버가 owning 클라이언트에게 복제하지 못하도록 제한하는 것이다. owning 클라이언트는 로컬에서 스폰한 버전을, 서버와 다른 클라이언트들은 서버의 복제본을 사용하게 된다.

```c++
bool APAReplicatedActorExceptOwner::IsNetRelevantFor(const AActor * RealViewer, const AActor * ViewTarget, const FVector & SrcLocation) const
{
	return !IsOwnedBy(ViewTarget);
}
```

스폰된 `Actor`가 데미지 예측이 필요한 발사체처럼 게임플레이에 영향을 미친다면, 이 문서의 범위를 벗어나는 고급 로직이 필요하다. Epic Games의 GitHub에서 UnrealTournament가 발사체를 예측적으로 스폰하는 방식을 참고하라. owning 클라이언트에만 더미 발사체를 스폰하여 서버의 복제 발사체와 동기화하는 방식을 사용한다.

---

## 내 분석
