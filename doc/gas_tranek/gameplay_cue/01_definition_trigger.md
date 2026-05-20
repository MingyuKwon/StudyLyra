# GameplayCue 정의 & 트리거

> **GASDoc**: 4.8.1~2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-definition"></a>
#### GameplayCue란 무엇이며 GameplayAbility·GE와 어떻게 연결되는가?

`GameplayCue`(`GC`)는 사운드, 파티클, 카메라 흔들림 등 **게임플레이 로직과 무관한 시각·청각 효과**를 실행하는 시스템이다. 기본적으로 복제(replicated)되며 예측(prediction)도 지원한다.

트리거 방식: `GameplayCue.`로 시작하는 `GameplayTag`와 이벤트 타입(`Execute`, `Add`, `Remove`)을 ASC를 통해 `GameplayCueManager`에 전달한다. `GameplayCueNotify` 오브젝트 또는 `IGameplayCueInterface`를 구현한 Actor는 해당 태그를 구독하여 이벤트에 반응한다.

> `GameplayCue`의 태그는 반드시 `GameplayCue`를 부모로 시작해야 한다. 예: `GameplayCue.A.B.C`

`GameplayCueNotify`는 두 종류이며, 용도에 따라 구분한다:

| 클래스 | 이벤트 | GE 타입 | 특징 |
| --- | --- | --- | --- |
| `GameplayCueNotify_Static` | `Execute` | Instant / Periodic | CDO에서 동작(인스턴스 없음). 히트 임팩트 같은 일회성 효과에 적합 |
| `GameplayCueNotify_Actor` | `Add` / `Remove` | Duration / Infinite | `Added` 시 인스턴스를 스폰하고, `Removed`될 때까지 지속 효과가 가능. 루핑 사운드·파티클에 적합 |

> `GameplayCueNotify_Actor` 사용 시 `Auto Destroy on Remove`를 반드시 체크해야 한다. 체크하지 않으면 이후 동일 태그로 `Add` 호출이 동작하지 않는다.

`Full` 이외의 ASC Replication Mode에서는, `Add`/`Remove` GC 이벤트가 서버(리슨 서버)에서 두 번 발생한다. 한 번은 GE 적용 시, 한 번은 클라이언트 `NetMultiCast`를 통해서다. `WhileActive`는 여전히 한 번만 발생한다.

<a name="concepts-gc-trigger"></a>
#### GameplayCue는 GameplayEffect와 GameplayAbility에서 각각 어떻게 트리거하는가?

**GameplayEffect에서**: GE 내 GameplayCue 태그 컨테이너에 트리거할 `GameplayCueTag`를 채워 넣는다. GE가 성공적으로 적용될 때 자동으로 트리거된다.

**GameplayAbility에서**: `Execute`, `Add`, `Remove` 블루프린트 노드를 제공한다.

**C++에서**: ASC의 함수를 직접 호출한다:

```c++
void ExecuteGameplayCue(const FGameplayTag GameplayCueTag, FGameplayEffectContextHandle EffectContext = FGameplayEffectContextHandle());
void ExecuteGameplayCue(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

void AddGameplayCue(const FGameplayTag GameplayCueTag, FGameplayEffectContextHandle EffectContext = FGameplayEffectContextHandle());
void AddGameplayCue(const FGameplayTag GameplayCueTag, const FGameplayCueParameters& GameplayCueParameters);

void RemoveGameplayCue(const FGameplayTag GameplayCueTag);

/** GE 없이 단독으로 추가된 GameplayCue를 모두 제거 */
void RemoveAllGameplayCues();
```

---
