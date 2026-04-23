# GA Spec & 데이터 전달

> **GASDoc**: 4.6.10~11 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-spec"></a>
#### 4.6.10 Gameplay Ability Spec

`GameplayAbility`가 부여된 이후에는 ASC 위에 `GameplayAbilitySpec`이 존재하게 된다. `GameplayAbilitySpec`은 활성화 가능한 `GameplayAbility`를 정의하며, GameplayAbility 클래스, 레벨, 입력 바인딩, 그리고 GameplayAbility 클래스와 분리하여 유지해야 하는 런타임 상태 정보를 담고 있다.

서버에서 `GameplayAbility`가 부여되면, 서버는 `GameplayAbilitySpec`을 owning client에 복제하여 해당 클라이언트가 능력을 활성화할 수 있도록 한다.

`GameplayAbilitySpec`을 활성화하면 그 `Instancing Policy`에 따라 `GameplayAbility`의 인스턴스가 생성된다 (`Non-Instanced` GameplayAbility의 경우에는 인스턴스가 생성되지 않는다).

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-data"></a>
#### 4.6.11 Abilities에 데이터 전달하기

`GameplayAbility`의 일반적인 패러다임은 `Activate → Generate Data → Apply → End`다. 때로는 기존 데이터를 기반으로 동작해야 하는 경우도 있다. GAS는 외부 데이터를 `GameplayAbility`로 전달하기 위한 몇 가지 방법을 제공한다.

| 방법                                            | 설명                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 이벤트로 `GameplayAbility` 활성화               | 데이터 페이로드를 포함한 이벤트로 `GameplayAbility`를 활성화한다. 로컬 예측 `GameplayAbility`의 경우, 이벤트 페이로드는 클라이언트에서 서버로 복제된다. 기존 변수에 맞지 않는 임의의 데이터를 전달할 때는 두 개의 `Optional Object` 변수 또는 [`TargetData`](#concepts-targeting-data) 변수를 사용한다. 단, 이 방법을 사용하면 입력 바인딩으로는 어빌리티를 활성화할 수 없다는 단점이 있다. 이벤트로 `GameplayAbility`를 활성화하려면, `GameplayAbility`에서 `Triggers`를 설정하고 `GameplayTag`를 할당한 후 `GameplayEvent` 옵션을 선택해야 한다. 이벤트를 전송할 때는 `UAbilitySystemBlueprintLibrary::SendGameplayEventToActor(AActor* Actor, FGameplayTag EventTag, FGameplayEventData Payload)` 함수를 사용한다. |
| `WaitGameplayEvent` AbilityTask 사용            | `WaitGameplayEvent` AbilityTask를 사용하여, `GameplayAbility`가 활성화된 이후 페이로드 데이터를 포함한 이벤트를 수신 대기하도록 설정한다. 이벤트 페이로드와 전송 방법은 이벤트로 GameplayAbility를 활성화하는 것과 동일하다. 단, AbilityTask가 이벤트를 복제하지 않으므로 `Local Only` 및 `Server Only` GameplayAbility에서만 사용해야 한다는 단점이 있다. 이벤트 페이로드를 복제하는 커스텀 AbilityTask를 직접 작성하는 것도 가능하다.                                                                                                                                                                                                                                                                                       |
| `TargetData` 사용                               | 커스텀 `TargetData` 구조체는 클라이언트와 서버 사이에서 임의의 데이터를 전달하는 좋은 방법이다.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `OwnerActor` 또는 `AvatarActor`에 데이터 저장  | `OwnerActor`, `AvatarActor`, 또는 참조를 얻을 수 있는 다른 오브젝트에 복제 변수를 저장하여 사용한다. 이 방법은 가장 유연하며 입력 바인딩으로 활성화되는 `GameplayAbility`와도 함께 사용할 수 있다. 단, 사용 시점에 복제로 인한 데이터 동기화가 보장되지 않는다. 즉, 복제 변수를 설정하고 즉시 `GameplayAbility`를 활성화하면, 패킷 손실 등의 이유로 수신 측에서 처리 순서가 보장되지 않을 수 있다.                                                                                                                                                                                                                                                                                                                                     |

**[⬆ Back to Top](#table-of-contents)**
---

## 내 분석
