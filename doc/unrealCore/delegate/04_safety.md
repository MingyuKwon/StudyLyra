# 안전성과 수명 관리

---

## Dynamic vs Non-Dynamic

| | Non-Dynamic | Dynamic |
|--|-------------|---------|
| 함수 저장 방식 | 함수 포인터 직접 저장 | 함수 이름(FName)으로 저장 후 런타임 조회 |
| 속도 | 빠름 | 느림 (FName 조회 비용) |
| Blueprint 사용 | X | O |
| 직렬화 | X | O (함수 이름이 FName이므로) |
| UPROPERTY | X | O (BlueprintAssignable) |
| 바인딩 대상 | UObject / raw / SharedPtr / 람다 | UObject(UFUNCTION)만 가능 |

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
