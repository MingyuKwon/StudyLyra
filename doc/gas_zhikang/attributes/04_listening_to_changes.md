# Attribute 변경 감지 방법

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 방법 1 — C++ ASC 값 변경 델리게이트

C++에서 ASC에 직접 접근 가능한 경우 사용한다. `GetGameplayAttributeValueChangeDelegate()`로 Attribute별 델리게이트를 얻는다. `ATTRIBUTE_ACCESSORS` 매크로로 생성된 `GetFooAttribute()` 정적 함수가 필요하다.

```cpp
void AMyCharacter::BeginPlay()
{
    Super::BeginPlay();
    AbilitySystemComp->InitAbilityActorInfo(this, this);
    AbilitySystemComp->GetGameplayAttributeValueChangeDelegate(
        UMyHealthAttributeSet::GetHealthAttribute()
    ).AddLambda([](const FOnAttributeChangeData& Data) {
        UE_LOG(LogTemp, Warning, TEXT("health changed: %.2f -> %.2f"), Data.OldValue, Data.NewValue);
    });
}
```

---

## 방법 2 — GameplayAbility 블루프린트 Task

GA 블루프린트에서 `WaitForAttributeChange` AbilityTask를 사용한다. 소유 Actor 또는 다른 Actor의 Attribute가 변경될 때까지 대기하고, 변경 시 `OnChange` 핀을 실행한다.

---

## 방법 3 — AttributeSet의 BlueprintAssignable 델리게이트

`UAttributeSet::PostAttributeChange()`와 `PostAttributeBaseChange()`는 Attribute 값 변경이 처음 보고되는 가상 함수다. 이를 오버라이드해서 변경에 반응하거나 델리게이트를 브로드캐스트한다.

```cpp
DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(
    FAttributeChangedEvent, UAttributeSet*, AttributeSet, float, OldValue, float, NewValue);

UCLASS()
class ULabHealthAttributeSet : public UAttributeSet
{
    GENERATED_BODY()

    virtual void PostAttributeChange(
        const FGameplayAttribute& Attribute, float OldValue, float NewValue) override;

    UPROPERTY(BlueprintAssignable)
    FAttributeChangedEvent OnHealthChanged;
};
```

AttributeSet을 먼저 resolve한 뒤 델리게이트에 바인딩해야 하므로, 블루프린트 그래프가 다소 복잡해진다.

---

## 방법 4 — BlueprintSpawnableComponent 래핑 (Lyra 방식)

블루프린트에서 ASC → AttributeSet을 거쳐 델리게이트에 접근하는 과정이 번거롭다. 이를 처리하는 전용 컴포넌트 클래스를 만들어 편의성을 높일 수 있다. Lyra의 `LyraHealthComponent`가 이 패턴의 예시다.

컴포넌트가 내부적으로 ASC와 AttributeSet을 처리하고, 블루프린트용 `BlueprintAssignable` 델리게이트를 외부에 노출한다.

```cpp
void ULyraHealthComponent::InitializeWithAbilitySystem(ULyraAbilitySystemComponent* InASC)
{
    // AttributeSet의 native 델리게이트에 바인딩
    HealthSet->OnHealthChanged.AddUObject(this, &ThisClass::HandleHealthChanged);
    HealthSet->OnMaxHealthChanged.AddUObject(this, &ThisClass::HandleMaxHealthChanged);
    HealthSet->OnOutOfHealth.AddUObject(this, &ThisClass::HandleOutOfHealth);
}
```

**장점**: 블루프린트에서 Health 변경을 감지하는 데 필요한 노드 수가 크게 줄어든다.

**단점**: Actor Component가 추가되므로 메모리 오버헤드가 생긴다.
