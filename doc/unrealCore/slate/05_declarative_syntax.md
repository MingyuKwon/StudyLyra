# Slate 선언형 문법

> 출처:  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/DeclarativeSyntaxSupport.h`  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SWidget.h`

Slate는 C++ 안에서 HTML/XML 느낌의 선언형 문법을 제공한다.  
일반 함수 호출이 아니라 매크로와 연산자 오버로딩으로 구현된 DSL(도메인 특화 언어)이다.

---

## SNew() — 위젯 생성

```cpp
TSharedRef<STextBlock> MyText = SNew(STextBlock)
    .Text(FText::FromString("Hello"))
    .Font(FSlateFontInfo(FPaths::EngineContentDir() / TEXT("Slate/Fonts/Roboto-Regular.ttf"), 14))
    .ColorAndOpacity(FSlateColor(FLinearColor::White));
```

`SNew(T)`는 내부적으로 `T::FArguments`를 생성하고 `T::Construct()`를 호출한다.  
반환 타입은 `TSharedRef<T>`.

`SAssignNew()`는 생성과 동시에 변수에 대입한다.

```cpp
TSharedPtr<SButton> MyButton;
SAssignNew(MyButton, SButton)   // MyButton에 TSharedRef를 TSharedPtr로 저장
    .OnClicked(this, &SMyWidget::OnButtonClicked);
```

---

## SLATE_BEGIN_ARGS / SLATE_END_ARGS — 커스텀 위젯 파라미터 선언

커스텀 위젯을 만들 때 외부에서 `.파라미터명(값)`으로 설정할 수 있게 선언하는 매크로.

```cpp
class SMyWidget : public SCompoundWidget
{
public:
    SLATE_BEGIN_ARGS(SMyWidget)
        : _Label(FText::GetEmpty())   // 기본값
        , _FontSize(12)
    {}
        SLATE_ARGUMENT(FText, Label)       // .Label(텍스트)
        SLATE_ARGUMENT(int32, FontSize)    // .FontSize(14)
        SLATE_EVENT(FOnClicked, OnClicked) // .OnClicked(델리게이트)
    SLATE_END_ARGS()

    void Construct(const FArguments& InArgs);
};
```

```cpp
void SMyWidget::Construct(const FArguments& InArgs)
{
    FText LabelText = InArgs._Label;       // 언더스코어 prefix로 접근
    int32 FontSize  = InArgs._FontSize;
    // ...
}
```

**매크로 종류**:

| 매크로 | 용도 |
|--------|------|
| `SLATE_ARGUMENT(Type, Name)` | 값 복사로 전달되는 단순 파라미터 |
| `SLATE_ATTRIBUTE(Type, Name)` | `TAttribute<T>` — 값 또는 바인딩 함수 |
| `SLATE_EVENT(Type, Name)` | 델리게이트 이벤트 (FOnClicked 등) |
| `SLATE_NAMED_SLOT(Type, Name)` | 자식 위젯을 받는 슬롯 |

---

## 슬롯 문법 — [ ] 연산자

자식 위젯을 부모에 연결할 때 `[ ]` 연산자를 사용한다.

### SCompoundWidget 계열 (자식 1개)

```cpp
SNew(SBorder)
.Padding(FMargin(10.f))
[
    SNew(STextBlock).Text(FText::FromString("Inside Border"))
]
```

`[ ]` 안에 들어간 위젯이 `ChildSlot`에 배치된다.

### SPanel 계열 (자식 여러 개)

```cpp
SNew(SVerticalBox)

+ SVerticalBox::Slot()                          // + 연산자로 슬롯 추가
.AutoHeight()                                   // 슬롯 파라미터
.Padding(0, 0, 0, 4)
[
    SNew(STextBlock).Text(FText::FromString("Row 1"))
]

+ SVerticalBox::Slot()
.FillHeight(1.0f)                               // 남은 공간을 비율로 채움
[
    SNew(STextBlock).Text(FText::FromString("Row 2"))
]
```

`SHorizontalBox::Slot()`, `SVerticalBox::Slot()` 등 각 Panel 타입마다 슬롯 파라미터가 다르다.

**슬롯 크기 지정 방식**:

| 방식 | 의미 |
|------|------|
| `.AutoWidth()` / `.AutoHeight()` | 자식 DesiredSize만큼 사용 |
| `.FillWidth(1.0f)` / `.FillHeight(1.0f)` | 남은 공간을 비율로 분배 |
| `.MaxWidth(200.f)` | 최대 크기 제한 |

---

## TAttribute — 값 또는 함수 바인딩

`TAttribute<T>`는 **고정값** 또는 **게터 함수**를 모두 받을 수 있는 타입이다.

```cpp
// 고정값으로 설정
SNew(STextBlock)
.Text(FText::FromString("Static"))

// 함수로 바인딩 — 매 프레임 함수가 호출됨
SNew(STextBlock)
.Text(this, &SMyWidget::GetDynamicText)      // UObject 멤버 함수
.Text_Lambda([]() { return FText::AsNumber(FPlatformTime::Seconds()); })
```

함수 바인딩 방식은 위젯이 Paint될 때마다 호출된다.  
복잡한 계산은 매 프레임 실행되므로 주의.

---

## 이벤트 바인딩

```cpp
SNew(SButton)
.OnClicked(this, &SMyWidget::OnButtonClicked)         // 멤버 함수

.OnClicked_Lambda([]()                                // 람다
{
    UE_LOG(LogTemp, Log, TEXT("Clicked"));
    return FReply::Handled();
})
```

`FReply::Handled()` — 이벤트를 소비했음. 상위로 전파되지 않음.  
`FReply::Unhandled()` — 이벤트를 소비하지 않음. 상위 위젯으로 전파.

---

## 전체 예시 — 커스텀 위젯

```cpp
// MyWidget.h
class SMyWidget : public SCompoundWidget
{
public:
    SLATE_BEGIN_ARGS(SMyWidget)
        : _Title(FText::GetEmpty())
    {}
        SLATE_ARGUMENT(FText, Title)
        SLATE_EVENT(FSimpleDelegate, OnConfirm)
    SLATE_END_ARGS()

    void Construct(const FArguments& InArgs);

private:
    FSimpleDelegate OnConfirmDelegate;
};

// MyWidget.cpp
void SMyWidget::Construct(const FArguments& InArgs)
{
    OnConfirmDelegate = InArgs._OnConfirm;

    ChildSlot
    [
        SNew(SVerticalBox)

        + SVerticalBox::Slot().AutoHeight()
        [
            SNew(STextBlock).Text(InArgs._Title)
        ]

        + SVerticalBox::Slot().AutoHeight().Padding(0, 8, 0, 0)
        [
            SNew(SButton)
            .OnClicked_Lambda([this]()
            {
                OnConfirmDelegate.ExecuteIfBound();
                return FReply::Handled();
            })
            [ SNew(STextBlock).Text(FText::FromString("OK")) ]
        ]
    ];
}
```

사용:

```cpp
TSharedRef<SMyWidget> Widget = SNew(SMyWidget)
    .Title(FText::FromString("Are you sure?"))
    .OnConfirm(FSimpleDelegate::CreateUObject(this, &AMyActor::OnUserConfirmed));
```

---

## 내 노트

