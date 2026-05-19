# Gameplay Effects

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## Modifier 드롭다운에서 속성 숨기기

GameplayEffect Modifier에서 특정 Attribute를 선택할 수 없도록 하려면, `UPROPERTY` 선언에 `HideFromModifiers` 메타 태그를 추가한다.

```cpp
UPROPERTY(..., meta = (HideFromModifiers))
FGameplayAttributeData Health;
```

---

## 속성값 초기화 — Instant GE와 Infinite GE 중 무엇을 쓸까?

대부분의 경우 **Instant GE**가 적합하다.

- Instant GE의 Modifier: Attribute의 **BaseValue**를 직접 변경한다.
- Infinite GE의 Modifier: **BaseValue로부터 CurrentValue를 계산하는 방식**을 제어한다.

어떤 방식을 선택할지의 핵심은 "해당 Modifier를 나중에 기억해야 하는가, 혹은 제거할 수 있는가"다.
Modifier가 이후 계산에 필요하거나 나중에 제거될 수 있다면 Infinite(또는 Duration) GE를 사용한다.

### Instant GE 예시 — 데미지

데미지를 적용한 뒤에 의미 있는 것은 최신 Health 값뿐이다.
따라서 Health의 BaseValue를 Instant GE로 변경하는 것이 자연스럽다.
MaxHealth 값으로 Health를 초기화하는 것도 마찬가지로 Instant GE가 적합하다.

### Infinite GE 예시 — 탤런트 트리 MaxHealth

탤런트 트리가 MaxHealth를 10/20/30% 증가시키고, 초기 MaxHealth가 100이라고 가정하자.
플레이어가 1랭크 탤런트를 선택했을 때:

- **Instant GE 방식**: BaseValue를 110으로 변경 → 2랭크 선택 시 문제가 생긴다.
  110이 새 BaseValue이므로 +10%를 다시 적용하면 `110 × 1.1 = 121`이 되어 잘못된 값이 나온다.
- **Infinite GE 방식**: +10% 배수 Modifier를 별도 보관 → 2랭크 선택 시 +10% Modifier를 제거하고 +20% Modifier를 추가하면 `100 × 1.2 = 120`으로 정확하다.

단순한 경우에는 Instant GE로 BaseValue를 설정하는 것과 Infinite GE로 가산(Additive) Modifier를 추가하는 것이 동일한 결과를 낸다.
하지만 프로젝트에 곱셈·나눗셈·Override 방식의 Instant GE가 있다면 달라진다.
그런 연산들은 BaseValue 자체를 바꾸기 때문에 Infinite GE의 가산 Modifier보다 먼저 적용된다.
**Attribute 계산 공식을 정확히 숙지**하는 것이 중요하다.

---

## 속성값의 영구적인 변경 — Instant GE와 Infinite GE 중 무엇을 쓸까?

판단 기준은 초기화와 같다.

변경 자체를 영구적으로 남겨야 한다면 **Instant GE**로 BaseValue를 수정한다.
**Health**는 대표적인 예다. 각 변경은 항상 최신 값에 작용하면 되므로 Instant GE로 처리한다.

Modifier를 별도로 보관해 두어야 CurrentValue를 재계산할 수 있다면 **Infinite GE**가 적합하다.
**MaxHealth, DamageResistance, MovementSpeed** 등이 여기에 해당한다.
아이템을 장착하거나 해제할 때 이 값들이 변하고, 여러 Modifier가 상호작용하기 때문이다.
(일부 아이템은 값을 더하고, 일부는 곱하거나 Override하는 방식으로 작동한다.)

---

## GameplayEffect 적용 시 추가 파라미터 전달 방법

GE를 적용할 때 Actor·Component 포인터, 넉백 방향 벡터, 수치값 등 부가 데이터를 함께 전달해야 할 때가 있다.

### SetByCaller 크기값 — 1차원 수치에 적합

GameplayTag에 float 값을 연결해 GameplayEffectSpec에 저장한 뒤 GE를 적용하는 방식이다.
GE의 Attribute Modifier가 이 SetByCaller 값을 사용할 수 있고, Execution 코드에서도 꺼내 쓸 수 있다.

### 커스텀 GameplayEffectContext 서브클래스 — 복잡한 데이터에 적합

더 복잡한 데이터가 필요하다면 `FGameplayEffectContext`를 상속해 프로젝트 전용 클래스를 만든다.
이 구조체는 프로젝트 전체에서 동일하게 사용된다. GE 클래스마다 다른 Context 클래스를 쓰는 것은 불가능하다.

```cpp
USTRUCT(BlueprintType)
struct FMyGameplayEffectContext : public FGameplayEffectContext
{
    GENERATED_BODY()

    UPROPERTY()
    TSoftObjectPtr<AActor> MyRelevantActor;

    UPROPERTY()
    FVector KnockbackForce;
};
```

어떤 Context 클래스를 사용할지는 커스텀 `AbilitySystemGlobals` 클래스에서 지정한다.
프로젝트에 커스텀 Globals 클래스가 없다면 `UAbilitySystemGlobals`를 상속해 만들고,
`Project Settings > Ability System Globals Class` 또는 `DefaultGame.ini`에서 등록한다.

```ini
[/Script/GameplayAbilities.AbilitySystemGlobals]
AbilitySystemGlobalsClassName=/Script/AbilitiesLab.LabAbilitySystemGlobals
```

커스텀 Globals 클래스에서 `AllocGameplayEffectContext()`를 오버라이드해 프로젝트 전용 Context를 반환한다.

```cpp
UCLASS()
class ABILITIESLAB_API ULabAbilitySystemGlobals : public UAbilitySystemGlobals
{
    GENERATED_BODY()

    virtual FGameplayEffectContext* AllocGameplayEffectContext() const override;
};

FGameplayEffectContext* ULabAbilitySystemGlobals::AllocGameplayEffectContext() const
{
    return new FLabGameplayEffectContext();
}
```

`AllocGameplayEffectContext()`는 GE 적용 시 GAS 내부에서 Context를 생성할 때 호출된다.
임의의 데이터를 전달하려면 Context를 직접 생성하고 커스텀 함수로 값을 설정한 뒤, GE 적용 시 완성된 Context를 넘기면 된다.
GE의 ExecutionCalculation 클래스에서 해당 데이터를 꺼내 활용할 수 있다.

```cpp
// Context에 값 설정
void ULabAbilitySystemGlobals::IncrementNumInEffectContext(const FGameplayEffectContextHandle& ContextHandle)
{
    FLabGameplayEffectContext* LabEffectContext = (FLabGameplayEffectContext*)ContextHandle.Get();
    LabEffectContext->MyNum++;
}

// ExecutionCalculation에서 값 추출
void ULabEffectContextTestExecution::Execute_Implementation(
    const FGameplayEffectCustomExecutionParameters& ExecutionParams,
    FGameplayEffectCustomExecutionOutput& OutExecutionOutput) const
{
    Super::Execute_Implementation(ExecutionParams, OutExecutionOutput);

    FGameplayEffectContextHandle ContextHandle = ExecutionParams.GetOwningSpec().GetEffectContext();
    FLabGameplayEffectContext* LabContext = (FLabGameplayEffectContext*)ContextHandle.Get();
    UE_LOG(LogTemp, Warning, TEXT("Extracted My Num = %d"), LabContext->MyNum);
}
```

---

## GameplayEffectContext는 GC(가비지 컬렉션)를 막지 않는다

`GameplayEffectContext`는 `GameplayEffectSpec`이 참조하지만, 이 참조는 GC 도달 가능성 분석에서 고려되지 않는다.
즉, Context 클래스 내부의 객체 포인터에 `UPROPERTY`를 붙여도 해당 객체가 GC에 의해 수집되는 것을 막을 수 없다.
언리얼 엔진은 레퍼런스 카운팅 방식의 다형성 구조체를 지원하지 않는다. 현재 이 한계를 해결할 계획은 없다.

Epic의 프로젝트에서는 Context 내의 모든 객체 포인터를 `TWeakObjectPtr`로 선언해 이 사실을 명시한다.
기반 클래스인 `FGameplayEffectContext`의 모든 객체 포인터도 `TWeakObjectPtr`이다.

### GC가 도달하지 못하는 이유

일반 `USTRUCT`에서 `UPROPERTY()` 포인터가 GC를 막는다는 것은 맞다.
하지만 `FGameplayEffectContext`는 `FGameplayEffectContextHandle` 안에 `TSharedPtr`로 보관된다.

```cpp
// FGameplayEffectContextHandle 내부 (GameplayEffectTypes.h)
TSharedPtr<FGameplayEffectContext> Data;  // UPROPERTY 없음
```

`TSharedPtr`에는 `UPROPERTY`를 붙일 수 없다.
GC는 `UPROPERTY`로 표시된 경로만 따라가므로, `Data` 필드에서 경로가 끊겨 `FGameplayEffectContext` 내부까지 아예 도달하지 못한다.

```
GC 스캔 경로:
FGameplayEffectSpec        (UPROPERTY)
  → FGameplayEffectContextHandle  (UPROPERTY)
    → TSharedPtr<FGameplayEffectContext>  ← 여기서 끊김 (UPROPERTY 아님)
      → FGameplayEffectContext 내부 UPROPERTY  ← 스캔 안 됨
```

따라서 Context 내부 필드에 `UPROPERTY`를 붙여도 GC 보호 효과가 없다.
Epic이 `TWeakObjectPtr`을 쓰는 것은 GC를 막을 수 없다는 사실을 코드로 명시하기 위해서다.
`UPROPERTY()`로 강한 참조처럼 보이게 두는 것보다, `TWeakObjectPtr`로 "이 포인터는 GC 보호 안 됨"을 명확히 표현하는 것이다.
