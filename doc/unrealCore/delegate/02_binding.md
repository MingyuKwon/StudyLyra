# 바인딩과 실행

---

## Single-cast — Bind

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

---

## Multicast — Add

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

---

## Dynamic — BindDynamic / AddDynamic

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

### AddDynamicRaw / AddDynamicSP가 없는 이유

Non-Dynamic에 `AddRaw`, `AddUObject`, `AddSP`, `AddLambda`가 따로 있는 이유는  
대상의 종류마다 수명 추적 방식이 달라서 각각 별도 메서드가 필요하기 때문이다.

Dynamic은 내부 구조 자체가 `UObject* + FName`이다.  
`ProcessEvent`가 UObject의 메서드라서 처음부터 UObject만 받을 수 있고,  
raw 포인터나 SharedPtr을 바인딩할 방법 자체가 없다.

```
AddDynamic(this, &AMyActor::Func)
  → this는 반드시 UObject
  → 저장: UObject* + FName("Func")
```

`AddDynamic` = `AddDynamicUObject`가 맞고,  
`AddDynamicRaw` / `AddDynamicSP` / `AddDynamicLambda`는 존재하지 않는다.

---

## 실행

### Single-cast

```cpp
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

**바인딩 없이 Execute() 호출 시**

내부에 `checkf(IsBound(), ...)` 가 있어서 Debug / Development 빌드에서는 즉시 assert로 크래시된다.  
Shipping 빌드에서는 check가 제거되므로 미정의 동작이 된다.  
바인딩 여부가 불확실하면 반드시 `ExecuteIfBound()`를 쓴다.

### Multicast

```cpp
// 등록된 모든 함수 호출
OnScoreChanged.Broadcast(1000);

// 바인딩 여부 확인
OnScoreChanged.IsBound();
```

**바인딩 없이 Broadcast() 호출 시**

InvocationList가 비어 있으면 순회 없이 그냥 반환한다. 크래시 없이 안전하다.  
`ExecuteIfBound`가 없는 이유도 여기에 있다 — `Broadcast` 자체가 항상 안전하기 때문이다.

---

## 내 노트
