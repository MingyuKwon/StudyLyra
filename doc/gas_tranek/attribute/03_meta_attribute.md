# Meta Attribute

> **GASDoc**: 4.3.3 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-meta"></a>
#### Meta Attribute란 무엇이며, 왜 Damage를 직접 Health에 적용하지 않는가?

다른 Attribute와 상호작용하기 위한 임시 플레이스홀더 Attribute다. GE가 Health를 직접 깎는 대신 `Damage` Meta Attribute에 값을 넣고, AttributeSet의 `PostGameplayEffectExecute()`에서 방어막 차감 등 추가 처리 후 최종적으로 Health에 반영한다.

이 구조는 "데미지 양 결정(GE)"과 "데미지 처리 방식(AttributeSet)" 사이의 책임을 분리한다. GE는 캐릭터에 방어막이 있는지 없는지 알 필요가 없다.

Meta Attribute는 GE 사이에서 값이 유지되지 않으며, 복제되지 않는다.

---

### Meta Attribute 값이 GE 사이에서 유지되지 않는 이유는 무엇인가?

`PostGameplayEffectExecute()` 안에서 읽고 처리한 뒤 즉시 0으로 리셋되기 때문이다. 각 GE 적용마다 덮어쓰이는 일회성 수신함으로 설계되어 있다.

```
GE A 적용 → Damage = 50 → PostGameplayEffectExecute() 처리 → Damage = 0 리셋
GE B 적용 → Damage = 30 → PostGameplayEffectExecute() 처리 → Damage = 0 리셋
```

누적이나 기억 용도로 쓰면 안 된다.

### Meta Attribute를 통해 AttributeSet에서 추가 조작을 하는 이유는?

`PostGameplayEffectExecute()`가 처리 지점이다. GE는 데미지 수치만 결정하고, 방어막 차감 순서 같은 캐릭터 내부 로직은 AttributeSet이 담당한다.

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

### Meta Attribute를 복제하지 않는 이유는?

`PostGameplayEffectExecute()` 안에서 읽고 처리한 직후 0으로 리셋되므로 클라이언트에 복제될 시간도, 필요도 없다. Health처럼 UI가 읽어야 하는 값이 아니라 서버에서 계산하고 즉시 버리는 중간 계산값이다.
