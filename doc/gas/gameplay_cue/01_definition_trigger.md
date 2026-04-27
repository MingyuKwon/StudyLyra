# GameplayCue 정의 & 트리거

> **GASDoc**: 4.8.1~2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gc-definition"></a>
#### 4.8.1 GameplayCue 정의

`GameplayCues` (`GC`)는 사운드 이펙트, 파티클 이펙트, 카메라 흔들림 등 게임플레이와 직접 관련 없는 효과를 실행한다. `GameplayCues`는 명시적으로 로컬에서 `Executed`, `Added`, `Removed`되지 않는 한 일반적으로 복제(replicated)되며, 예측(predicted)도 지원한다.

`GameplayCues`는 **반드시 `GameplayCue.`로 시작하는 부모 이름**을 가진 `GameplayTag`와 이벤트 타입(`Execute`, `Add`, `Remove`)을 ASC를 통해 `GameplayCueManager`로 전달함으로써 트리거된다. `GameplayCueNotify` 오브젝트 및 `IGameplayCueInterface`를 구현한 다른 `Actor`들은 `GameplayCue`의 `GameplayTag`(`GameplayCueTag`)를 기반으로 해당 이벤트를 구독하여 반응할 수 있다.

> **참고**  
> 다시 한번 강조하지만, `GameplayCue`의 `GameplayTag`는 반드시 부모 `GameplayTag`인 `GameplayCue`로 시작해야 한다. 예를 들어 유효한 `GameplayCue` `GameplayTag`는 `GameplayCue.A.B.C`와 같은 형태다.

`GameplayCueNotify`에는 `Static`과 `Actor` 두 가지 클래스가 있다. 각각 서로 다른 이벤트에 반응하며, 서로 다른 타입의 `GameplayEffect`가 이를 트리거할 수 있다. 해당 이벤트에 맞는 로직으로 오버라이드하여 사용한다.

| `GameplayCue` 클래스 | 이벤트 | `GameplayEffect` 타입 | 설명 |
| --- | --- | --- | --- |
| [`GameplayCueNotify_Static`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UGameplayCueNotify_Static/index.html) | `Execute` | `Instant` 또는 `Periodic` | Static `GameplayCueNotify`는 `ClassDefaultObject`(인스턴스 없음)에서 동작하며, 히트 임팩트처럼 일회성 효과에 적합하다. |
| [`GameplayCueNotify_Actor`](https://docs.unrealengine.com/en-US/BlueprintAPI/GameplayCueNotify/index.html) | `Add` 또는 `Remove` | `Duration` 또는 `Infinite` | Actor `GameplayCueNotify`는 `Added`될 때 새 인스턴스를 스폰한다. 인스턴스가 존재하므로 `Removed`될 때까지 시간에 걸친 동작이 가능하다. Duration 또는 Infinite `GameplayEffect`가 제거되거나 수동으로 Remove를 호출할 때 함께 제거되는 루핑 사운드나 파티클 이펙트에 적합하다. 동시에 `Added`될 수 있는 수를 관리하는 옵션도 있어, 동일 효과가 여러 번 적용되어도 사운드나 파티클이 한 번만 시작되도록 할 수 있다. |

`GameplayCueNotify`는 기술적으로 어떤 이벤트에도 반응할 수 있지만, 일반적으로 위와 같이 사용한다.

> **참고**  
> `GameplayCueNotify_Actor`를 사용할 때는 `Auto Destroy on Remove`를 반드시 체크해야 한다. 그렇지 않으면 이후에 동일한 `GameplayCueTag`로 `Add`를 호출해도 동작하지 않는다.

`Full` 이외의 ASC Replication Mode를 사용할 때, `Add` 및 `Remove` `GC` 이벤트는 서버 플레이어(리슨 서버)에서 두 번 발생한다. 한 번은 `GE` 적용 시, 또 한 번은 클라이언트에게 "Minimal" `NetMultiCast`를 통해서다. 단, `WhileActive` 이벤트는 여전히 한 번만 발생한다. 클라이언트에서는 모든 이벤트가 한 번씩만 발생한다.

샘플 프로젝트에는 스턴과 스프린트 효과를 위한 `GameplayCueNotify_Actor`와, FireGun의 발사체 임팩트를 위한 `GameplayCueNotify_Static`이 포함되어 있다. 이 `GC`들은 `GE`를 통해 복제하는 대신 로컬에서 트리거하는 방식으로 추가 최적화가 가능하다. 샘플 프로젝트에서는 초보자 친화적인 방식을 보여주기 위해 이 방식을 선택했다.

<a name="concepts-gc-trigger"></a>
#### 4.8.2 GameplayCue 트리거

`GameplayEffect`가 성공적으로 적용될 때(태그에 의해 차단되거나 면역 상태가 아닌 경우), 트리거되어야 하는 모든 `GameplayCue`의 `GameplayTag`를 `GameplayEffect` 내 `GameplayCue` 태그 컨테이너에 채워 넣는다.

![GameplayCue Triggered from a GameplayEffect](https://github.com/tranek/GASDocumentation/raw/master/Images/gcfromge.png)

`UGameplayAbility`는 `GameplayCue`를 `Execute`, `Add`, `Remove`하는 블루프린트 노드를 제공한다.

![GameplayCue Triggered from a GameplayAbility](https://github.com/tranek/GASDocumentation/raw/master/Images/gcfromga.png)

C++에서는 ASC의 함수를 직접 호출하거나(또는 ASC 서브클래스에서 블루프린트에 노출), 다음과 같이 사용할 수 있다:

```c++
/** GameplayCues can also come on their own. These take an optional effect context to pass through hit result, etc */
void ExecuteGameplayCue(const FGameplayTag GameplayCueTag, FGameplayEffectContextHandle EffectContext = FGameplayEffectContextHandle());
void ExecuteGameplayCue(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

/** Add a persistent gameplay cue */
void AddGameplayCue(const FGameplayTag GameplayCueTag, FGameplayEffectContextHandle EffectContext = FGameplayEffectContextHandle());
void AddGameplayCue(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

/** Remove a persistent gameplay cue */
void RemoveGameplayCue(const FGameplayTag GameplayCueTag);
	
/** Removes any GameplayCue added on its own, i.e. not as part of a GameplayEffect. */
void RemoveAllGameplayCues();
```

---

## 내 분석
