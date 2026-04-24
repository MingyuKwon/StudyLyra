# 커스텀 AbilityTask

> **GASDoc**: 4.7.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-definition"></a>
### 4.7.2 커스텀 AbilityTask

대부분의 경우 C++로 커스텀 `AbilityTask`를 직접 작성하게 된다. 샘플 프로젝트에는 두 가지 커스텀 `AbilityTask`가 포함되어 있다:
1. `PlayMontageAndWaitForEvent` — 기본 `AbilityTask`인 `PlayMontageAndWait`와 `WaitGameplayEvent`를 결합한 태스크다. 이를 통해 애니메이션 몽타주가 `AnimNotify`에서 해당 몽타주를 시작한 `GameplayAbility`로 게임플레이 이벤트를 역으로 전달할 수 있다. 애니메이션 몽타주의 특정 타이밍에 동작을 트리거할 때 활용한다.
2. `WaitReceiveDamage` — `OwnerActor`가 데미지를 받는 것을 감지하는 태스크다. 패시브 아머 스택 `GameplayAbility`에서 영웅이 데미지를 받을 때 아머 스택을 하나씩 제거하는 데 사용된다.

`AbilityTask`는 다음 요소들로 구성된다:
* `AbilityTask`의 새 인스턴스를 생성하는 정적(static) 함수
* 태스크가 목적을 완수했을 때 브로드캐스트되는 델리게이트
* 메인 작업을 시작하고 외부 델리게이트에 바인딩하는 `Activate()` 함수
* 외부 델리게이트 바인딩 해제를 포함한 정리 작업을 수행하는 `OnDestroy()` 함수
* 바인딩된 외부 델리게이트에 대한 콜백 함수
* 멤버 변수 및 내부 헬퍼 함수

> **참고**  
> `AbilityTask`는 출력 델리게이트를 한 가지 타입만 선언할 수 있다. 모든 출력 델리게이트는 파라미터 사용 여부와 관계없이 동일한 타입이어야 하며, 사용하지 않는 파라미터에는 기본값을 전달한다.

`AbilityTask`는 기본적으로 소유 `GameplayAbility`를 실행 중인 클라이언트 또는 서버에서만 동작한다. 단, `AbilityTask` 생성자에서 `bSimulatedTask = true`로 설정하고, `virtual void InitSimulatedTask(UGameplayTasksComponent& InGameplayTasksComponent)`를 오버라이드하며, 필요한 멤버 변수를 복제 설정하면 시뮬레이션 클라이언트에서도 실행할 수 있다. 이 방식은 모든 이동 변경 사항을 복제하는 대신 이동 `AbilityTask` 전체를 시뮬레이션하고 싶은 이동 관련 태스크 같은 드문 상황에서만 유용하다. 모든 `RootMotionSource` `AbilityTask`가 이 방식을 사용한다. 예시로 `AbilityTask_MoveToLocation.h/.cpp`를 참고하라.

`AbilityTask` 생성자에서 `bTickingTask = true`로 설정하고 `virtual void TickTask(float DeltaTime)`를 오버라이드하면 `AbilityTask`가 `Tick`을 수행할 수 있다. 프레임에 걸쳐 값을 부드럽게 보간(lerp)해야 할 때 유용하다. 예시로 `AbilityTask_MoveToLocation.h/.cpp`를 참고하라.

---

## 내 분석
