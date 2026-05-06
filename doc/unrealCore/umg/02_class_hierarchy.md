# UWidget 클래스 계층

> 출처:  
> `Engine/Source/Runtime/UMG/Public/Components/Widget.h`  
> `Engine/Source/Runtime/UMG/Public/Components/PanelWidget.h`  
> `Engine/Source/Runtime/UMG/Public/Components/ContentWidget.h`  
> `Engine/Source/Runtime/UMG/Public/Blueprint/UserWidget.h`

---

## 전체 계층 구조

```
UVisual
  └── UWidget                      ← 모든 UMG 위젯의 기반
        ├── UUserWidget            ← WBP의 기반. 개발자가 직접 만드는 복합 위젯
        ├── UPanelWidget           ← 자식 여러 개를 담는 레이아웃 위젯
        │     ├── UCanvasPanel     절대좌표 자유 배치
        │     ├── UVerticalBox     세로 배치
        │     ├── UHorizontalBox   가로 배치
        │     ├── UOverlay         겹쳐 쌓기
        │     ├── UGridPanel       격자 배치
        │     └── UWidgetSwitcher  한 번에 하나만 표시
        ├── UContentWidget         ← 자식 1개를 감싸는 위젯
        │     ├── UButton          클릭 이벤트 추가
        │     ├── UBorder          배경·테두리·패딩 추가
        │     └── UScrollBox       스크롤 추가
        └── (리프 위젯)            ← 자식 없는 출력 전용 위젯
              ├── UTextBlock       텍스트 렌더링
              ├── UImage           이미지/브러시 렌더링
              ├── UProgressBar     진행률 바
              ├── USlider          슬라이더
              └── UEditableText    텍스트 입력
```

---

## UWidget — 모든 위젯의 기반

`UObject`를 상속하므로 GC, UPROPERTY, 블루프린트 노출이 가능하다.

핵심 멤버:

```cpp
// Widget.h
class UWidget : public UVisual
{
    // Slate 위젯 캐시 — TakeWidget() 호출 시 생성·저장
    TWeakPtr<SWidget> MyWidget;

    // 위젯 가시성
    ESlateVisibility Visibility;

    // 렌더 변환 (위치, 회전, 스케일, 피벗)
    FWidgetTransform RenderTransform;

    // 대응하는 Slate 위젯을 반환. 없으면 RebuildWidget()으로 생성
    TSharedRef<SWidget> TakeWidget();

    // 서브클래스가 오버라이드해 대응 SWidget을 생성
    virtual TSharedRef<SWidget> RebuildWidget();
};
```

---

## UUserWidget — 개발자가 만드는 복합 위젯

WBP(Widget Blueprint)를 만들면 이 클래스를 상속한 클래스가 생성된다.  
내부에 `WidgetTree`가 있어 자식 UWidget들을 소유한다.

```cpp
class UUserWidget : public UWidget
{
    // 자식 위젯 트리. UPROPERTY이므로 GC가 추적
    UPROPERTY(Transient)
    TObjectPtr<UWidgetTree> WidgetTree;

    // 뷰포트에 추가
    void AddToViewport(int32 ZOrder = 0);

    // 특정 LocalPlayer의 화면에 추가 (스플릿스크린 대응)
    bool AddToPlayerScreen(int32 ZOrder = 0);

    // 생명주기 함수 (자세한 내용 → 03_lifecycle.md)
    virtual void NativeOnInitialized();
    virtual void NativePreConstruct();
    virtual void NativeConstruct();
    virtual void NativeDestruct();
    virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime);
};
```

`UUserWidget`만 `AddToViewport()`를 직접 호출할 수 있다.  
일반 `UWidget`(UButton 등)은 반드시 어떤 `UUserWidget`의 WidgetTree 안에 들어가야 화면에 나온다.

---

## UPanelWidget — 여러 자식을 담는 컨테이너

자식을 동적으로 추가·제거할 수 있다.

```cpp
class UPanelWidget : public UWidget
{
    // 자식 목록
    TArray<TObjectPtr<UPanelSlot>> Slots;

    UPanelSlot* AddChild(UWidget* Content);
    bool RemoveChild(UWidget* Content);
    int32 GetChildrenCount() const;
    UWidget* GetChildAt(int32 Index) const;
};
```

각 Panel 타입은 자신만의 Slot 클래스를 갖는다.  
`UVerticalBox`는 `UVerticalBoxSlot`, `UCanvasPanel`은 `UCanvasPanelSlot` 등.  
Slot에 패딩, 크기, 정렬 같은 배치 파라미터를 저장한다.

---

## UContentWidget — 자식 1개를 감싸는 위젯

```cpp
class UContentWidget : public UPanelWidget
{
    // 자식 1개만 허용
    UPanelSlot* SetContent(UWidget* Content);
    UWidget* GetContent() const;
};
```

`UButton`에 텍스트를 넣는 패턴:

```cpp
UButton* Button = WidgetTree->ConstructWidget<UButton>();
UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>();
Button->SetContent(Label);                      // UContentWidget::SetContent
```

---

## Slate 대응 관계

각 UMG 위젯은 대응하는 Slate 위젯이 있다.  
`RebuildWidget()`에서 생성하고 `TakeWidget()`이 반환한다.

| UMG (UWidget) | Slate (SWidget) |
|---------------|-----------------|
| UUserWidget | SObjectWidget > (내부 트리) |
| UVerticalBox | SVerticalBox |
| UHorizontalBox | SHorizontalBox |
| UButton | SButton |
| UBorder | SBorder |
| UTextBlock | STextBlock |
| UImage | SImage |
| UCanvasPanel | SConstraintCanvas |

---

## 내 노트

