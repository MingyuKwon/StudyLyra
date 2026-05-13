# 선언 매크로

---

## Single-cast Delegate

```cpp
// 파라미터 없음
DECLARE_DELEGATE(FOnGameStart);

// 파라미터 있음 — OneParam, TwoParams, ThreeParams ...
DECLARE_DELEGATE_OneParam(FOnDamaged, float /*Damage*/);
DECLARE_DELEGATE_TwoParams(FOnHit, AActor* /*HitActor*/, FVector /*HitLocation*/);

// 반환값 있음
DECLARE_DELEGATE_RetVal(bool, FOnCanFire);
DECLARE_DELEGATE_RetVal_OneParam(bool, FOnCanTakeDamage, float /*Damage*/);
```

---

## Multicast Delegate

```cpp
DECLARE_MULTICAST_DELEGATE(FOnGameOver);
DECLARE_MULTICAST_DELEGATE_OneParam(FOnScoreChanged, int32 /*NewScore*/);
```

Multicast는 반환값을 가질 수 없다 — 여러 함수가 각자 다른 값을 반환하면 어느 것을 쓸지 알 수 없기 때문이다.

---

## Dynamic Delegate (Blueprint 연동)

```cpp
DECLARE_DYNAMIC_DELEGATE(FOnGameStartDynamic);
DECLARE_DYNAMIC_DELEGATE_OneParam(FOnDamagedDynamic, float, Damage);
//                                                    ↑ 타입, ↑ 파라미터 이름 필수
```

Non-Dynamic과 달리 **파라미터 이름을 반드시 함께 써야 한다.**  
Blueprint에서 파라미터 이름이 노드 핀 이름으로 표시되기 때문이다.

---

## Dynamic Multicast Delegate (가장 흔한 이벤트 패턴)

```cpp
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnPlayerDied);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnHealthChanged, float, NewHealth);
```

`UPROPERTY(BlueprintAssignable)`과 함께 쓰면 Blueprint에서 이벤트를 구독할 수 있다.

```cpp
UCLASS()
class AMyActor : public AActor
{
    GENERATED_BODY()

    UPROPERTY(BlueprintAssignable)
    FOnHealthChanged OnHealthChanged;  // Blueprint에서 + 버튼으로 구독 가능
};
```

---

## 내 노트
