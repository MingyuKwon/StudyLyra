# AbilityTask 사용법

> **GASDoc**: 4.7.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-using"></a>
### 4.7.3 AbilityTask 사용법

C++에서 `AbilityTask`를 생성하고 활성화하는 방법(`GDGA_FireGun.cpp` 예시):

```c++
UGDAT_PlayMontageAndWaitForEvent* Task = UGDAT_PlayMontageAndWaitForEvent::PlayMontageAndWaitForEvent(this, NAME_None, MontageToPlay, FGameplayTagContainer(), 1.0f, NAME_None, false, 1.0f);
Task->OnBlendOut.AddDynamic(this, &UGDGA_FireGun::OnCompleted);
Task->OnCompleted.AddDynamic(this, &UGDGA_FireGun::OnCompleted);
Task->OnInterrupted.AddDynamic(this, &UGDGA_FireGun::OnCancelled);
Task->OnCancelled.AddDynamic(this, &UGDGA_FireGun::OnCancelled);
Task->EventReceived.AddDynamic(this, &UGDGA_FireGun::EventReceived);
Task->ReadyForActivation();
```

블루프린트에서는 `AbilityTask`용으로 생성한 블루프린트 노드를 사용하면 된다. `ReadyForActivation()`을 직접 호출할 필요가 없다. 이는 `Engine/Source/Editor/GameplayTasksEditor/Private/K2Node_LatentGameplayTaskCall.cpp`에서 자동으로 호출해 준다. `AbilityTask` 클래스에 `BeginSpawningActor()`와 `FinishSpawningActor()`가 존재하는 경우(`AbilityTask_WaitTargetData` 참고) 이 함수들도 `K2Node_LatentGameplayTaskCall`이 자동으로 호출해 준다. 단, `K2Node_LatentGameplayTaskCall`의 이러한 자동 처리는 블루프린트에서만 작동한다. C++에서는 `ReadyForActivation()`, `BeginSpawningActor()`, `FinishSpawningActor()`를 모두 수동으로 호출해야 한다.

![Blueprint WaitTargetData AbilityTask](https://github.com/tranek/GASDocumentation/raw/master/Images/abilitytask.png)

`AbilityTask`를 수동으로 취소하려면 블루프린트(Async Task Proxy 오브젝트)나 C++ 모두에서 `AbilityTask` 객체의 `EndTask()`를 호출하면 된다.

---

## 내 분석
