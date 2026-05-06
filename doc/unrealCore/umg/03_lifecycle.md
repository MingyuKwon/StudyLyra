# UUserWidget 생명주기

> 출처:  
> `Engine/Source/Runtime/UMG/Public/Blueprint/UserWidget.h` (line 282, 505~540)  
> `Engine/Source/Runtime/UMG/Private/UserWidget.cpp` (line 135, 1824~1920)

---

## 생명주기 함수 전체 흐름

```
CreateWidget<UMyWidget>(PC, UMyWidget::StaticClass())
    │
    └─ UUserWidget::Initialize()          ← 생성 시 딱 1회
          └─ NativeOnInitialized()
                └─ OnInitialized()        ← BP 이벤트 "Event On Initialized"

MyWidget->AddToViewport()  (또는 위젯 트리에 삽입)
    │
    └─ TakeWidget() → Slate 위젯 생성
    └─ NativePreConstruct()               ← Slate 붙기 직전
          └─ PreConstruct(bIsDesignTime)  ← BP 이벤트 (에디터/런타임 모두)
    └─ NativeConstruct()                  ← Slate가 붙은 직후
          └─ Construct()                  ← BP 이벤트 "Event Construct" (BeginPlay 상당)

[매 프레임 — Slate Paint 단계]
    └─ NativeTick(MyGeometry, DeltaTime)  ← 틱이 활성화된 경우만
          └─ Tick(MyGeometry, DeltaTime)  ← BP 이벤트

MyWidget->RemoveFromParent()  (또는 위젯 트리에서 제거)
    └─ NativeDestruct()
          └─ Destruct()                   ← BP 이벤트 "Event Destruct"
```

> **참고**  
> `AddToViewport()` / `RemoveFromParent()`를 반복하면 Construct/Destruct가 여러 번 불린다.  
> 1회만 실행돼야 하는 초기화는 반드시 `OnInitialized()`에서 해야 한다.

---

## Initialize() — 생성 시 1회

```cpp
// UserWidget.cpp:135
bool UUserWidget::Initialize()
{
    if (!bInitialized && !HasAnyFlags(RF_ClassDefaultObject))  // CDO는 건너뜀
    {
        // WidgetTree 초기화 (WBP 클래스면 블루프린트 트리 로드)
        BGClass->InitializeWidget(this);

        // 이후 NativeOnInitialized() 호출
        NativeOnInitialized();

        bInitialized = true;
    }
}
```

`CreateWidget<T>()`를 호출하면 내부적으로 `Initialize()`가 실행된다.  
이 시점에 WidgetTree와 BindWidget 프로퍼티가 모두 연결된다.

---

## NativeOnInitialized() / OnInitialized — 가장 이른 초기화 시점

```cpp
// UserWidget.h:507
// "Called once only at game time on non-template instances.
//  If you have one-time things to establish up-front
//  (like binding callbacks to events on BindWidget properties), do so here."
```

엔진이 권장하는 용도:
- BindWidget 프로퍼티(버튼, 텍스트 등)에 이벤트 콜백 등록
- 서브시스템, 게임 인스턴스 등 외부 참조 캐싱

**이 시점에 WidgetTree가 이미 구성돼 있다.** BindWidget 변수로 자식 위젯에 접근할 수 있다.

```cpp
void UMyWidget::NativeOnInitialized()
{
    Super::NativeOnInitialized();

    // MyButton은 BindWidget — 이 시점에 안전하게 접근 가능
    MyButton->OnClicked.AddDynamic(this, &UMyWidget::OnButtonClicked);
}
```

---

## NativePreConstruct() / PreConstruct — 에디터에서도 호출

Slate가 붙기 직전에 호출된다.  
에디터 디자이너에서 미리보기를 갱신할 때도 호출된다.

```cpp
// UserWidget.h:515
// "Called by both the game and the editor."
// "WARNING: Do not access game-related state here — may crash the editor."
```

용도:
- 텍스트, 색상, 아이콘처럼 로컬 데이터 기반의 외관 초기화
- 에디터 미리보기에서도 올바르게 보여야 하는 시각 세팅

게임 상태(GameMode, PlayerController 등)에 절대 접근하지 않는다.

---

## NativeConstruct() / Construct — Slate 추가 직후

```cpp
// UserWidget.h:529
// "Called after the underlying slate widget is constructed."
// "This event may be called multiple times due to adding and removing from the hierarchy."
// "If you need a true called-once-when-created event, use OnInitialized."
```

`AddToViewport()`나 다른 위젯 트리에 삽입될 때마다 호출된다.  
Actor의 `BeginPlay()`에 대응하는 시점이다.

용도:
- 게임 상태 참조 초기화 (GameState, PlayerState 등)
- 데이터 바인딩 시작
- 타이머 등록

```cpp
void UMyWidget::NativeConstruct()
{
    Super::NativeConstruct();

    // 게임 상태에 접근해도 안전
    AMyGameState* GS = GetWorld()->GetGameState<AMyGameState>();
    UpdateHealthBar(GS->GetPlayerHealth());
}
```

---

## NativeDestruct() / Destruct — Slate 제거 직후

`RemoveFromParent()`로 위젯이 화면에서 제거될 때 호출된다.  
Construct와 마찬가지로 여러 번 호출될 수 있다.

용도:
- 타이머 해제
- 델리게이트 언바인딩
- Construct에서 등록한 것들 정리

---

## NativeTick() — 프레임마다

```cpp
// UserWidget.h:282
// 기본 클래스 선언:
// UCLASS(... meta=(DisableNativeTick) ...)
```

`UUserWidget` 기본값은 **Tick 비활성화**다.  
블루프린트에서 Tick 이벤트를 사용하거나, C++에서 `bCanEverTick`을 활성화해야 호출된다.

Tick이 활성화되는 조건:
- WBP에서 Event Tick 노드를 연결
- C++ 서브클래스에서 `bCanEverTick = true` 설정
- 메타 태그 `DisableNativeTick` 제거

```cpp
// Tick이 필요한 경우 생성자에서 활성화
UMyWidget::UMyWidget()
{
    // DisableNativeTick 메타가 있으면 이 방법으로는 안 됨
    // WBP에서 Tick 노드를 연결하거나 UpdateCanTick()을 통해 처리
}
```

> **참고**  
> Tick 대신 `FTimerHandle`이나 델리게이트 기반으로 갱신하는 것이 성능상 낫다.  
> 매 프레임 폴링이 아니라 상태 변화 시점에만 업데이트하는 방식을 선호한다.

---

## 정리

| 함수 | 호출 시점 | 횟수 | 주요 용도 |
|------|-----------|:----:|-----------|
| `NativeOnInitialized` | `CreateWidget()` 직후 | 1회 | BindWidget 콜백 등록, 캐싱 |
| `NativePreConstruct` | Slate 생성 직전 | 여러 번 | 로컬 데이터 기반 외관 초기화 |
| `NativeConstruct` | `AddToViewport()` 직후 | 여러 번 | 게임 상태 참조, 타이머 등록 |
| `NativeDestruct` | `RemoveFromParent()` 직후 | 여러 번 | 타이머·델리게이트 정리 |
| `NativeTick` | 매 프레임 | 많음 | 실시간 갱신 (기본 비활성화) |

---

## 내 노트

