# Slate 레이아웃 시스템

> 출처:  
> `Engine/Source/Runtime/SlateCore/Public/Layout/Geometry.h`  
> `Engine/Source/Runtime/SlateCore/Public/Layout/ArrangedWidget.h`  
> `Engine/Source/Runtime/SlateCore/Private/Widgets/SWidget.cpp`

Slate의 레이아웃은 두 단계 패스(Prepass → Paint)로 동작한다.  
이 문서는 두 패스에서 핵심 개념인 **DesiredSize**와 **AllottedGeometry**가 어떻게 흐르는지 설명한다.

---

## 핵심 개념 두 가지

### DesiredSize — 위젯이 원하는 크기

위젯이 `ComputeDesiredSize()`에서 반환하는 값.  
"나를 제대로 표시하려면 최소 이만큼의 공간이 필요하다"는 의향이다.

부모가 이 크기를 반드시 줘야 하는 건 아니다.  
부모가 자식보다 작으면 클리핑된다.

### AllottedGeometry — 부모가 실제로 할당한 공간

부모가 `OnArrangeChildren()` 또는 Paint 과정에서 자식에게 넘겨주는 값.  
위치(LocalPosition), 크기(LocalSize), 스케일 정보를 포함한다.

```cpp
struct FGeometry
{
    FVector2D  AbsolutePosition;   // 스크린 절대 좌표
    FVector2D  LocalSize;          // 이 위젯에 할당된 크기 (부모 기준)
    float      AccumulatedRenderTransformWithRHIRoundingBias; // 스케일 포함 변환
    // ...
};
```

위젯이 받은 AllottedGeometry 안에서만 그릴 수 있다.  
더 크게 그리면 클리핑되거나 다른 위젯과 겹친다.

---

## Prepass — 바텀업 크기 계산

`DrawPrepass()` → `SlatePrepass()` → `ComputeDesiredSize()` 재귀 호출.

```
[리프] STextBlock::ComputeDesiredSize()
          "Hello World" 텍스트 크기 측정 → (88, 16) 반환
              ↑
[중간] SVerticalBox::ComputeDesiredSize()
          자식 1: (88, 16)
          자식 2: (120, 16)
          패딩 포함 합산 → (120, 40) 반환
              ↑
[루트] SBorder::ComputeDesiredSize()
          자식 크기 (120, 40) + 자신의 패딩 → (128, 48) 반환
```

**바텀업인 이유**: 부모가 자신의 DesiredSize를 계산하려면 자식의 DesiredSize를 먼저 알아야 한다.

결과는 `CachedDesiredSize`에 저장된다.  
Prepass가 끝난 뒤 Paint 단계에서 이 캐시값을 참조한다.

---

## Paint 단계 — 탑다운 공간 분배

루트에서 시작해 자식으로 내려가며 `AllottedGeometry`를 나눠준다.

```
[루트] AllottedGeometry = 화면 전체 (1920, 1080)
          │ OnArrangeChildren() — 자식들의 위치·크기 계산
          ▼
[SVerticalBox] AllottedGeometry = (800, 600) at (560, 240)
          │ 자식 1에게 위쪽 절반 할당
          │ 자식 2에게 아래쪽 절반 할당
          ▼
[STextBlock] AllottedGeometry = (800, 300) at (0, 0)   ← 부모 로컬 좌표
          OnPaint() — 이 공간 안에 텍스트 드로우
```

탑다운인 이유: 부모가 전체 공간을 받아야 자식에게 얼마를 줄지 결정할 수 있다.

---

## FArrangedWidget — 자식 배치 결과

`SPanel::OnArrangeChildren()` 구현 시 `FArrangedChildren`에 결과를 담는다.

```cpp
void SVerticalBox::OnArrangeChildren(
    const FGeometry& AllottedGeometry,
    FArrangedChildren& ArrangedChildren) const
{
    float CurrentY = 0.f;
    for (const FSlot& Slot : Children)
    {
        FVector2D ChildSize = Slot.GetWidget()->GetDesiredSize();

        // 자식의 위치와 크기를 ArrangedChildren에 추가
        ArrangedChildren.AddWidget(
            AllottedGeometry.MakeChild(Slot.GetWidget(), FVector2D(0, CurrentY), ChildSize)
        );

        CurrentY += ChildSize.Y + Slot.SlotPadding.Get().Bottom + Slot.SlotPadding.Get().Top;
    }
}
```

이렇게 계산된 각 자식의 `FGeometry`가 다음 `OnPaint()` 호출 시 AllottedGeometry로 전달된다.

---

## 두 단계 흐름 전체 그림

```
[Prepass — 바텀업]
리프 위젯
  ComputeDesiredSize() → CachedDesiredSize 저장
      ↑
중간 위젯
  ComputeDesiredSize() → 자식 CachedDesiredSize 읽어 합산 → 저장
      ↑
루트
  ComputeDesiredSize() → 저장

[Paint — 탑다운]
루트 (AllottedGeometry = 화면)
  OnArrangeChildren() → 자식별 FGeometry 계산
      ↓
중간 위젯 (AllottedGeometry = 부모가 준 공간)
  OnArrangeChildren() → 손자별 FGeometry 계산
      ↓
리프 위젯 (AllottedGeometry = 최종 할당 공간)
  OnPaint() → FSlateDrawElement 발행
```

---

## 클리핑

위젯이 AllottedGeometry 바깥에 드로우 명령을 보내도 GPU로 가지 않는다.  
`SWidget::Paint()`가 호출 전에 `CalculateCullingAndClippingRules()`로 클리핑 영역을 설정한다.

`SetClipping(EWidgetClipping::ClipToBounds)`를 켜면 이 위젯의 경계 밖을 그리는 자식은 잘린다.

---

## 내 노트

