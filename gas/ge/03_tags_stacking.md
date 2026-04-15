# GE 태그 & 스택

> 참고: [GAS Doc 캐시](../gas_doc_cache.md)

---

## 7가지 GE 태그

| 태그 유형 | 동작 |
|---|---|
| `Asset Tags` | GE 자체를 설명하는 식별 태그. 쿼리 등에 사용 |
| `Granted Tags` | GE 활성화 중 대상 ASC에 자동 부여. GE 제거 시 자동 제거 |
| `Ongoing Required Tags` | 이 태그가 없으면 GE 일시 Inhibit (비활성화) |
| `Ongoing Ignored Tags` | 이 태그가 있으면 GE 일시 Inhibit |
| `Application Required Tags` | 이 태그가 없으면 GE 적용 자체 불가 |
| `Application Ignored Tags` | 이 태그가 있으면 GE 적용 자체 불가 |
| `Remove GEs with Tags` | 이 GE 적용 시 해당 Asset Tag 가진 기존 GE 제거 |

### Application vs Ongoing 차이

```
Application Required/Ignored Tags:
    → GE를 처음 적용할 때만 체크
    → 조건 불충족 → GE 자체가 추가되지 않음

Ongoing Required/Ignored Tags:
    → GE가 이미 활성화된 상태에서 매 틱 체크
    → 조건 불충족 → GE Inhibit (일시 중지, 제거는 아님)
    → 조건 복귀 → GE 다시 활성화
```

---

## Granted Tags 활용 패턴

### 상태 표시

```
스턴 GE:
    Duration: 3초
    Granted Tags: Status.Debuff.Stun

다른 GA들:
    ActivationBlockedTags: Status.Debuff.Stun
→ 스턴 중에는 모든 능력 차단
```

### 쿨다운 구현

```
Cooldown GE:
    Duration: 5초 (SetByCaller로 런타임 설정 가능)
    Granted Tags: Cooldown.Ability.MyAbility

해당 GA:
    ActivationBlockedTags: Cooldown.Ability.MyAbility
→ 쿨다운 중에는 활성화 불가
```

### 무적 GE

```
InvincibilityGE:
    Duration: 2초
    Application Ignored Tags: (없음)
    
모든 데미지 GE:
    Application Required Tags: (없음)
    Ongoing Ignored Tags: Status.Effect.Invincible
→ 무적 중에는 데미지 GE Inhibit
```

---

## Stacking

같은 GE가 여러 번 적용될 때 어떻게 처리할지 결정한다.

| Stacking 옵션 | 설명 |
|---|---|
| `Aggregate by Source` | 소스(GA/캐릭터)별로 독립 스택 |
| `Aggregate by Target` | 타겟 기준으로 단일 스택 |

### 스택 관련 설정

```
Stack Limit Count: 최대 스택 수
Stack Duration Refresh Policy:
    NeverRefresh: 새 스택 추가해도 Duration 유지
    RefreshOnSuccessfulApplication: 스택 추가 시 Duration 갱신
Stack Expiration Policy:
    ClearEntireStack: Duration 만료 시 전체 스택 제거
    RemoveSingleStackAndRefreshDuration: Duration 만료 시 스택 1개만 제거, Duration 갱신
```

### 예시: 독 중독 스택

```
PoisonGE:
    Duration: 5초
    Stack: Aggregate by Source, Limit = 3
    RefreshPolicy: RefreshOnSuccessfulApplication
    ExpirationPolicy: RemoveSingleStackAndRefreshDuration

결과: 같은 적에게 독이 중첩될수록 스택 증가,
      매 5초마다 스택 1개씩 감소
```

---

## Immunity (면역)

GE 적용을 차단하는 두 가지 방법:

### 1. ASC 레벨 면역

```cpp
// 특정 태그를 가진 GE 차단
ASC->AddGameplayTagImmunity(FGameplayEffectQuery::MakeQuery_MatchAnyOwningTags(ImmuneTags));
```

### 2. GE Application Required/Ignored Tags 활용

```
무적 GE: Granted Tags += Status.Effect.Invincible

데미지 GE:
    Application Ignored Tags: Status.Effect.Invincible
→ 무적 태그 보유 시 데미지 GE 적용 자체 불가
```

### 3. PreGameplayEffectExecute에서 차단

```cpp
bool UMyAttributeSet::PreGameplayEffectExecute(FGameplayEffectModCallbackData& Data)
{
    if (/* 특정 조건 */)
        return false;  // false 반환 시 GE 취소
    return true;
}
```

---

## Remove GEs with Tags 패턴

새 GE 적용 시 기존 GE를 자동 제거하는 패턴:

```
SilenceGE:
    Remove GEs with Tags: Ability.Effect.Buff.Status

→ 침묵 GE 적용 시 모든 버프 상태 GE 제거
```
