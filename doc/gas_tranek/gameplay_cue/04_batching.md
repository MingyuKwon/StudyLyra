# GameplayCue 배칭

> **GASDoc**: 4.8.7 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-batching"></a>
#### 동시에 여러 GameplayCue가 발동될 때 RPC를 줄이려면 어떤 배칭 방법을 쓰는가?

각 GameplayCue는 비신뢰성(unreliable) NetMulticast RPC다. 동시에 여러 GC가 발동될 때 RPC를 줄이는 방법은 두 가지다.

<a name="concepts-gc-batching-manualrpc"></a>
##### 수동 RPC로 여러 GameplayCue를 하나로 묶는 방법은?

8발 탄환 샷건을 예로 들면, 기본적으로 8개의 RPC가 발생한다. 이를 하나의 커스텀 RPC로 압축하는 흐름:

1. `FScopedGameplayCueSendContext`를 선언한다. 스코프를 벗어날 때까지 `UGameplayCueManager::FlushPendingCues()` 호출을 억제하여, 모든 GameplayCue를 큐에 쌓는다.
2. `UGameplayCueManager::FlushPendingCues()`를 오버라이드한다. 배칭 대상 GameplayCue들을 커스텀 구조체 하나로 병합하고 클라이언트에 RPC로 전송한다.
3. 클라이언트는 커스텀 구조체를 언팩하여 로컬 GameplayCue로 변환한다.

이 방법은 데미지 숫자, 크리티컬 표시, 쉴드 파괴 표시처럼 `GameplayCueParameters`로는 표현하기 어렵고 `EffectContext`에 넣기도 애매한 파라미터가 필요할 때도 유용하다.

참고: https://forums.unrealengine.com/development-discussion/c-gameplay-programming/1711546-fscopedgameplaycuesendcontext-gameplaycuemanager

<a name="concepts-gc-batching-gcsonge"></a>
##### 하나의 GameplayEffect에 여러 GameplayCue를 등록하면 RPC가 몇 번 발생하는가?

하나의 RPC로 전송된다. `UGameplayCueManager::InvokeGameplayCueAddedAndWhileActive_FromSpec()`은 ASC Replication Mode에 관계없이 비신뢰성 NetMulticast로 전체 `FGameplayEffectSpecForRPC`를 한 번만 전송한다.

대역폭 최적화가 필요하다면 cvar `AbilitySystem.AlwaysConvertGESpecToGCParams 1`을 설정한다. `FGameplayEffectSpecForRPC` 대신 더 작은 `FGameplayCueParameter` 구조체로 변환해 전송하므로 대역폭을 절약할 수 있다. 단, 변환 과정에서 일부 정보가 손실될 수 있다.

---
