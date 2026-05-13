# Delegate

> 소스:  
> `Engine/Source/Runtime/Core/Public/Delegates/Delegate.h`  
> `Engine/Source/Runtime/Core/Public/Delegates/MulticastDelegateBase.h`

타입 안전한 함수 포인터·콜백 시스템.  
특정 이벤트가 발생했을 때 미리 등록해둔 함수들을 호출하는 데 사용한다.

---

## 종류

| 종류 | 바인딩 수 | Blueprint | 직렬화 | 주요 용도 |
|------|---------|-----------|--------|----------|
| Delegate (Single) | 1개 | X | X | 단일 콜백 |
| Multicast Delegate | 여러 개 | X | X | 다수 리스너 |
| Dynamic Delegate | 1개 | O | O | Blueprint 단일 콜백 |
| Dynamic Multicast Delegate | 여러 개 | O | O | Blueprint 이벤트 (가장 흔함) |

---

## 선언 매크로

### Single-cast Delegate

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

### Multicast Delegate

```cpp
DECLARE_MULTICAST_DELEGATE(FOnGameOver);
DECLARE_MULTICAST_DELEGATE_OneParam(FOnScoreChanged, int32 /*NewScore*/);
```

Multicast는 반환값을 가질 수 없다 — 여러 함수가 각자 다른 값을 반환하면 어느 것을 쓸지 알 수 없기 때문이다.

### Dynamic Delegate (Blueprint 연동)

```cpp
DECLARE_DYNAMIC_DELEGATE(FOnGameStartDynamic);
DECLARE_DYNAMIC_DELEGATE_OneParam(FOnDamagedDynamic, float, Damage);
//                                                    ↑ 타입, ↑ 파라미터 이름 필수
```

Non-Dynamic과 달리 **파라미터 이름을 반드시 함께 써야 한다.**  
Blueprint에서 파라미터 이름이 노드 핀 이름으로 표시되기 때문이다.

### Dynamic Multicast Delegate (가장 흔한 이벤트 패턴)

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

## 바인딩

### Single-cast — Bind

```cpp
FOnDamaged OnDamaged;

// UCLASS 멤버 함수 (GC 추적됨 — 가장 안전)
OnDamaged.BindUObject(this, &AMyActor::HandleDamage);

// 일반 C++ 함수 포인터 (수명 직접 관리 필요)
OnDamaged.BindRaw(NativeObj, &FNativeClass::HandleDamage);

// static 함수
OnDamaged.BindStatic(&UMyLibrary::HandleDamage);

// 람다
OnDamaged.BindLambda([](float Damage)
{
    UE_LOG(LogTemp, Log, TEXT("Damage: %f"), Damage);
});

// TSharedPtr 기반 객체
OnDamaged.BindSP(SharedObj, &FMyClass::HandleDamage);
```

Single-cast는 이미 바인딩된 상태에서 다시 Bind하면 **이전 바인딩이 교체된다.**

### Multicast — Add

```cpp
FOnScoreChanged OnScoreChanged;

// 바인딩 추가 (여러 개 등록 가능)
FDelegateHandle Handle = OnScoreChanged.AddUObject(this, &AMyHUD::RefreshScore);
OnScoreChanged.AddUObject(this, &AMyGameMode::SaveScore);
OnScoreChanged.AddLambda([](int32 Score) { /* ... */ });

// 특정 바인딩 제거 (Handle로)
OnScoreChanged.Remove(Handle);

// 특정 오브젝트의 모든 바인딩 제거
OnScoreChanged.RemoveAll(this);
```

### Dynamic Delegate — BindDynamic / AddDynamic

```cpp
// Dynamic Single
FOnDamagedDynamic OnDamaged;
OnDamaged.BindDynamic(this, &AMyActor::HandleDamage);

// Dynamic Multicast
FOnHealthChanged OnHealthChanged;
OnHealthChanged.AddDynamic(this, &AMyActor::HandleHealthChanged);
OnHealthChanged.RemoveDynamic(this, &AMyActor::HandleHealthChanged);
```

`BindDynamic` / `AddDynamic`은 실제로는 매크로다.  
내부에서 함수 이름을 `FName`으로 변환해 등록하기 때문에  
**함수 시그니처가 Delegate 선언과 정확히 일치해야 한다.**

`AddDynamic`은 **`UFUNCTION`이 붙은 멤버 함수에만** 사용할 수 있다.  
`UFUNCTION` 없이 쓰면 컴파일 에러가 발생한다.

---

## 실행

### Single-cast

```cpp
FOnDamaged OnDamaged;

// 바인딩 확인 후 실행 (안전)
OnDamaged.ExecuteIfBound(50.f);

// 반드시 바인딩 되어있을 때만 (바인딩 없으면 assert)
OnDamaged.Execute(50.f);

// 바인딩 여부 확인
if (OnDamaged.IsBound())
{
    OnDamaged.Execute(50.f);
}
```

### Multicast

```cpp
FOnScoreChanged OnScoreChanged;

// 등록된 모든 함수 호출
OnScoreChanged.Broadcast(1000);

// 바인딩 여부 확인
OnScoreChanged.IsBound();
```

Multicast는 `ExecuteIfBound`가 없다. `Broadcast`는 바인딩이 없어도 안전하게 아무것도 하지 않는다.

---

## 내부 구현

### Non-Dynamic — 타입 이레이저 + IDelegateInstance

Delegate 변수 자체는 두 가지를 들고 있다.

```
TDelegate<void(float)>
├── TAlignedBytes<16> InlineStorage  ← 힙 할당 없이 인라인 저장 (small buffer 최적화)
└── IDelegateInstance* Instance      ← InlineStorage 또는 힙을 가리킴
```

`IDelegateInstance`는 인터페이스다. 바인딩 방식마다 이를 구현하는 별도 구체 클래스가 생성된다.

```
BindUObject(this, &AMyActor::HandleDamage)
  → TUObjectMethodDelegate 생성
      ├── TWeakObjectPtr<AMyActor> Object  ← GC 추적 가능
      └── void (AMyActor::*FuncPtr)(float) ← 멤버 함수 포인터

BindRaw(RawPtr, &FMyClass::HandleDamage)
  → TRawMethodDelegate 생성
      ├── FMyClass* Object                 ← raw 포인터 (수명 추적 없음)
      └── void (FMyClass::*FuncPtr)(float)

BindLambda([](float f) { ... })
  → TFunctorDelegate 생성
      └── 람다 객체 (캡처 포함)를 내부에 복사
```

`Execute()` 호출 시 흐름:

```
Delegate.Execute(50.f)
  → IDelegateInstance::Execute(Params)  ← 가상 호출
      → (Object.*FuncPtr)(50.f)         ← 실제 함수 호출
```

`ExecuteIfBound()`는 실행 전 `IDelegateInstance::IsSafeToExecute()`를 확인한다.  
`BindUObject`의 경우 이 안에서 `TWeakObjectPtr::IsValid()`가 호출된다 — 대상 UObject가 이미 수거됐으면 실행하지 않는다.

### Dynamic — FName + ProcessEvent

Dynamic Delegate는 함수 포인터를 저장하지 않는다.

```
AddDynamic(this, &AMyActor::HandleDamage)
  → 매크로가 "HandleDamage" 문자열을 FName으로 변환해 저장
      ├── UObject* Object
      └── FName FunctionName = FName("HandleDamage")

Execute() / Broadcast() 시
  → Object->FindFunctionByName(FName("HandleDamage"))
  → Object->ProcessEvent(Func, &Params)
```

`ProcessEvent`는 Blueprint VM 진입점과 같은 경로다.  
FName 조회 + ProcessEvent 스택 비용이 붙기 때문에 Non-Dynamic보다 느리다.

**왜 Dynamic은 구현이 다른가**

Blueprint 연동 때문이다.

Non-Dynamic은 C++ 컴파일 타임에 함수 포인터가 확정된다. 하지만 Blueprint 함수는 에디터에서 만들어지고 런타임에 로드되므로 컴파일 타임에 주소를 알 수 없다. Blueprint가 이벤트를 구독하려면 함수를 주소가 아닌 **이름**으로 등록해야 한다. 그래서 FName 기반 런타임 조회가 불가피하다.

`UFUNCTION`이 필수인 이유도 같은 맥락이다. FName으로 함수를 찾으려면 리플렉션 시스템에 그 함수가 등록돼 있어야 한다. `UFUNCTION`이 붙어야 UHT가 `UFunction` 객체를 생성하고 리플렉션 테이블에 등록한다. 등록이 없으면 `FindFunctionByName`이 찾지 못한다.

```
UFUNCTION() 있음 → UHT가 UFunction 생성 → 리플렉션 테이블 등록
                    → FindFunctionByName("HandleDamage") 성공

UFUNCTION() 없음 → 리플렉션 테이블에 없음 → 에러
```

FName 기반 조회, UFUNCTION 필수 조건, 느린 속도 모두 "Blueprint도 구독할 수 있는 이벤트"를 만들기 위한 트레이드오프다.

### Multicast

`TMulticastDelegate`는 내부적으로 Single-cast 인스턴스 배열을 들고 있다.

```
TMulticastDelegate<void(int32)>
└── TArray<TSharedRef<IDelegateInstance>> InvocationList
```

`Broadcast(1000)` 시 InvocationList를 순회하며 각 인스턴스의 `Execute()`를 호출한다.  
순회 도중 `Remove()`가 호출돼도 안전하도록 순회 전에 배열을 로컬에 복사하는 방어 로직이 내장돼 있다.

---

## Dynamic vs Non-Dynamic

| | Non-Dynamic | Dynamic |
|--|-------------|---------|
| 함수 저장 방식 | 함수 포인터 직접 저장 | 함수 이름(FName)으로 저장 후 런타임 조회 |
| 속도 | 빠름 | 느림 (FName 조회 비용) |
| Blueprint 사용 | X | O |
| 직렬화 | X | O (함수 이름이 FName이므로) |
| UPROPERTY | X | O (BlueprintAssignable) |

Dynamic Delegate가 느린 이유는 호출 시마다 FName으로 함수를 찾아야 하기 때문이다.  
C++끼리만 통신한다면 Non-Dynamic이 더 적합하다.

---

## 바인딩 안전성

| 바인딩 방법 | 대상 소멸 시 위험 |
|------------|----------------|
| `BindUObject` / `AddUObject` | GC가 대상 UObject 수거 시 자동으로 바인딩 무효화 |
| `BindRaw` / `AddRaw` | 대상 소멸 후에도 바인딩이 남아 크래시 위험 — 직접 Remove 필요 |
| `BindSP` / `AddSP` | TSharedPtr이 만료되면 자동으로 바인딩 무효화 |
| `BindLambda` / `AddLambda` | 람다가 캡처한 포인터의 수명을 직접 보장해야 함 |

`BindRaw`는 가장 빠르지만 가장 위험하다.  
UObject 기반 클래스라면 항상 `BindUObject`를 쓰는 것이 원칙이다.

---

## 수명 관리 — 소멸 전 명시적 제거

`AddUObject`는 GC가 대상을 수거할 때 자동으로 바인딩을 무효화하지만,  
**등록한 쪽이 먼저 소멸되는 경우**에는 명시적 제거가 필요하다.

UMG 위젯이 대표적인 예다 — `NativeDestruct`에서 반드시 제거한다.

```cpp
void UMyWidget::NativeOnInitialized()
{
    Super::NativeOnInitialized();
    ConfirmButton->OnClicked.AddDynamic(this, &UMyWidget::OnConfirmClicked);
}

void UMyWidget::NativeDestruct()
{
    Super::NativeDestruct();
    ConfirmButton->OnClicked.RemoveDynamic(this, &UMyWidget::OnConfirmClicked);
}
```

`RemoveAll(this)`를 쓰면 해당 오브젝트의 모든 바인딩을 한 번에 제거할 수 있다.

```cpp
void UMyWidget::NativeDestruct()
{
    Super::NativeDestruct();
    ConfirmButton->OnClicked.RemoveAll(this);  // this가 등록한 콜백 전부 제거
}
```

---

## 내 노트
