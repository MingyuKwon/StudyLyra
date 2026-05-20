# BaseValue vs CurrentValue

> **GASDoc**: 4.3.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-value"></a>
#### BaseValue와 CurrentValue는 어떻게 다르며, GE 종류별로 어느 값이 바뀌는가?

| GE 종류 | 바꾸는 값 | 비고 |
|---|---|---|
| `Instant` | **BaseValue** | 영구 변경. CurrentValue도 뒤따라 갱신 |
| `Duration` / `Infinite` | **CurrentValue만** | Aggregator 경유. BaseValue는 그대로 |
| `Periodic` | **BaseValue** | Instant처럼 취급, 주기마다 적용 |

- **BaseValue**: 영구적인 기저값. Instant GE 적용 또는 `SetXxx()` 호출 시에만 바뀐다.
- **CurrentValue**: 지금 유효한 실효값. Aggregator가 BaseValue에 활성 중인 모든 Duration/Infinite GE Modifier를 합산해 계산한다.

예: 이동속도 BaseValue 600에 임시 버프 +50 적용 시 → CurrentValue = 650, BaseValue = 600 유지. 버프 만료 시 CurrentValue가 600으로 복귀한다.

**주의:** BaseValue를 Attribute의 최대값으로 혼동하지 말 것. 변동 가능한 최대값은 별도 Attribute로 만들고, 하드코딩 최소/최대값은 AttributeSet의 float으로 관리한다.

---

### FGameplayAttributeData가 BaseValue와 CurrentValue를 분리해서 갖는 이유는?

```cpp
struct FGameplayAttributeData
{
protected:
    float BaseValue;    // 영구적인 기저값
    float CurrentValue; // 버프/디버프까지 반영한 실효값
};
```

Duration/Infinite GE가 제거될 때 BaseValue를 건드리지 않고 Aggregator가 재계산만 하면 원복이 되기 때문이다. 두 값이 분리되지 않으면 GE 만료 시 "원래 값이 얼마였는지" 추적이 불가능하다.

게임 코드에서 `GetHealth()`를 호출하면 항상 CurrentValue를 반환한다.

**Periodic GE가 CurrentValue가 아닌 BaseValue를 바꾸는 이유:** 각 틱은 "확정된 이벤트"이기 때문이다. DoT 데미지처럼 틱마다 적용된 값은 GE가 만료된 후에도 남아야 한다. CurrentValue를 바꾸면 GE 만료 시 Aggregator가 제거되면서 데미지가 없던 일이 되어버린다.

---

### Instant, Duration, Infinite, Periodic GE는 각각 BaseValue와 CurrentValue 중 무엇을 변경하는가?

**Duration/Infinite GE 흐름:**

```
GE 적용 → Aggregator에 Modifier 추가 → Evaluate() = BaseValue + 모든 활성 Modifier → CurrentValue 갱신
GE 제거 → Aggregator에서 Modifier 제거 → 재계산 → CurrentValue = BaseValue 복귀
```

**Instant GE 흐름:**

```
GE 적용 → BaseValue 직접 변경 → Aggregator 재계산 → CurrentValue 갱신 → GE 즉시 소멸
```

### ATTRIBUTE_ACCESSORS 매크로가 생성하는 4개 함수는 각각 어떤 역할을 하는가?

```cpp
ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)
// 아래 4개가 자동 생성됨

static FGameplayAttribute GetHealthAttribute(); // FProperty 포인터 — GE Modifier에서 대상 Attribute 지정 시 사용
float GetHealth() const;                        // CurrentValue 읽기
void SetHealth(float NewVal);                   // ASC->SetNumericAttributeBase() 경유 → Aggregator 재계산 + 델리게이트 보장
void InitHealth(float NewVal);                  // BaseValue + CurrentValue 직접 세팅 (초기화 전용)
```

`SetHealth`가 ASC를 경유하는 이유: 직접 `Health.SetBaseValue(v)`를 쓰면 Aggregator 재계산과 `PreAttributeBaseChange` 델리게이트가 발동하지 않는다.

`InitHealth`는 초기화 시점에 Aggregator가 아직 붙기 전이므로 예외적으로 양쪽을 직접 세팅한다.
