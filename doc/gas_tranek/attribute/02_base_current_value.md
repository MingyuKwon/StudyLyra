# BaseValue vs CurrentValue

> **GASDoc**: 4.3.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-value"></a>
#### BaseValue와 CurrentValue는 어떻게 다르며, GE 종류별로 어느 값이 바뀌는가?

Attribute는 두 개의 값으로 구성된다. `BaseValue`는 Attribute의 영구적인 값이며, `CurrentValue`는 BaseValue에 GameplayEffect에 의한 임시 수정값을 더한 값이다. 예를 들어 캐릭터의 이동속도 Attribute의 BaseValue가 600 units/second라면, GameplayEffect가 이동속도를 수정하지 않는 한 CurrentValue도 600 u/s다. 여기에 임시 50 u/s 이동속도 버프를 받으면 BaseValue는 600 u/s로 유지되고 CurrentValue는 600 + 50으로 총 650 u/s가 된다. 이동속도 버프가 만료되면 CurrentValue는 다시 BaseValue인 600 u/s로 돌아간다.

GAS를 처음 접하는 사람들은 종종 BaseValue를 Attribute의 최대값으로 혼동하고 그렇게 다루려 한다. 이는 잘못된 접근이다. 어빌리티나 UI에서 참조할 수 있는 변동 가능한 최대값은 별도의 Attribute로 처리해야 한다. 하드코딩된 최대값과 최소값의 경우, 최대값과 최소값을 설정할 수 있는 `FAttributeMetaData`와 함께 `DataTable`을 정의하는 방법이 있지만, Epic의 해당 구조체 위 주석에 "작업 중(work in progress)"이라고 명시되어 있다. 자세한 내용은 `AttributeSet.h`를 참고한다. 혼란을 피하기 위해, 어빌리티나 UI에서 참조할 수 있는 최대값은 별도의 Attribute로 만들고, Attribute 클램핑에만 사용되는 하드코딩 최대값과 최소값은 AttributeSet의 하드코딩 float으로 정의하는 것을 권장한다. Attribute의 클램핑은 CurrentValue 변경 시 PreAttributeChange()에서, GameplayEffect에 의한 BaseValue 변경 시 PostGameplayEffectExecute()에서 처리한다.

`Instant` GameplayEffect는 BaseValue를 영구적으로 변경하며, `Duration`과 `Infinite` GameplayEffect는 CurrentValue를 변경한다. `Periodic` GameplayEffect는 Instant GameplayEffect처럼 취급되어 BaseValue를 변경한다.

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

개념 요약의 내용을 구현 관점에서 보면:

- **BaseValue** = "진짜 값". Instant GE가 적용되거나 `SetXxx()`를 호출할 때만 바뀐다.
  GE가 나중에 제거돼도 BaseValue에 기록된 변경은 남는다.
- **CurrentValue** = "지금 유효한 값". Aggregator가 BaseValue를 기반으로 활성 중인 모든 Duration/Infinite GE Modifier를 합산해 계산한다.
  GE가 제거되면 Aggregator가 재계산하여 BaseValue 기준으로 복귀한다.

게임 코드에서 `GetHealth()`를 호출하면 항상 CurrentValue를 반환한다.
BaseValue를 직접 읽어야 할 일은 드물고, 대부분 CurrentValue가 곧 "현재 체력"이다.

**Periodic GE는 Instant처럼 취급된다.** `Period`마다 Modifier를 BaseValue에 직접 적용하고 완료되면 끝이다. Duration 내내 Aggregator에 쌓이는 것이 아니다.

Periodic이 CurrentValue가 아닌 BaseValue를 바꾸는 이유는 각 틱이 "확정된 이벤트"이기 때문이다.
DoT(독 데미지)를 예로 들면, 틱마다 맞은 데미지는 GE가 만료된 후에도 남아야 한다.
만약 CurrentValue를 바꿨다면 독 GE가 만료될 때 Aggregator가 제거되면서 데미지가 없던 일이 되어버린다.
Periodic의 각 틱은 Instant GE를 주기적으로 터뜨리는 것과 동일하게 설계되어 있다.

---

### Instant, Duration, Infinite, Periodic GE는 각각 BaseValue와 CurrentValue 중 무엇을 변경하는가?

"GE가 Attribute를 바꾼다"고 할 때, GE 종류에 따라 건드리는 값이 다르다.

| GE 종류 | 바꾸는 값 | 비고 |
|---|---|---|
| `Instant` | **BaseValue** | 영구 변경. CurrentValue도 뒤따라 갱신 |
| `Duration` / `Infinite` | **CurrentValue만** | Aggregator 경유. BaseValue는 그대로 |
| `Periodic` | **BaseValue** | Instant처럼 취급, 주기마다 |

**Duration/Infinite GE 흐름:**

```
GE 적용
  → Aggregator에 Modifier 추가
  → Aggregator.Evaluate() = BaseValue + 모든 활성 Modifier 합산
  → CurrentValue 갱신

GE 제거
  → Aggregator에서 Modifier 제거 → 재계산
  → CurrentValue = BaseValue 복귀
```

BaseValue는 전혀 건드리지 않는다.
Aggregator가 "지금 얼마짜리 Modifier들이 붙어 있냐"를 관리하고, BaseValue에 더해 CurrentValue를 뽑아낸다.

**Instant GE 흐름:**

```
GE 적용
  → BaseValue 직접 변경
  → Aggregator 없으면: CurrentValue = 새 BaseValue로 동기화
  → Aggregator 있으면: 재계산해서 CurrentValue 갱신
  → GE는 적용 즉시 사라짐 (ActiveGameplayEffects에 남지 않음)
```

### ATTRIBUTE_ACCESSORS 매크로가 생성하는 4개 함수는 각각 어떤 역할을 하는가?

```cpp
ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)
// 아래 4개가 자동 생성됨

static FGameplayAttribute GetHealthAttribute(); // FProperty 포인터 — GE Modifier에서 "어느 Attribute를 건드릴지" 지정할 때 사용
float GetHealth() const;                        // CurrentValue 읽기
void SetHealth(float NewVal);                   // ASC->SetNumericAttributeBase() 경유 → Aggregator 재계산 + 델리게이트 보장
void InitHealth(float NewVal);                  // BaseValue + CurrentValue 직접 세팅 (초기화 전용)
```

`SetHealth`가 ASC를 경유하는 이유:
직접 `Health.SetBaseValue(v)`를 쓰면 Aggregator 재계산이 일어나지 않고 `PreAttributeBaseChange` 델리게이트도 발동하지 않는다.
ASC의 `SetNumericAttributeBase()`를 거쳐야 이 두 가지가 보장된다.

`InitHealth`만 예외적으로 직접 양쪽을 세팅한다.
초기화 시점은 아직 Aggregator가 붙기 전이라 재계산이 필요 없고, 빠르게 초기값을 주입하는 것이 목적이기 때문이다.
