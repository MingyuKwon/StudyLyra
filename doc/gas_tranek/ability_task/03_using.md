# AbilityTask 사용법

> **GASDoc**: 4.7.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-at-using"></a>
### C++와 Blueprint에서 AbilityTask를 생성하고 활성화하는 방법은 어떻게 다른가?

**C++** — 팩토리 함수로 생성 후 델리게이트를 수동 바인딩하고, 마지막에 `ReadyForActivation()`을 직접 호출해야 한다.

```cpp
UGDAT_PlayMontageAndWaitForEvent* Task = UGDAT_PlayMontageAndWaitForEvent::PlayMontageAndWaitForEvent(
    this, NAME_None, MontageToPlay, FGameplayTagContainer(), 1.0f, NAME_None, false, 1.0f);
Task->OnBlendOut.AddDynamic(this, &UGDGA_FireGun::OnCompleted);
Task->OnCompleted.AddDynamic(this, &UGDGA_FireGun::OnCompleted);
Task->OnInterrupted.AddDynamic(this, &UGDGA_FireGun::OnCancelled);
Task->OnCancelled.AddDynamic(this, &UGDGA_FireGun::OnCancelled);
Task->EventReceived.AddDynamic(this, &UGDGA_FireGun::EventReceived);
Task->ReadyForActivation();
```

**Blueprint** — 전용 잠재 노드를 사용하면 된다. `ReadyForActivation()`은 `K2Node_LatentGameplayTaskCall`이 자동으로 호출한다. `BeginSpawningActor()`·`FinishSpawningActor()`가 있는 태스크(`AbilityTask_WaitTargetData` 등)도 동일하게 자동 처리된다.

> C++에서는 `ReadyForActivation()`, `BeginSpawningActor()`, `FinishSpawningActor()` 모두 수동으로 호출해야 한다.

AbilityTask를 수동으로 취소하려면 C++과 Blueprint 모두 태스크 객체의 `EndTask()`를 호출한다.
