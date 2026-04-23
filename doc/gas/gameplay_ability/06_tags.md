# Ability Tags

> **GASDoc**: 4.6.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-tags"></a>
#### 4.6.9 Ability Tags

`GameplayAbility`에는 내장 로직을 가진 `GameplayTagContainer`가 여러 개 포함되어 있다. 이 `GameplayTag`들은 복제되지 않는다.

| `GameplayTag Container`     | 설명                                                                                                                                                                                                                              |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Ability Tags`              | `GameplayAbility`가 소유하는 `GameplayTag`. 해당 GameplayAbility를 설명하는 용도의 태그다.                                                                                                                                        |
| `Cancel Abilities with Tag` | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화될 때 취소된다.                                                                                                                              |
| `Block Abilities with Tag`  | `Ability Tags`에 이 태그를 가진 다른 `GameplayAbility`는, 이 GameplayAbility가 활성화 중인 동안 활성화가 차단된다.                                                                                                                |
| `Activation Owned Tags`     | 이 `GameplayAbility`가 활성화 중인 동안, 해당 GameplayAbility의 Owner에게 부여되는 `GameplayTag`. 이 태그들은 복제되지 않는다는 점에 유의할 것.                                                                                    |
| `Activation Required Tags`  | Owner가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다.                                                                                                                                             |
| `Activation Blocked Tags`   | Owner가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다.                                                                                                                                           |
| `Source Required Tags`      | `Source`가 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Source Blocked Tags`       | `Source`가 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Source` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |
| `Target Required Tags`      | `Target`이 이 태그를 **모두** 보유하고 있을 때만 이 `GameplayAbility`를 활성화할 수 있다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                             |
| `Target Blocked Tags`       | `Target`이 이 태그 중 **하나라도** 보유하고 있으면 이 `GameplayAbility`를 활성화할 수 없다. `Target` GameplayTag는 GameplayAbility가 이벤트로 트리거된 경우에만 설정된다.                                                          |

---

## 내 분석
