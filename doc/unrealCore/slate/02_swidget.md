# SWidget 클래스 계층

> 출처:  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SWidget.h`  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SCompoundWidget.h`  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SPanel.h`  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SLeafWidget.h`

모든 Slate 위젯은 `SWidget`을 상속한다.  
`SWidget`을 직접 상속하지 않고, 세 가지 중간 기반 클래스 중 하나를 통해 상속한다.

---

## 세 가지 기반 클래스

```
SWidget
  ├── SLeafWidget        자식 없음
  ├── SCompoundWidget    자식 정확히 1개
  └── SPanel             자식 여러 개 (슬롯 배열)
```

### SLeafWidget — 자식을 가질 수 없는 위젯

텍스트, 이미지처럼 스스로 콘텐츠를 렌더링하는 최말단 위젯.

```
SLeafWidget
  ├── STextBlock       텍스트 렌더링
  ├── SImage           이미지/브러시 렌더링
  ├── SSpinBox         숫자 입력 스피너
  └── SProgressBar     진행률 바
```

`OnArrangeChildren()`을 구현하지 않는다 — 자식이 없으므로 배치할 것이 없다.

### SCompoundWidget — 자식 1개를 감싸는 위젯

단일 자식을 감싸 추가 시각 효과나 동작을 부여하는 컨테이너.

```
SCompoundWidget
  ├── SButton          클릭 인터랙션 추가
  ├── SBorder          배경·패딩·테두리 추가
  ├── SScrollBox       스크롤 기능 추가
  └── SOverlay         Z축 레이어링 (자식 여럿이지만 구현은 SPanel 쪽)
```

내부에 `ChildSlot`이라는 단일 슬롯을 갖는다.

```cpp
// SButton 사용 예
SNew(SButton)
[
    SNew(STextBlock).Text(FText::FromString("Click"))  // ← ChildSlot에 들어감
]
```

### SPanel — 자식 여러 개를 배치하는 위젯

자식들을 특정 방식(가로, 세로, 절대좌표 등)으로 배치하는 레이아웃 위젯.

```
SPanel
  ├── SHorizontalBox   가로 배치 (HBox)
  ├── SVerticalBox     세로 배치 (VBox)
  ├── SGridPanel       격자 배치
  ├── SCanvas          절대좌표 자유 배치
  └── SOverlay         겹쳐 쌓기 (Z 순서)
```

슬롯(Slot) 배열로 자식을 관리하며, 각 슬롯에 배치 파라미터(크기, 패딩, 정렬)를 저장한다.

---

## SWidget의 핵심 가상 함수

레이아웃과 렌더링을 담당하는 세 함수를 이해하면 전체 파이프라인이 보인다.

### ComputeDesiredSize()

```cpp
// SWidget.h
virtual FVector2D ComputeDesiredSize(float LayoutScaleMultiplier) const = 0;
```

**Prepass** 단계에서 호출된다.  
"내가 필요한 최소 크기가 얼마야?"를 반환한다.  
바텀업으로 순회하므로 자식의 DesiredSize를 이미 알고 있는 상태에서 호출된다.

```
리프 위젯: 텍스트 길이·폰트 크기 기반으로 계산 → (120, 20) 반환
    ↑
패널:     자식들의 DesiredSize 합산 → (120, 60) 반환
    ↑
루트:     전체 DesiredSize 확정
```

### OnArrangeChildren()

```cpp
// SPanel에서 오버라이드
virtual void OnArrangeChildren(
    const FGeometry& AllottedGeometry,
    FArrangedChildren& ArrangedChildren) const;
```

부모가 "너 이 공간 써"(AllottedGeometry)라고 줬을 때, 각 자식에게 실제 위치와 크기를 할당한다.  
`SLeafWidget`과 `SCompoundWidget`은 구현하지 않는다.

### OnPaint()

```cpp
virtual int32 OnPaint(
    const FPaintArgs& Args,
    const FGeometry& AllottedGeometry,
    const FSlateRect& MyCullingRect,
    FSlateWindowElementList& OutDrawElements,
    int32 LayerId,
    const FWidgetStyle& InWidgetStyle,
    bool bParentEnabled) const = 0;
```

**Paint** 단계에서 호출된다.  
`OutDrawElements`에 드로우 명령을 추가한다 (`FSlateDrawElement::MakeBox()`, `MakeText()` 등).  
반환값은 다음 위젯이 쓸 LayerId (Z 순서).

---

## 상속 예시 — STextBlock

```
SWidget
  └── SLeafWidget
        └── STextBlock
```

```cpp
class STextBlock : public SLeafWidget
{
public:
    // 텍스트 크기 계산
    virtual FVector2D ComputeDesiredSize(float) const override;

    // 텍스트 드로우 명령 발행
    virtual int32 OnPaint(const FPaintArgs&, const FGeometry&, ...) const override;

    // OnArrangeChildren — SLeafWidget이므로 구현 없음
};
```

---

## 상속 예시 — SVerticalBox

```
SWidget
  └── SPanel
        └── SVerticalBox
```

```cpp
class SVerticalBox : public SPanel
{
public:
    // 자식들의 DesiredSize를 세로로 합산
    virtual FVector2D ComputeDesiredSize(float) const override;

    // 자식들의 위치를 세로로 쌓아 배치
    virtual void OnArrangeChildren(const FGeometry&, FArrangedChildren&) const override;

    // OnPaint — SPanel 기본 구현이 자식들을 재귀 순회
};
```

---

## 내 노트

