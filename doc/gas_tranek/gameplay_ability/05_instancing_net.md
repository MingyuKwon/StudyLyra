# Instancing & Net Execution Policy

> **GASDoc**: 4.6.7~8 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-instancing"></a>
#### GA의 세 가지 Instancing Policy(Non-Instanced / Per Actor / Per Execution)는 각각 어떤 상황에 적합한가?

GA가 활성화될 때 인스턴스를 생성하는지 여부와 방식을 결정한다.

| Instancing Policy | 설명 | 사용 시기 |
|---|---|---|
| Instanced Per Actor | 각 ASC는 GA 인스턴스를 하나만 가지며, 활성화 간에 재사용된다. | 가장 일반적. 어떤 어빌리티에도 사용 가능하며 활성화 간 상태를 유지한다. 활성화 간에 초기화가 필요한 변수는 직접 리셋해야 한다. |
| Instanced Per Execution | GA가 활성화될 때마다 새 인스턴스가 생성된다. | 변수가 매번 초기화된다는 장점이 있지만 성능이 가장 나쁘다. |
| Non-Instanced | GA가 CDO에서 직접 실행된다. 인스턴스가 생성되지 않는다. | 성능이 가장 좋지만 기능 제약이 가장 많다. 상태 저장 불가, 동적 변수 불가, AbilityTask 델리게이트 바인딩 불가. MOBA/RTS 미니언 기본 공격 같은 단순한 어빌리티에 적합. 샘플 프로젝트의 Jump GA가 Non-Instanced다. |

<a name="concepts-ga-net"></a>
#### GA의 Net Execution Policy 네 가지는 어떻게 다르며, 언제 각각을 사용해야 하는가?

GA를 어디서 실행하는지와 그 순서를 결정한다.

| Net Execution Policy | 설명 |
|---|---|
| `Local Only` | owning client에서만 실행된다. 로컬 코스메틱 변경만 이루어지는 어빌리티에 유용하다. 싱글플레이어 게임은 `Server Only`를 사용할 것. |
| `Local Predicted` | owning client에서 먼저 활성화된 후 서버에서 활성화된다. 서버는 클라이언트가 잘못 예측한 내용을 수정한다. |
| `Server Only` | 서버에서만 실행된다. 패시브 GA에 일반적으로 사용하며, 싱글플레이어 게임에도 권장한다. |
| `Server Initiated` | 서버에서 먼저 활성화된 후 owning client에서 활성화된다. |

---

### FGameplayAbilitySpec과 GA 인스턴스는 어떤 관계이며, Instancing Policy에 따라 어떻게 달라지는가?

`GiveAbility()` 시점에 ASC의 `ActivatableAbilities` 배열에 `FGameplayAbilitySpec`이 추가된다. 이것이 "이 ASC에 이 어빌리티가 부여돼 있다"는 슬롯 역할을 하며, GA 인스턴스와는 별개 개념이다.

Spec 안에는 GA 클래스, 고유 핸들(`FGameplayAbilitySpecHandle`), 레벨, InputID, 그리고 실제 GA 인스턴스 또는 CDO를 가리키는 `UGameplayAbility* Ability`가 포함된다.

Activate 시점에 InstancingPolicy에 따라 이 포인터가 달라진다:

| Policy | GA 인스턴스 생성 | `Spec.Ability` 가리키는 곳 |
|---|---|---|
| Non-Instanced | 없음 | CDO |
| Instanced Per Actor | 최초 Activate 1회 생성, 이후 재사용 | 그 인스턴스 |
| Instanced Per Execution | Activate마다 새로 생성 | `Spec.NonReplicatedInstances` 배열 |

---

### GE는 왜 GA와 달리 인스턴스가 생성되지 않으며, 적용 시 어떤 구조체가 생성되는가?

GE는 데이터 에셋(CDO)으로만 존재하고 `new`/`Spawn`되지 않는다. 적용 시 구조체가 만들어진다.

```
ApplyGameplayEffect() 호출
  → FGameplayEffectSpec (구조체) 생성 — GE 클래스 + 레벨 + 컨텍스트
  → 지속 효과라면 FActiveGameplayEffect (구조체) 로 ActiveGameplayEffects에 추가
```

GA는 Policy에 따라 인스턴스가 생기기도 안 생기기도 하지만, GE는 어떤 경우에도 인스턴스가 만들어지지 않는다.
