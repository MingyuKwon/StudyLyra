# AbilityTask 정의

> **GASDoc**: 4.7.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-at-definition"></a>
### 4.7.1 AbilityTask 정의

`GameplayAbility`는 단일 프레임에서만 실행된다. 이것만으로는 유연성이 크게 부족하다. 시간에 걸쳐 진행되는 동작이나, 나중에 발생하는 델리게이트에 응답해야 하는 동작을 처리하려면 **잠재적(latent) 액션**인 `AbilityTask`를 사용한다.

GAS는 다음과 같은 `AbilityTask`를 기본으로 제공한다:
* `RootMotionSource`를 이용해 캐릭터를 이동시키는 태스크
* 애니메이션 몽타주를 재생하는 태스크
* `Attribute` 변경에 응답하는 태스크
* `GameplayEffect` 변경에 응답하는 태스크
* 플레이어 입력에 응답하는 태스크
* 그 외 다수

`UAbilityTask` 생성자는 게임 전체에서 동시에 실행되는 `AbilityTask` 수를 **최대 1000개**로 하드코딩하여 제한한다. RTS 게임처럼 수백 명의 캐릭터가 월드에 동시에 존재할 수 있는 게임의 `GameplayAbility`를 설계할 때 반드시 이 점을 고려해야 한다.

---

## 내 분석

### AbilityTask = GameplayTask + GAS

`UAbilityTask`는 범용 비동기 태스크 시스템인 `UGameplayTask`를 GAS에 통합한 클래스다.
`UGameplayTask` 자체의 구조와 복제 메커니즘은 → [00 GameplayTask](gameplay_task/README.md) 참조.

`UAbilityTask`가 `UGameplayTask` 위에 추가하는 것은 세 가지다.

**① GA 수명 연동**
`UGameplayTask`는 독립적인 수명을 갖는다.
`UAbilityTask`는 자신을 만든 GA와 수명이 묶여 있어, GA가 `EndAbility()`로 종료되면 해당 GA의 모든 AbilityTask가 자동으로 파괴된다.

**② GAS 컨텍스트 접근**
`UGameplayTask`는 ASC, AvatarActor, AbilityActorInfo를 모른다.
`UAbilityTask`는 자신을 만든 `UGameplayAbility` 포인터를 보유하므로, 태스크 내부에서 GAS 전체 컨텍스트에 바로 접근할 수 있다.

```cpp
Ability->GetAbilitySystemComponent()    // ASC
Ability->GetAvatarActorFromActorInfo()  // AvatarActor
Ability->GetActorInfo()                 // FGameplayAbilityActorInfo 전체
```

**③ GAS 예측 시스템 연동**
`UAbilityTask`는 GAS의 `PredictionKey` 시스템에 참여할 수 있다.
`UGameplayTask`에는 예측 개념 자체가 없다.
