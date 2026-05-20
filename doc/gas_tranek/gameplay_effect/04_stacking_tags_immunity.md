# 스태킹 / 태그 / 면역

> **GASDoc**: 4.5.5 / 4.5.7~8 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ge-stacking"></a>
#### GE Stacking이란 무엇이며, AggregateBySource와 AggregateByTarget은 어떻게 다른가?

Stacking을 설정하면 GE가 적용될 때 새 인스턴스가 추가되는 대신, 기존 인스턴스의 스택 카운트가 증가한다. `Duration`과 `Infinite` GE에서만 동작한다.

| Stacking 타입 | 설명 |
| --- | ---- |
| `Aggregate by Source` | Source ASC별로 독립적인 스택 인스턴스를 가진다. 각 Source가 최대 X개까지 스택 적용 가능 |
| `Aggregate by Target` | Source와 무관하게 Target에 인스턴스가 하나만 존재한다. 각 Source는 공유 스택 한도까지 기여 가능 |

<a name="concepts-ge-ga"></a>
#### GE로 GA를 부여하는 방법과 GE가 제거될 때 부여된 GA를 어떻게 처리할 것인지 결정하는 방법은?

`Duration`과 `Infinite` GE만 GA를 부여할 수 있다. 일반적인 사용 사례는 다른 플레이어에게 넉백이나 끌어당기기처럼 특정 행동을 강제로 취하게 하고 싶을 때다.

| 제거 정책 | 설명 |
| --- | ---- |
| `Cancel Ability Immediately` | GE가 제거될 때 부여된 어빌리티가 즉시 취소되고 제거된다 |
| `Remove Ability on End` | 부여된 어빌리티가 완료될 때까지 허용된 후 제거된다 |
| `Do Nothing` | GE가 제거되어도 어빌리티는 영향을 받지 않는다. 수동으로 제거하기 전까지 영구 보유 |

<a name="concepts-ge-tags"></a>
#### GE의 다양한 태그 카테고리(GrantedTags, OngoingRequirements, ApplicationRequirements 등)는 각각 어떤 역할을 하는가?

| 카테고리 | 설명 |
| --- | ---- |
| `Gameplay Effect Asset Tags` | GE 자체가 보유하는 태그. 기능 없음 — 설명 용도로만 사용 |
| `Granted Tags` | GE가 적용된 ASC에도 부여된다. GE가 제거되면 ASC에서도 함께 제거. `Duration`과 `Infinite` GE에서만 동작 |
| `Ongoing Tag Requirements` | 적용 이후 GE의 활성/비활성 여부를 결정한다. 조건 불충족 시 꺼졌다가 충족되면 다시 켜진다. `Duration`과 `Infinite` GE에서만 동작 |
| `Application Tag Requirements` | GE 적용 가능 여부를 결정한다. 조건 미충족 시 적용되지 않는다 |
| `Remove Gameplay Effects with Tags` | GE가 성공적으로 적용될 때, 지정된 태그를 가진 기존 GE를 모두 제거한다 |

<a name="concepts-ge-immunity"></a>
#### GE의 Immunity(면역)는 Application Tag Requirements와 어떻게 다르며, 언제 사용해야 하는가?

두 방법 모두 GE 적용을 차단할 수 있다. Immunity 시스템을 사용하면 면역으로 GE가 차단될 때를 감지할 수 있는 델리게이트 `UAbilitySystemComponent::OnImmunityBlockGameplayEffectDelegate`를 제공한다는 차이가 있다.

- `GrantedApplicationImmunityTags`: Source ASC가 지정된 태그 중 하나라도 보유하면 해당 Source의 모든 GE를 차단한다
- `Granted Application Immunity Query`: `FGameplayEffectQuery`로 더 세밀한 조건을 표현하여 차단 여부를 결정한다

---

### AggregateBySource와 AggregateByTarget은 내부적으로 어떤 기준으로 인스턴스를 분리하는가?

> 소스: `GameplayEffect.cpp:3614`

차이는 `FindStackableActiveGameplayEffect` 함수의 조건 하나다.

```cpp
// GameplayEffect.cpp:3629
if (ActiveEffect.Spec.Def == Spec.Def &&
    ((StackingType == EGameplayEffectStackingType::AggregateByTarget) ||
     (SourceASC && SourceASC == ActiveEffect.Spec.GetContext().GetInstigatorAbilitySystemComponent())))
```

- **AggregateByTarget**: GE 클래스가 같으면 찾음 (Source 무관) → 인스턴스 하나 공유
- **AggregateBySource**: GE 클래스가 같고 Source ASC도 같아야 찾음 → Source별 독립 인스턴스

| 타입 | 인스턴스 수 | 대표 용도 |
|---|---|---|
| AggregateByTarget | 하나 | "이 디버프는 Target에 최대 N중첩" — 누가 걸든 공유 카운터 |
| AggregateBySource | Source당 하나 | "각 플레이어가 독립적으로 최대 N중첩 적용 가능" — Source별 독립 카운터 |

---

### UE 5.3에서 UGameplayEffect가 GEComponent 방식으로 리팩터링된 이유와 기존 필드와의 대응 관계는?

> 소스: `GameplayEffect.h:41`, `GameplayEffectComponents/` 폴더 전체

UE 5.3부터 `UGameplayEffect` 클래스의 태그 요건, 면역, 어빌리티 부여 등의 설정이 `UGameplayEffectComponent` 서브클래스들로 분리됐다. 기존 필드들은 `UE_DEPRECATED(5.3, ...)`로 전환되고, 저장 시 자동 fix-up 과정을 통해 GEComponent로 마이그레이션된다.

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

**UTargetTagRequirementsGameplayEffectComponent**: 기존에 없던 `RemovalTagRequirements`가 추가됐다. 조건 충족 시 GE를 영구 제거한다(기존 `OngoingTagRequirements`는 일시 억제였다).

**UImmunityGameplayEffectComponent**: 기존 태그 기반 면역과 쿼리 기반 면역을 `FGameplayEffectQuery` 배열 하나로 통합했다.

**URemoveOtherGameplayEffectComponent**: 기존 태그 목록 방식에서 `FGameplayEffectQuery` 배열로 바뀌어 더 복잡한 조건(클래스, 레벨, 태그 조합 등)으로 제거 대상을 지정할 수 있다.
