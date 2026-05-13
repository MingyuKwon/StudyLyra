# 내부 구현

---

## Non-Dynamic — 타입 이레이저 + IDelegateInstance

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

`TDelegate`는 `IDelegateInstance*` 하나만 들고 있으면 된다.  
실제로 뭐가 들어있든 `Execute()`만 부르면 동작한다 — 이것이 **타입 이레이저** 패턴이다.

`Execute()` 호출 시 흐름:

```
Delegate.Execute(50.f)
  → IDelegateInstance::Execute(Params)  ← 가상 호출
      → (Object.*FuncPtr)(50.f)         ← 실제 함수 호출
```

`ExecuteIfBound()`는 실행 전 `IDelegateInstance::IsSafeToExecute()`를 확인한다.  
`BindUObject`의 경우 이 안에서 `TWeakObjectPtr::IsValid()`가 호출된다 — 대상 UObject가 이미 수거됐으면 실행하지 않는다.

### InlineStorage — Small Buffer Optimization

바인딩 크기가 16바이트 이하면 `InlineStorage`에 직접 올린다(placement new). 힙 할당이 없다.

```
BindUObject (TWeakObjectPtr + 함수포인터 ≈ 16바이트)
  → InlineStorage 안에 placement new → 힙 할당 없음

BindLambda (캡처가 많아서 크면)
  → 16바이트 초과 → 힙 할당, Instance가 힙 포인터를 가리킴
```

---

## Dynamic — FName + ProcessEvent

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

`UFUNCTION`이 필수인 이유도 같은 맥락이다. FName으로 함수를 찾으려면 리플렉션 시스템에 그 함수가 등록돼 있어야 한다. `UFUNCTION`이 붙어야 UHT가 `UFunction` 객체를 생성하고 리플렉션 테이블에 등록한다.

```
UFUNCTION() 있음 → UHT가 UFunction 생성 → 리플렉션 테이블 등록
                    → FindFunctionByName("HandleDamage") 성공

UFUNCTION() 없음 → 리플렉션 테이블에 없음 → 에러
```

FName 기반 조회, UFUNCTION 필수 조건, 느린 속도 모두 "Blueprint도 구독할 수 있는 이벤트"를 만들기 위한 트레이드오프다.

---

## Multicast

`TMulticastDelegate`는 내부적으로 Single-cast 인스턴스 배열을 들고 있다.

```
TMulticastDelegate<void(int32)>
└── TArray<TSharedRef<IDelegateInstance>> InvocationList
```

`Broadcast(1000)` 시 InvocationList를 순회하며 각 인스턴스의 `Execute()`를 호출한다.  
순회 도중 `Remove()`가 호출돼도 안전하도록 순회 전에 배열을 로컬에 복사하는 방어 로직이 내장돼 있다.

---

## 복사 / 이동 / 소멸

**복사 생성자**

InlineStorage 안에 `IDelegateInstance`가 있기 때문에 단순 `memcpy`로는 안 된다.  
`IDelegateInstance`에 가상 `Clone()` 메서드가 있어서 복사 시 바인딩 전체를 새로 복제한다.

```cpp
FOnDamaged A;
A.BindUObject(this, &AMyActor::HandleDamage);

FOnDamaged B = A;  // IDelegateInstance::Clone() 호출
// B의 InlineStorage에 새 TUObjectMethodDelegate 생성
// TWeakObjectPtr, FuncPtr 모두 복사됨
```

**이동 생성자**

InlineStorage를 그대로 `memcpy`하고 원본을 비운다.  
`IDelegateInstance`를 새로 만들 필요가 없어서 복사보다 빠르다.

```cpp
FOnDamaged B = MoveTemp(A);
// A의 InlineStorage 16바이트를 B로 전달
// A는 IsBound() == false 상태가 됨
```

바인딩 대상이 InlineStorage보다 크면 힙에 올라가는데, 이 경우 이동은 힙 포인터만 넘기므로 더욱 O(1)이다.

**Multicast의 복사 vs 이동**

`TArray<IDelegateInstance>`를 들고 있어서 비용 차이가 크다.

| | 동작 | 비용 |
|--|------|------|
| 복사 | TArray 전체 복사 + 각 Instance마다 `Clone()` | O(n) |
| 이동 | TArray 포인터만 전달 | O(1) |

Multicast를 컨테이너에 담을 때는 복사보다 이동을 쓰는 것이 성능상 유리하다.

**소멸자**

소멸 시 `IDelegateInstance`의 소멸자를 호출해 정리한다.  
InlineStorage에 있으면 placement destroy, 힙에 있으면 `delete`.

---

## 내 노트
