# Meta Attribute

> **GASDoc**: 4.3.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-meta"></a>
#### 4.3.3 Meta Attribute

일부 Attribute는 다른 Attribute와 상호작용하기 위한 임시 값의 플레이스홀더로 취급된다. 이를 `Meta Attribute`라고 한다. 예를 들어 우리는 흔히 데미지를 Meta Attribute로 정의한다. GameplayEffect가 체력 Attribute를 직접 변경하는 대신, `Damage`라는 Meta Attribute를 플레이스홀더로 사용한다. 이렇게 하면 데미지 값을 `GameplayEffectExecutionCalculation`에서 버프와 디버프로 조정할 수 있고, 최종적으로 체력 Attribute에서 나머지를 차감하기 전에 현재 방어막 Attribute에서 데미지를 먼저 차감하는 등 AttributeSet에서 추가 조작이 가능하다. `Damage` Meta Attribute는 GameplayEffect 사이에서 값이 유지되지 않으며, 매번 덮어써진다. Meta Attribute는 일반적으로 복제되지 않는다.

Meta Attribute는 데미지나 힐링과 같은 것들에 대해 "얼마나 피해를 줬는가?"와 "이 피해를 어떻게 처리할 것인가?" 사이의 논리적 분리를 제공한다. 이 논리적 분리 덕분에 Gameplay Effect와 Execution Calculation은 Target이 데미지를 어떻게 처리하는지 알 필요가 없다. 데미지 예시를 이어가면, Gameplay Effect가 데미지의 양을 결정하고, AttributeSet이 그 데미지를 어떻게 처리할지 결정한다. 모든 캐릭터가 같은 Attribute를 갖지 않을 수 있는데, 특히 서브클래싱된 AttributeSet을 사용하는 경우 그렇다. 기본 AttributeSet 클래스는 체력 Attribute만 가질 수 있지만, 서브클래싱된 AttributeSet은 방어막 Attribute를 추가할 수 있다. 방어막 Attribute를 가진 서브클래싱 AttributeSet은 기본 AttributeSet 클래스와 다른 방식으로 받은 데미지를 분배할 것이다.

Meta Attribute는 좋은 설계 패턴이지만 필수는 아니다. 모든 데미지 인스턴스에 Execution Calculation 하나만 사용하고 모든 캐릭터가 하나의 AttributeSet 클래스를 공유한다면, Execution Calculation 내부에서 체력, 방어막 등에 데미지를 분배하고 해당 Attribute를 직접 수정해도 무방하다. 유연성을 희생하는 것이지만, 그것으로 충분할 수도 있다.

---

### "GE 사이에서 값이 유지되지 않으며 매번 덮어써진다"

`Damage`는 `FGameplayAttributeData`로 선언된 Attribute지만, 실제로는 임시 수신함처럼 쓰인다.

```
GE A 적용 → Damage = 50 → PostGameplayEffectExecute() 실행 → 처리 완료
GE B 적용 → Damage = 30 → PostGameplayEffectExecute() 실행 → 처리 완료
```

GE A가 끝난 뒤 Damage = 50이 남아있지 않다. GE B가 오면 30으로 덮어쓴다.
이 값을 "누적"하거나 "기억"하는 용도로 쓰면 안 된다.

### "AttributeSet에서 추가 조작이 가능하다"

`PostGameplayEffectExecute()`가 그 조작 지점이다.

```cpp
void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        float DamageValue = GetDamage();

        // 방어막이 있으면 먼저 차감
        float Shield = GetShield();
        float Remainder = FMath::Max(0.f, DamageValue - Shield);
        SetShield(FMath::Max(0.f, Shield - DamageValue));

        // 나머지를 체력에서 차감
        SetHealth(FMath::Max(0.f, GetHealth() - Remainder));

        SetDamage(0.f);  // Meta Attribute 초기화
    }
}
```

GE는 "데미지가 30이다"만 결정하고, "방어막에서 먼저 까고 체력에서 빼라"는 로직은 AttributeSet이 담당한다.
GE가 캐릭터 내부 구조(방어막 유무 등)를 알 필요가 없다.

### "Meta Attribute는 일반적으로 복제되지 않는다"

값의 수명이 너무 짧기 때문이다.
`PostGameplayEffectExecute()` 안에서 읽고 처리한 뒤 바로 0으로 리셋된다.
클라이언트에 복제될 시간도, 복제할 의미도 없다.

Health 같은 일반 Attribute는 클라이언트 UI가 읽어야 하므로 복제한다.
Damage는 서버에서 계산하고 처리까지 끝나면 버리는 값이라 복제가 필요 없다.
