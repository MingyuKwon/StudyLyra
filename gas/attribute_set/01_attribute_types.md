# Attribute 타입 구분: FGameplayAttribute vs FGameplayAttributeData

## 한 줄 요약

- **`FGameplayAttributeData`** = 값을 **저장**하는 그릇 (BaseValue, CurrentValue)
- **`FGameplayAttribute`** = 그 그릇을 **가리키는 식별자/핸들** (어느 AttributeSet의 어느 프로퍼티인지)

## FGameplayAttributeData — 데이터 저장소

```cpp
// AttributeSet 클래스 안에 멤버 변수로 선언
UPROPERTY()
FGameplayAttributeData Health;  // 실제 float 값 두 개를 들고 있음
```

그 자체로는 "나는 Health다"라는 정체성이 없다. 그냥 float 두 개짜리 구조체다.

## FGameplayAttribute — 식별자/핸들

```cpp
struct FGameplayAttribute
{
    TFieldPath<FProperty> Attribute;      // 핵심: 어느 클래스의 어느 변수인지 가리키는 FProperty*
    TObjectPtr<UStruct>   AttributeOwner; // 소유 AttributeSet 클래스
    FString               AttributeName;
};
```

`FProperty*`를 감싼 래퍼다. "**ULyraHealthSet 클래스의 Health 변수**"를 런타임에 식별하는 키다.

## ATTRIBUTE_ACCESSORS 매크로로 보는 관계

```cpp
ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)
// 이 한 줄이 아래 세 함수를 만들어냄

// FGameplayAttributeData에서 float 읽기
float GetHealth() const { return Health.GetCurrentValue(); }

// FGameplayAttribute (식별자) 반환
static FGameplayAttribute GetHealthAttribute()
{
    static FProperty* Property = FindFieldChecked<FProperty>(
        ULyraHealthSet::StaticClass(), GET_MEMBER_NAME_CHECKED(ULyraHealthSet, Health)
    );
    return FGameplayAttribute(Property);
}

// FGameplayAttribute를 키로 ASC에 요청 → 내부적으로 FGameplayAttributeData 수정
void SetHealth(float NewVal) { ASC->SetNumericAttributeBase(GetHealthAttribute(), NewVal); }
```

## 어디서 각각 쓰이는가

| 용도 | 타입 |
|------|------|
| GE Modifier 타겟 지정 ("Health를 수정해라") | `FGameplayAttribute` |
| ASC에서 값 조회/설정 (`GetNumericAttribute`) | `FGameplayAttribute` (키) |
| `AttributeAggregatorMap`의 키 | `FGameplayAttribute` |
| `OnAttributeChanged` 델리게이트 바인딩 | `FGameplayAttribute` |
| 실제 float 값 읽기/쓰기 | `FGameplayAttributeData` |
| 복제 (`OnRep_Health` 파라미터) | `FGameplayAttributeData` |

> **비유:** `FGameplayAttributeData`는 메모리에 있는 **실제 박스**, `FGameplayAttribute`는 그 박스의 **주소가 적힌 라벨**.
> GAS 시스템이 "Health를 수정해라"는 명령을 주고받을 때는 항상 라벨(`FGameplayAttribute`)을 들고 다니다가,
> 실제로 값을 건드릴 때만 박스(`FGameplayAttributeData`)를 연다.
