# Attribute 기본 개념

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## Base 값과 Current 값의 차이

- **Base 값**: 활성 GE의 Modifier를 적용하기 전 입력값
- **Current 값**: 지속 중인 모든 GE의 Modifier를 Base에 적용한 결과값 (출력)

---

## AttributeSet을 하나로 합칠까, 여러 개로 나눌까

프로젝트에서 ASC와 AttributeSet을 가질 Actor 클래스 목록을 먼저 만들고, 각 클래스가 어떤 Attribute를 필요로 하고 필요로 하지 않는지를 정리한다.

예를 들어 Health/MaxHealth는 많은 Actor가 공유하지만, WeaponDamage는 일부에서만 필요하다. 이런 경우 별도의 AttributeSet으로 분리하는 것이 자연스럽다. Lyra도 이 방식을 따른다.

---

## ATTRIBUTE_ACCESSORS 매크로

UE 5.6부터는 `AttributeSet.h`에 `ATTRIBUTE_ACCESSORS_BASIC`이라는 이름으로 기본 제공된다.

이 매크로는 원래 `AttributeSet.h` 주석 안에 예시로 포함된 것인데, 관례적으로 프로젝트 AttributeSet 헤더에 복사해서 사용해왔다.

```cpp
#define ATTRIBUTE_ACCESSORS(ClassName, PropertyName) \
    GAMEPLAYATTRIBUTE_PROPERTY_GETTER(ClassName, PropertyName) \
    GAMEPLAYATTRIBUTE_VALUE_GETTER(PropertyName) \
    GAMEPLAYATTRIBUTE_VALUE_SETTER(PropertyName) \
    GAMEPLAYATTRIBUTE_VALUE_INITTER(PropertyName)
```

AttributeSet 프로퍼티에 이 매크로를 적용하면 Base 값 getter/setter와 `FGameplayAttribute` 정의 getter가 자동 생성된다.

```cpp
UCLASS()
class ULabHealthAttributeSet : public UAttributeSet
{
    GENERATED_BODY()
public:
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, ReplicatedUsing=OnRep_Health)
    FGameplayAttributeData Health;

    ATTRIBUTE_ACCESSORS(ULabHealthAttributeSet, Health)
};
```

### 생성되는 함수들

`ATTRIBUTE_ACCESSORS(MySet, Foo)` 적용 시 다음 함수가 생성된다.

| 함수 | 설명 |
|---|---|
| `InitFoo(Value)` | Base와 Current를 동시에 설정. Modifier가 없다고 가정하므로 **초기화 전용**으로만 사용 |
| `SetFoo(Value)` | Base 값을 설정하고 활성 Modifier를 반영해 Current 값 재계산 |
| `GetFoo()` | Current 값 반환. 마지막 변경 이후 캐시된 값 |
| `UMySet::GetFooAttribute()` | `FGameplayAttribute` 프로퍼티 정의 반환. 정적 함수라 어디서든 호출 가능. AttributeSet 이벤트에서 어떤 Attribute가 변경됐는지 확인할 때 유용 |

### Attribute에 직접 대입하면 안 되는 이유

`Health.BaseValue = 100.0f`처럼 `=`로 직접 쓰면 GAS 내부 파이프라인 전체가 우회된다.

| 우회되는 것 | 결과 |
|---|---|
| `PreAttributeChange` / `PostAttributeChange` | 클램핑, 변경 후 처리(MaxHealth 변경 시 Health 재클램핑 등)가 동작하지 않음 |
| ASC Aggregator | Attribute별 GE Modifier 합산 구조를 모르는 상태가 됨 — Current 값 계산이 깨짐 |
| 델리게이트 | `GetGameplayAttributeValueChangeDelegate` 바인딩된 UI·컴포넌트 콜백이 호출되지 않음 |
| 복제 | dirty 마킹이 안 되어 클라이언트에 변경이 전달되지 않음 |

`SetFoo()` / `InitFoo()` 또는 GE를 통해야 하는 이유가 이것이다.
