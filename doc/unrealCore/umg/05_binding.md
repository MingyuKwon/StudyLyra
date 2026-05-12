# 위젯 바인딩

> 출처:  
> `Engine/Source/Runtime/UMG/Public/Components/Widget.h` (line 69~86)  
> `Engine/Source/Runtime/UMG/Public/Blueprint/UserWidget.h` (line 505~510)

UMG에서 "바인딩"은 두 가지 의미로 쓰인다.  
1. **BindWidget** — C++ 변수를 WBP 내부 위젯에 자동 연결  
2. **Property Binding** — 위젯 속성을 함수 반환값에 연결

---

## BindWidget — C++ 변수와 WBP 위젯 연결

```cpp
// C++ 헤더
UCLASS()
class UMyHUDWidget : public UUserWidget
{
    GENERATED_BODY()

public:
    // WBP에서 이름이 "HealthBar"인 위젯을 자동으로 여기에 연결
    UPROPERTY(meta = (BindWidget))
    TObjectPtr<UProgressBar> HealthBar;

    // 없어도 컴파일 에러 안 남
    UPROPERTY(meta = (BindWidgetOptional))
    TObjectPtr<UTextBlock> OptionalLabel;
};
```

WBP 에디터에서 위젯 이름이 C++ 변수명과 **정확히 일치**해야 한다.  
이름이 다르면 에디터가 컴파일 에러를 표시한다 (`BindWidgetOptional`은 경고로 처리).

`Initialize()` 이후(WidgetTree 구성 완료 후) 변수에 값이 채워진다.  
`NativeOnInitialized()`에서 이미 접근 가능하다.

```cpp
void UMyHUDWidget::NativeOnInitialized()
{
    Super::NativeOnInitialized();

    // HealthBar는 이미 연결돼 있음
    HealthBar->SetPercent(1.0f);

    // 버튼 클릭 콜백 등록 — BindWidget 프로퍼티에 콜백을 붙이는 권장 위치
    ConfirmButton->OnClicked.AddDynamic(this, &UMyHUDWidget::OnConfirmClicked);
}
```

---

## BindWidgetAnim — UWidgetAnimation 연결

```cpp
UPROPERTY(meta = (BindWidgetAnim), Transient)
TObjectPtr<UWidgetAnimation> FadeInAnim;
```

WBP에 같은 이름의 애니메이션이 있으면 자동으로 연결된다.

```cpp
void UMyHUDWidget::NativeConstruct()
{
    Super::NativeConstruct();
    PlayAnimation(FadeInAnim);
}
```

---

## Property Binding — 속성을 함수로 연동

WBP 에디터에서 위젯 속성 옆의 "Bind" 버튼으로 설정한다.  
매 프레임 함수가 호출되어 위젯 속성이 갱신된다.

```
[WBP 에디터]
  TextBlock → Content 속성 → Bind → GetPlayerNameText 함수
                                            ↓
  [매 Paint 프레임] GetPlayerNameText() 호출 → 반환값을 텍스트로 표시
```

블루프린트 함수로 연결하는 것이 일반적이지만, C++로도 가능하다.

```cpp
// C++에서 TAttribute 바인딩 (Slate 수준)
// NativeConstruct에서 직접 Slate 속성에 바인딩
STextBlock::FArguments Args;
Args.Text(TAttribute<FText>::CreateUObject(this, &UMyHUDWidget::GetPlayerNameText));
```

> **참고**  
> Property Binding은 매 프레임 호출되므로 무거운 연산은 피한다.  
> 상태가 바뀔 때만 갱신하는 방식(델리게이트 기반)이 성능상 낫다.

---

## 이벤트 바인딩 — 델리게이트

위젯의 이벤트(클릭, 호버 등)에 콜백을 등록하는 방식이다.  
Delegate 상세는 [delegate.md](../delegate.md) 참고.

```cpp
// Dynamic Delegate (블루프린트에서도 호출 가능) — 대상 함수에 UFUNCTION 필수
MyButton->OnClicked.AddDynamic(this, &UMyWidget::OnButtonClicked);

// 람다 바인딩 (C++만)
MyButton->OnClicked.AddLambda([]()
{
    UE_LOG(LogTemp, Log, TEXT("Clicked"));
});
```

위젯이 소멸하기 전 `NativeDestruct`에서 반드시 해제한다.

```cpp
void UMyWidget::NativeDestruct()
{
    Super::NativeDestruct();
    MyButton->OnClicked.RemoveDynamic(this, &UMyWidget::OnButtonClicked);
}
```

---

## 정리

| 바인딩 종류 | 방법 | 갱신 시점 | 용도 |
|-------------|------|-----------|------|
| BindWidget | `UPROPERTY(meta=(BindWidget))` | Initialize 시 1회 | WBP 내부 위젯을 C++ 변수로 접근 |
| BindWidgetAnim | `UPROPERTY(meta=(BindWidgetAnim), Transient)` | Initialize 시 1회 | WBP 애니메이션을 C++ 변수로 접근 |
| Property Binding | WBP 에디터 Bind 버튼 | 매 프레임 | 속성을 함수 반환값에 연동 |
| 이벤트 바인딩 | `AddDynamic` / `AddLambda` | 이벤트 발생 시 | 버튼 클릭 등 이벤트 처리 |

---

## 내 노트

