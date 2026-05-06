# AddToViewport / RemoveFromParent 내부 흐름

> 출처:  
> `Engine/Source/Runtime/UMG/Private/UserWidget.cpp` (line 1355, 1179, 1208)  
> `Engine/Source/Runtime/UMG/Private/Components/Widget.cpp` (line 909, 999)  
> `Engine/Source/Runtime/UMG/Private/Blueprint/GameViewportSubsystem.cpp` (line 130, 210)  
> `Engine/Source/Runtime/UMG/Private/Slate/SObjectWidget.cpp` (line 55)

---

## AddToViewport() — 전체 호출 체인

```
UUserWidget::AddToViewport(ZOrder)                            UserWidget.cpp:1355
  │
  └─ UGameViewportSubsystem::AddWidget(this, ViewportSlot)   GameViewportSubsystem.cpp:130
       │
       ├─ SConstraintCanvas 생성 (ZOrder 슬롯 포함)
       │
       ├─ RawSlot->AttachWidget( Widget->TakeWidget() )       GameViewportSubsystem.cpp:180
       │        │
       │        └─ UWidget::TakeWidget_Private()              Widget.cpp:999
       │                 │
       │                 ├─ [MyWidget 없으면] RebuildWidget()  ← 최초 1회만
       │                 │       └─ UUserWidget::RebuildWidget()  UserWidget.cpp:1179
       │                 │               └─ WidgetTree->RootWidget->TakeWidget()
       │                 │                       └─ (자식 UWidget들 TakeWidget() 재귀)
       │                 │                               → Slate 위젯 트리 전체 구성
       │                 │
       │                 ├─ SObjectWidget 생성               ← UUserWidget이므로
       │                 │       SNew(SObjectWidget, this)[SlateRootWidget]
       │                 │       MyGCWidget = SObjectWidget  ← GC 보호 시작
       │                 │
       │                 ├─ SynchronizeProperties()           ← UMG 프로퍼티 → Slate 동기화
       │                 │
       │                 └─ OnWidgetRebuilt()                 UserWidget.cpp:1208
       │                         ├─ NativePreConstruct()  →  PreConstruct() [BP]
       │                         └─ NativeConstruct()     →  Construct()    [BP]
       │
       └─ ViewportClient->AddViewportWidgetContent(
              FullScreenCanvas, ZOrder + 10)                  ← Slate 트리에 삽입
                                                              ← 다음 프레임부터 렌더링
```

> **참고**  
> `TakeWidget()`은 이미 `MyWidget`이 유효하면 캐시된 Slate 위젯을 그대로 반환한다.  
> `RebuildWidget()`(→ Slate 트리 구성)은 최초 호출 시에만 실행된다.  
> `SObjectWidget` 역시 이미 존재하면 재사용한다. NativeConstruct는 매번 호출된다.

---

## 핵심 포인트 — NativeConstruct가 불리는 시점

`NativeConstruct()`는 `AddToViewport()` 내부에서 불린다.  
정확히는 `TakeWidget()` → `OnWidgetRebuilt()` 안에서 호출된다.

```
AddToViewport()
  └─ GameViewportSubsystem::AddWidget()
       └─ RawSlot->AttachWidget( Widget->TakeWidget() )
                                         ↑
                              여기서 NativeConstruct 호출
```

즉 Slate 트리에 **삽입되기 직전**에 `NativeConstruct()`가 실행되고,  
그 이후 `AddViewportWidgetContent()`로 실제 Slate 트리에 붙는다.

---

## RemoveFromParent() — 전체 호출 체인

```
UWidget::RemoveFromParent()                                   Widget.cpp:909
  │
  └─ [bIsManagedByGameViewportSubsystem == true]
       UGameViewportSubsystem::RemoveWidget(this)             GameViewportSubsystem.cpp:197
         │
         ├─ ViewportWidgets 맵에서 SlotInfo 꺼냄 (맵 제거)
         │
         └─ RemoveWidgetInternal()                            GameViewportSubsystem.cpp:210
               │
               └─ ViewportClient->RemoveViewportWidgetContent(FullScreenCanvas)
                       └─ ViewportClient가 가진 TSharedRef 해제
                               │
                               ▼
              [SlotInfo 로컬 변수 소멸 → FullScreenCanvas TSharedPtr 해제]
                               │
                               ▼
              FullScreenCanvas(SConstraintCanvas) 참조 카운트 0
                               │
                               ▼
              SConstraintCanvas 소멸 → 내부 슬롯의 SObjectWidget TSharedRef 해제
                               │
                               ▼
              SObjectWidget 참조 카운트 0 → ~SObjectWidget()
                               │
                               └─ ResetWidget()               SObjectWidget.cpp:55
                                     ├─ UnregisterGCObject()  ← GC 보호 해제
                                     ├─ NativeDestruct()  →  Destruct() [BP]
                                     ├─ ReleaseSlateResources(true)
                                     │     └─ 자식 Slate 위젯들 순차 해제
                                     └─ WidgetObject = nullptr
```

> **참고**  
> `NativeDestruct()`는 `SObjectWidget`이 소멸할 때 호출된다.  
> `RemoveFromParent()`를 호출한 즉시 불리는 게 아니라,  
> Slate 참조 카운트가 0이 돼 `SObjectWidget`이 실제로 소멸하는 시점에 불린다.  
> 이 두 시점은 같은 콜스택 안에서 연속으로 일어나므로 실질적으로는 동시다.

---

## NativeDestruct가 불리는 시점

```
RemoveFromParent()
  └─ GameViewportSubsystem::RemoveWidget()
       └─ RemoveWidgetInternal()
            └─ ViewportClient 참조 해제
                 └─ (참조 카운트 연쇄 감소)
                      └─ SObjectWidget::ResetWidget()
                           └─ NativeDestruct()   ← 여기
```

`NativeDestruct()`가 호출되는 시점에는 이미 Slate 트리에서 빠진 상태다.

---

## UUserWidget 객체는 언제 GC되는가

`RemoveFromParent()` 이후에도 **UUserWidget UObject 자체는 즉시 사라지지 않는다.**

```
RemoveFromParent()
  └─ SObjectWidget::ResetWidget()
       └─ WidgetObject = nullptr   ← SObjectWidget의 강한 참조 해제

하지만 C++ 코드에서 UPROPERTY로 들고 있으면:

UPROPERTY()
UMyWidget* HUDWidget;              ← 이 참조가 남아있는 한 GC 안 됨

HUDWidget = nullptr;               ← 이 시점 이후 다음 GC에서 수거
```

`SObjectWidget`의 보호가 풀렸다고 바로 GC되는 게 아니다.  
다른 곳에서 UPROPERTY 참조가 남아있으면 계속 살아있다.

---

## 재사용 패턴 — Add → Remove → Add

같은 위젯 인스턴스를 반복 사용하면 어떻게 되는가:

```
[1회] AddToViewport()
         TakeWidget() → RebuildWidget() → Slate 트리 새로 구성 (최초)
         OnWidgetRebuilt() → NativePreConstruct + NativeConstruct 호출

[1회] RemoveFromParent()
         SObjectWidget 소멸 → NativeDestruct 호출
         MyWidget(TWeakPtr)은 아직 SWidget 살아있으면 유효

[2회] AddToViewport()
         TakeWidget() → MyWidget 유효하면 RebuildWidget() 스킵
         SObjectWidget은 이미 소멸했으므로 새로 생성
         OnWidgetRebuilt() → NativePreConstruct + NativeConstruct 다시 호출
```

**결론**: `Add → Remove → Add`를 반복하면 `NativeConstruct / NativeDestruct`가 매번 쌍으로 호출된다.  
1회만 실행돼야 하는 초기화는 `NativeOnInitialized()`에서 해야 한다.

---

## 전체 정리

| 단계 | 호출 함수 | 시점 |
|------|-----------|------|
| `AddToViewport()` | `NativePreConstruct` | Slate 삽입 직전 (TakeWidget 안) |
| `AddToViewport()` | `NativeConstruct` | Slate 삽입 직전 (TakeWidget 안) |
| `RemoveFromParent()` | `NativeDestruct` | SObjectWidget 소멸 시 (참조 카운트 0) |
| 다음 GC | UUserWidget 수거 | UPROPERTY 참조가 모두 해제된 이후 |

---

## 내 노트

