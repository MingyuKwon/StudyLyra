# GameplayCue 배칭

> **GASDoc**: 4.8.7 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-batching"></a>
#### 4.8.7 GameplayCue 배칭

트리거되는 각 `GameplayCue`는 비신뢰성(unreliable) NetMulticast RPC다. 동시에 여러 `GC`가 발동되는 상황에서는, 이를 하나의 RPC로 압축하거나 더 적은 데이터를 전송하여 최적화하는 몇 가지 방법이 있다.

<a name="concepts-gc-batching-manualrpc"></a>
##### 4.8.7.1 수동 RPC

8발의 탄환을 발사하는 샷건을 예로 들면, 8개의 트레이스와 임팩트 `GameplayCue`가 발생한다. [GASShooter](https://github.com/tranek/GASShooter)는 모든 트레이스 정보를 `EffectContext`에 `TargetData`로 저장하여 하나의 RPC로 합치는 방식을 취했다. 이렇게 하면 RPC가 8개에서 1개로 줄어들지만, 해당 하나의 RPC에 여전히 많은 데이터가 담긴다(약 500바이트). 더 최적화된 방법은 히트 위치를 효율적으로 인코딩한 커스텀 구조체를 RPC로 전송하거나, 수신 측에서 임팩트 위치를 재현/근사할 수 있도록 랜덤 시드 번호를 전달하는 것이다. 클라이언트는 이 커스텀 구조체를 언팩하여 로컬에서 실행하는 `GameplayCue`로 변환한다.

동작 방식:
1. `FScopedGameplayCueSendContext`를 선언한다. 이는 스코프를 벗어날 때까지 `UGameplayCueManager::FlushPendingCues()`를 억제하여, 스코프가 끝날 때까지 모든 `GameplayCue`가 큐에 쌓이도록 한다.
1. `UGameplayCueManager::FlushPendingCues()`를 오버라이드하여, 커스텀 `GameplayTag`를 기반으로 함께 배칭할 수 있는 `GameplayCue`들을 커스텀 구조체 하나로 병합하고 클라이언트에 RPC로 전송한다.
1. 클라이언트는 커스텀 구조체를 언팩하여 로컬에서 실행하는 `GameplayCue`로 변환한다.

이 방법은 대미지 숫자, 크리티컬 표시, 쉴드 파괴 표시, 치명타 여부 표시 등 `GameplayCueParameters`로는 표현하기 어렵고 `EffectContext`에 추가하고 싶지도 않은 특정 파라미터가 `GameplayCue`에 필요할 때도 유용하다.

https://forums.unrealengine.com/development-discussion/c-gameplay-programming/1711546-fscopedgameplaycuesendcontext-gameplaycuemanager

<a name="concepts-gc-batching-gcsonge"></a>
##### 4.8.7.2 하나의 GE에 여러 GC 묶기

`GameplayEffect`에 등록된 모든 `GameplayCue`는 이미 하나의 RPC로 전송된다. 기본적으로 `UGameplayCueManager::InvokeGameplayCueAddedAndWhileActive_FromSpec()`은 ASC의 `Replication Mode`에 관계없이 비신뢰성 NetMulticast로 전체 `GameplayEffectSpec`(단, `FGameplayEffectSpecForRPC`로 변환된 형태)을 전송한다. `GameplayEffectSpec`의 내용에 따라 데이터량이 상당할 수 있다. cvar `AbilitySystem.AlwaysConvertGESpecToGCParams 1`을 설정하면 `GameplayEffectSpec`을 `FGameplayCueParameter` 구조체로 변환하여 전체 `FGameplayEffectSpecForRPC` 대신 이 구조체를 RPC로 전송하는 방식으로 최적화할 수 있다. 이 방식은 잠재적으로 대역폭을 절약하지만, `GESpec`이 `GameplayCueParameters`로 변환되는 방식과 `GC`가 필요로 하는 정보에 따라 일부 정보가 손실될 수 있다.

---

