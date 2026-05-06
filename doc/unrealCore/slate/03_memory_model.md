# Slate 메모리 모델

> 출처:  
> `Engine/Source/Runtime/Core/Public/Templates/SharedPointer.h`  
> `Engine/Source/Runtime/UMG/Private/Components/Widget.cpp`  
> `Engine/Source/Runtime/UMG/Public/Components/Widget.h`

Slate는 UObject 기반이 아니므로 언리얼 GC가 관리하지 않는다.  
대신 **TSharedRef / TSharedPtr** (참조 카운팅)로 수명을 관리한다.

---

## TSharedPtr vs TSharedRef

언리얼의 TSharedPtr / TSharedRef는 C++ 표준 `std::shared_ptr`과 개념이 같지만 별도 구현이다.

| 타입 | nullable | 의미 |
|------|:--------:|------|
| `TSharedPtr<T>` | O | 없을 수도 있는 소유 포인터. `IsValid()` 확인 필요 |
| `TSharedRef<T>` | X | 반드시 유효한 소유 포인터. null 불가 |
| `TWeakPtr<T>` | O | 소유권 없음. 대상이 사라져도 크래시 없이 `Pin()` 실패 |

SWidget은 항상 `TSharedRef<SWidget>`으로 전달된다.

```cpp
TSharedRef<SButton> MyButton = SNew(SButton);        // TSharedRef — null 불가
TSharedPtr<STextBlock> OptionalText;                 // TSharedPtr — null 가능
TWeakPtr<SWidget> WeakRef = MyButton;               // 소유권 없이 참조
```

참조 카운트가 0이 되면 즉시 소멸한다.  
언리얼 GC 사이클을 기다리지 않는다.

---

## UObject GC와의 차이

```
[UObject 세계]                      [Slate 세계]
  UPROPERTY로 참조 등록               TSharedRef로 소유
  GC 마크 단계에서 도달 가능 여부 확인  참조 카운트 0 → 즉시 소멸
  다음 GC 사이클에서 수거              별도 사이클 없음
  IsValid() / IsValidLowLevel()       IsValid() / Pin()
```

두 세계는 서로를 모른다.  
Slate가 `UUserWidget*`을 들고 있다고 해서 GC가 그 UObject를 살려두지 않는다.  
반대로 UObject가 `TSharedPtr<SWidget>`을 들고 있으면 SWidget이 UObject 수거를 막지 않는다.

---

## SObjectWidget — GC 브릿지

이 단절 문제를 해결하는 것이 `SObjectWidget`이다.

```cpp
// Widget.cpp (TakeWidget_Private 내부)
if (IsA(UUserWidget::StaticClass()))
{
    // SObjectWidget이 UUserWidget을 AddToRoot에 준하는 강한 참조로 붙잡음
    SafeGCWidget = SNew(SObjectWidget, this)[PublicWidget];
    MyGCWidget   = SafeGCWidget;
}
```

`SObjectWidget`은 `UUserWidget*`을 멤버로 갖고,  
자신이 살아있는 동안 GC가 그 UUserWidget을 수거하지 못하도록 막는다.

```
Slate 위젯 트리
  └── SObjectWidget  ─────────────── UUserWidget (GC로부터 보호)
        └── 실제 SWidget 트리           │
                                       └── WidgetTree (자식 UWidget들)
```

`SObjectWidget`이 소멸하면 (Slate 트리에서 제거되면) 보호가 풀리고,  
다음 GC 사이클에서 UUserWidget도 수거될 수 있다.

---

## 언제 수명 문제가 생기는가

### 케이스 1 — Slate 콜백이 UObject를 캡처

```cpp
// 위험: SButton 람다가 UObject*를 캡처
SNew(SButton).OnClicked_Lambda([MyActor]()
{
    MyActor->DoSomething();  // MyActor가 GC됐으면 크래시
    return FReply::Handled();
});
```

해결: `TWeakObjectPtr`로 캡처 후 `IsValid()` 확인.

```cpp
TWeakObjectPtr<AMyActor> WeakActor = MyActor;
SNew(SButton).OnClicked_Lambda([WeakActor]()
{
    if (WeakActor.IsValid())
        WeakActor->DoSomething();
    return FReply::Handled();
});
```

### 케이스 2 — UObject가 SWidget을 TSharedPtr로 보관

```cpp
class UMyWidget : public UUserWidget
{
    TSharedPtr<SMySlate> CachedSlate;  // UObject가 Slate를 붙잡음
};
```

이 경우는 안전하다.  
UObject가 살아있는 동안 SWidget 참조 카운트가 유지되고,  
UObject가 GC되면 TSharedPtr도 소멸해 SWidget 카운트가 줄어든다.

---

## 정리

```
TSharedRef   → 반드시 유효, Slate 위젯 소유의 기본
TSharedPtr   → 선택적 소유, 없을 수 있음
TWeakPtr     → 소유 없이 참조, Slate 콜백에서 SWidget 참조 시
TWeakObjectPtr → UObject를 소유 없이 참조, Slate 람다에서 UObject 참조 시
SObjectWidget → Slate 트리가 살아있는 동안 UUserWidget을 GC로부터 보호
```

---

## 내 노트

