# 스태킹 / 태그 / 면역

> **GASDoc**: 4.5.5 / 4.5.7~8 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-stacking"></a>
#### GE Stacking이란 무엇이며, AggregateBySource와 AggregateByTarget은 어떻게 다른가?

`GameplayEffect`는 기본적으로 적용될 때마다 이전에 존재하던 `GameplayEffectSpec` 인스턴스를 알지 못하거나 신경 쓰지 않는 새로운 인스턴스를 추가한다. Stacking을 설정하면 새 인스턴스가 추가되는 대신, 현재 존재하는 `GameplayEffectSpec`의 스택 카운트가 변경된다. Stacking은 `Duration`과 `Infinite` `GameplayEffect`에서만 동작한다.

Stacking 타입에는 두 가지가 있다: Aggregate by Source와 Aggregate by Target.

| Stacking 타입       | 설명 |
| ------------------- | ---- |
| Aggregate by Source | Target에서 Source ASC별로 독립적인 스택 인스턴스를 가진다. 각 Source가 최대 X개까지 스택을 적용할 수 있다 |
| Aggregate by Target | Target에 Source와 무관하게 스택 인스턴스가 하나만 존재한다. 각 Source는 공유 스택 한도까지 스택을 기여할 수 있다 |

스택에는 만료(expiration), 지속 시간 갱신(duration refresh), 주기 리셋(period reset)에 대한 정책이 있으며, GameplayEffect Blueprint에서 유용한 툴팁으로 확인할 수 있다.

샘플 프로젝트에는 `GameplayEffect` 스택 변경을 감지하는 커스텀 Blueprint 노드가 포함되어 있다. HUD UMG 위젯이 이를 사용하여 플레이어의 패시브 방어구 스택 수를 업데이트한다. 이 `AsyncTask`는 `EndTask()`가 수동으로 호출되기 전까지 계속 살아있으므로, UMG 위젯의 `Destruct` 이벤트에서 해제해야 한다. `AsyncTaskEffectStackChanged.h/cpp`를 참조하라.

<a name="concepts-ge-ga"></a>
#### GE로 GA를 부여하는 방법과 GE가 제거될 때 부여된 GA를 어떻게 처리할 것인지 결정하는 방법은?

`GameplayEffect`는 ASC에 새로운 GameplayAbility를 부여할 수 있다. `Duration`과 `Infinite` `GameplayEffect`만 어빌리티를 부여할 수 있다.

일반적인 사용 사례는 다른 플레이어에게 넉백이나 끌어당기기처럼 특정 행동을 강제로 취하게 하고 싶을 때다. 해당 대상에게 GE를 적용하여 자동으로 활성화되는 어빌리티(Passive Abilities 참조)를 부여하고, 이 어빌리티가 원하는 동작을 수행하게 한다.

디자이너는 GE가 부여하는 어빌리티, 부여 레벨, 바인딩할 입력, 그리고 부여된 어빌리티에 대한 제거 정책을 설정할 수 있다.

| 제거 정책                  | 설명 |
| -------------------------- | ---- |
| Cancel Ability Immediately | GE가 Target에서 제거될 때, 부여된 어빌리티가 즉시 취소되고 제거된다 |
| Remove Ability on End      | 부여된 어빌리티가 완료될 때까지 허용된 후 Target에서 제거된다 |
| Do Nothing                 | GE가 Target에서 제거되어도 부여된 어빌리티는 영향을 받지 않는다. Target은 이후 수동으로 제거하기 전까지 해당 어빌리티를 영구적으로 보유한다 |

<a name="concepts-ge-tags"></a>
#### GE의 다양한 태그 카테고리(GrantedTags, OngoingRequirements, ApplicationRequirements 등)는 각각 어떤 역할을 하는가?

`GameplayEffect`는 여러 `GameplayTagContainer`를 보유한다. 디자이너는 각 카테고리에 대해 `Added`와 `Removed` `GameplayTagContainer`를 편집하며, 컴파일 시 결과가 `Combined` `GameplayTagContainer`에 반영된다. `Added` 태그는 이 `GameplayEffect`가 부모 클래스에 없던 새 태그를 추가하는 것이며, `Removed` 태그는 부모 클래스에는 있지만 이 자식 클래스에는 없는 태그를 제거하는 것이다.

| 카테고리                          | 설명 |
| --------------------------------- | ---- |
| Gameplay Effect Asset Tags        | `GameplayEffect`가 보유하는 태그. 이 태그들은 그 자체로 아무 기능도 수행하지 않으며, `GameplayEffect`를 설명하는 용도로만 사용된다 |
| Granted Tags                      | `GameplayEffect`에 존재하는 태그이면서, `GameplayEffect`가 적용된 ASC에도 부여된다. `GameplayEffect`가 제거되면 ASC에서도 함께 제거된다. `Duration`과 `Infinite` `GameplayEffect`에서만 동작한다 |
| Ongoing Tag Requirements          | 적용된 이후, 이 태그들이 `GameplayEffect`의 활성/비활성 여부를 결정한다. `GameplayEffect`는 비활성 상태이면서도 여전히 적용 중일 수 있다. Ongoing Tag Requirements를 충족하지 못해 꺼진 `GameplayEffect`가 이후 조건을 충족하게 되면 다시 켜지고 Modifier가 재적용된다. `Duration`과 `Infinite` `GameplayEffect`에서만 동작한다 |
| Application Tag Requirements      | Target이 보유한 태그 중 `GameplayEffect`를 적용할 수 있는지 결정하는 태그. 이 조건을 충족하지 못하면 `GameplayEffect`가 적용되지 않는다 |
| Remove Gameplay Effects with Tags | 이 `GameplayEffect`가 성공적으로 적용될 때, Target에서 `Asset Tags` 또는 `Granted Tags`에 지정된 태그 중 하나라도 가진 `GameplayEffect`가 모두 제거된다 |

<a name="concepts-ge-immunity"></a>
#### GE의 Immunity(면역)는 Application Tag Requirements와 어떻게 다르며, 언제 사용해야 하는가?

`GameplayEffect`는 GameplayTag를 기반으로 다른 `GameplayEffect`의 적용을 효과적으로 차단하는 면역(Immunity)을 부여할 수 있다. `Application Tag Requirements`를 통해서도 유사한 효과를 낼 수 있지만, Immunity 시스템을 사용하면 면역으로 인해 `GameplayEffect`가 차단될 때를 감지할 수 있는 델리게이트 `UAbilitySystemComponent::OnImmunityBlockGameplayEffectDelegate`를 제공한다.

`GrantedApplicationImmunityTags`는 Source ASC(관련 Source 어빌리티의 `AbilityTags` 포함)가 지정된 태그 중 하나라도 보유하고 있는지 확인한다. 이는 특정 캐릭터 또는 소스의 태그를 기반으로 해당 소스로부터의 모든 `GameplayEffect`에 대해 면역을 제공하는 방법이다.

`Granted Application Immunity Query`는 수신되는 `GameplayEffectSpec`이 쿼리와 매칭되는지 검사하여 적용을 차단하거나 허용한다.

이 쿼리들은 `GameplayEffect` Blueprint에서 유용한 툴팁으로 확인할 수 있다.

---

### AggregateBySource와 AggregateByTarget은 내부적으로 어떤 기준으로 인스턴스를 분리하는가?

> 소스: `GameplayEffect.cpp:3614`

두 타입의 차이는 `FindStackableActiveGameplayEffect` 함수의 조건 하나다.

```cpp
// GameplayEffect.cpp:3629
if (ActiveEffect.Spec.Def == Spec.Def &&
    ((StackingType == EGameplayEffectStackingType::AggregateByTarget) ||
     (SourceASC && SourceASC == ActiveEffect.Spec.GetContext().GetInstigatorAbilitySystemComponent())))
```

이 함수가 "기존에 쌓인 같은 GE 인스턴스가 있는지" 찾는다.
- 찾으면 → 기존 인스턴스의 StackCount를 올림
- 못 찾으면 → 새 `FActiveGameplayEffect` 인스턴스 생성

**AggregateByTarget**: GE 클래스가 같으면 찾음 (Source 무관)

```
PlayerA 3번, PlayerB 2번 독 공격 → Target에 인스턴스 하나
  [PoisonGE] StackCount = 5   ← PlayerA 3 + PlayerB 2 합산
```

**AggregateBySource**: GE 클래스가 같고 Source ASC도 같아야 찾음

```
PlayerA 3번, PlayerB 2번 독 공격 → Target에 인스턴스 둘
  [PoisonGE] InstigatorASC = PlayerA, StackCount = 3
  [PoisonGE] InstigatorASC = PlayerB, StackCount = 2
```

PlayerB가 Apply할 때 PlayerA 인스턴스를 못 찾아서 자기 인스턴스를 별도로 생성한다.

**용도 비교**:

| 타입 | 인스턴스 수 | 대표 용도 |
|---|---|---|
| AggregateByTarget | 하나 | "이 디버프는 Target에 최대 N중첩" — 누가 걸든 공유 카운터 |
| AggregateBySource | Source당 하나 | "각 플레이어가 독립적으로 최대 N중첩 적용 가능" — Source별 독립 카운터 |

---

### UE 5.3에서 UGameplayEffect가 GEComponent 방식으로 리팩터링된 이유와 기존 필드와의 대응 관계는?

> 소스: `GameplayEffect.h:41`, `GameplayEffectComponents/` 폴더 전체

UE 5.3 이전에는 `UGameplayEffect` 클래스 하나에 태그 요건, 면역, 어빌리티 부여 등 모든 설정이 직접 UPROPERTY로 들어있었다. 5.3부터 이 필드들이 전부 `UE_DEPRECATED(5.3, ...)` + `DeprecatedProperty`로 전환되고, `UGameplayEffectComponent` 서브클래스들로 분리됐다.

```
// GameplayEffect.h:41
Since Unreal 5.3, we have deprecated the Monolithic UGameplayEffect
and instead rely on UGameplayEffectComponents.
```

기존 필드들은 에디터에서 읽기 전용으로 남아있고, 저장 시 자동 fix-up 과정을 통해 GEComponent로 마이그레이션된다.

#### 기존 필드 → 컴포넌트 대응표

| 기존 UGameplayEffect 필드 (5.3 Deprecated) | 대체 컴포넌트 |
|---|---|
| `InheritableOwnedTagsContainer` (GrantedTags) | `UTargetTagsGameplayEffectComponent` |
| `OngoingTagRequirements` | `UTargetTagRequirementsGameplayEffectComponent` |
| `ApplicationTagRequirements` | `UTargetTagRequirementsGameplayEffectComponent` |
| `RemoveGameplayEffectsWithTags` | `URemoveOtherGameplayEffectComponent` |
| `GrantedApplicationImmunityTags` | `UImmunityGameplayEffectComponent` |
| `GrantedApplicationImmunityQuery` | `UImmunityGameplayEffectComponent` |
| Granted Abilities | `UAbilitiesGameplayEffectComponent` |
| Asset Tags | `UAssetTagsGameplayEffectComponent` |

Stacking, Modifiers, Executions, GameplayCues, Duration/Period는 변경 없이 `UGameplayEffect`에 잔류한다.

#### GEComponent로 전환하면서 각 컴포넌트에 어떤 변경이 생겼는가?

**UTargetTagRequirementsGameplayEffectComponent**

기존에 없던 `RemovalTagRequirements`가 추가됐다. 기존 `OngoingTagRequirements`는 조건 불충족 시 GE를 일시 억제(bIsInhibited)했지만, Removal은 조건 충족 시 GE를 영구 제거한다.

```cpp
// TargetTagRequirementsGameplayEffectComponent.h
FGameplayTagRequirements ApplicationTagRequirements; // 적용 시 pass/fail (기존과 동일)
FGameplayTagRequirements OngoingTagRequirements;     // 적용 후 켜짐/꺼짐 (기존과 동일)
FGameplayTagRequirements RemovalTagRequirements;     // 충족 시 영구 제거 (신규)
```

**UImmunityGameplayEffectComponent**

기존 태그 기반 면역(`GrantedApplicationImmunityTags`)과 쿼리 기반 면역(`GrantedApplicationImmunityQuery`)을 `FGameplayEffectQuery` 배열 하나로 통합했다. 쿼리가 태그보다 더 세밀한 조건을 표현할 수 있다.

```cpp
// ImmunityGameplayEffectComponent.h
TArray<FGameplayEffectQuery> ImmunityQueries; // 태그 기반 + 쿼리 기반 통합
```

**URemoveOtherGameplayEffectComponent**

기존 `RemoveGameplayEffectsWithTags`는 태그 목록으로 대상을 지정했다. 컴포넌트로 오면서 `FGameplayEffectQuery` 배열로 바뀌어 더 복잡한 조건(클래스, 레벨, 태그 조합 등)으로 제거 대상을 지정할 수 있다.

```cpp
// RemoveOtherGameplayEffectComponent.h
TArray<FGameplayEffectQuery> RemoveGameplayEffectQueries;
```
