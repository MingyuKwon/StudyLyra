# 언리얼 엔진 UI 파이프라인 — Slate / UMG

> 출처:  
> `C:/UE_5.7/Engine/Source/Runtime/Launch/Private/LaunchEngineLoop.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/SlateCore/Private/Widgets/SWidget.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/UMG/Private/UserWidget.cpp`  
> `C:/UE_5.7/Engine/Source/Runtime/UMG/Private/Components/Widget.cpp`

---

## 계층 구조 한 눈에 보기

```
[블루프린트 / 게임 코드]
        │ CreateWidget<UMyWidget>()
        ▼
    UMG (UWidget / UUserWidget)          ← UObject 기반, Blueprint 노출
        │ TakeWidget() — 첫 접근 시 SWidget 생성 후 캐시
        ▼
    Slate (SWidget 파생 클래스)          ← 순수 C++, TSharedRef 기반
        │ OnPaint() — 드로우 엘리먼트 발행
        ▼
    FSlateWindowElementList              ← 한 프레임 드로우 명령 버퍼
        │ Renderer->DrawWindows()
        ▼
    RHI / GPU                            ← 실제 픽셀 출력
```

> **📌 내 노트**  
>

---

## 1. 엔진 루프에서 Slate 틱이 불리는 경로

```cpp
// LaunchEngineLoop.cpp:5890
FEngineLoop::Tick()
    │
    ├─ FSlateApplication::Get().Tick(ESlateTickType::PlatformAndInput)  ← 입력 처리
    │
    └─ FSlateApplication::Get().Tick(ESlateTickType::TimeAndWidgets)    ← 위젯 렌더
```

`ESlateTickType`으로 단계를 분리하는 이유:  
영상 재생 같은 슬레이트 전용 스레드가 `PlatformAndInput` 없이 `Widgets`만 틱할 수 있게 하기 위함.

> **📌 내 노트**  
>

---

## 2. FSlateApplication::Tick 내부 흐름

```
FSlateApplication::Tick(ESlateTickType)        ← SlateApplication.cpp:1591
    │
    ├─ TickPlatform(DeltaTime)                 ← OS 메시지 펌프 (modal 상태일 때)
    │       PlatformApplication->Tick()
    │
    ├─ TickTime()                              ← 현재 시간 갱신
    │
    └─ TickAndDrawWidgets(DeltaTime)           ← :1716 — 레이아웃 + 페인트
            │
            ├─ PreTickEvent.Broadcast()        ← 훅 (애니메이션 등)
            ├─ 유휴 판정 (사용자 입력 없음 + ActiveTimer 없음 → 스킵)
            └─ DrawWindows()                   ← :1182 → PrivateDrawWindows()
```

**슬레이트 절전 (Sleep)**: 사용자 입력이 없고 등록된 ActiveTimer도 없으면 `DrawWindows()`를 건너뛴다.  
애니메이션이 재생 중인 위젯은 반드시 `RegisterActiveTimer()`를 사용해야 매 틱 화면이 갱신된다.

> **📌 내 노트**  
>

---

## 3. DrawWindows — 두 단계 Pass

```
PrivateDrawWindows()                           ← :1411
    │
    ├─ [Pass 1] DrawPrepass()                  ← 레이아웃 계산 (크기)
    │       PrepassWindowAndChildren()
    │           SWindow::SlatePrepass()
    │               → SWidget::SlatePrepass()  ← 재귀적으로 모든 자식 순회
    │                   → Prepass_Internal()
    │                       → CacheDesiredSize()
    │                           → ComputeDesiredSize()  ← virtual, 각 위젯이 구현
    │
    └─ [Pass 2] DrawWindowAndChildren()        ← 실제 페인트
            for each SWindow in SlateWindows:
                DrawWindowAndChildren(Window)
                    SWindow::PaintWindow()
                        → SWidget::Paint()     ← 재귀적으로 모든 자식 순회
                            → Tick() (NeedsTick 플래그 있는 위젯만)
                            → OnPaint()        ← virtual, 각 위젯이 구현
                                드로우 엘리먼트 → FSlateWindowElementList에 추가
                    DrawWindowAndChildren(ChildWindow)  ← 자식 창 재귀
    │
    └─ Renderer->DrawWindows(DrawBuffer)       ← GPU 제출
```

### Pass 1: Prepass — 왜 먼저 하는가?

레이아웃은 **바텀업(Bottom-up)**으로 계산된다.  
자식의 DesiredSize를 알아야 부모가 자신의 크기를 결정할 수 있으므로, 페인트 전에 선행 순회가 필요하다.

```
[리프 위젯] ComputeDesiredSize() → (42, 20)
    ↑
[패널 위젯] 자식 크기 합산 → 자신의 DesiredSize 결정
    ↑
[루트 위젯] 전체 크기 확정
```

### Pass 2: Paint — OnPaint의 역할

`SWidget::Paint()`가 호출하는 순서:

```cpp
// SWidget.cpp:1407
SWidget::Paint(Args, AllottedGeometry, CullingRect, OutDrawElements, LayerId, ...)
    1. 클리핑 영역 계산 (CalculateCullingAndClippingRules)
    2. Tick() — NeedsTick 플래그 있을 때만
    3. OnPaint() → 각 위젯 고유 드로우 명령 발행
```

`AllottedGeometry`: 부모가 이 위젯에 **할당한** 실제 위치·크기.  
`OutDrawElements`: 이 프레임의 드로우 명령 버퍼. `FSlateDrawElement::MakeBox()` 등으로 추가.

> **📌 내 노트**  
>

---

## 4. UMG ↔ Slate 브릿지 — TakeWidget()

`UWidget`(UObject)과 `SWidget`(TSharedRef)은 별개의 세계다.  
`TakeWidget()`이 그 경계를 이어준다.

```cpp
// Widget.cpp:999
UWidget::TakeWidget_Private()
{
    if (!MyWidget.IsValid())          // 처음 호출 시
    {
        PublicWidget = RebuildWidget(); // ← virtual, 각 UWidget 서브클래스가 SWidget 생성
        MyWidget = PublicWidget;        // 약한 참조로 캐시
    }

    if (IsA(UUserWidget::StaticClass()))
    {
        // UUserWidget은 SObjectWidget으로 한 번 더 감쌈 — GC 방지용
        SafeGCWidget = SNew(SObjectWidget, this)[PublicWidget];
        MyGCWidget = SafeGCWidget;
    }
}
```

**SObjectWidget의 역할**: Slate는 TSharedRef로 메모리를 관리하고 UObject GC를 모른다.  
`SObjectWidget`이 `UUserWidget`을 GC 루트에 묶어 Slate 위젯 트리에 살아있는 동안 UObject가 수거되지 않게 한다.

### UUserWidget::RebuildWidget()

```cpp
// UserWidget.cpp:1179
TSharedRef<SWidget> UUserWidget::RebuildWidget()
{
    // WidgetTree에서 루트 UWidget을 가져와 TakeWidget() 재귀 호출
    TSharedRef<SWidget> UserRootWidget =
        WidgetTree->RootWidget
            ? WidgetTree->RootWidget->TakeWidget()
            : SNew(SSpacer);

    return UserRootWidget;
}
```

블루프린트로 만든 WBP의 모든 위젯 트리가 여기서 Slate 위젯 트리로 변환된다.

> **📌 내 노트**  
>

---

## 5. 뷰포트에 추가하는 경로

```cpp
// UserWidget.cpp:1355
UUserWidget::AddToViewport(int32 ZOrder)
    → UGameViewportSubsystem::AddWidget(this, ViewportSlot)
        → (내부) TakeWidget() 호출 → SWidget 생성
        → GameViewport의 Slate 위젯 트리에 삽입
```

`AddToPlayerScreen()`은 `AddToViewport()`와 달리 특정 `ULocalPlayer`에 귀속된다 — 스플릿스크린 대응.

> **📌 내 노트**  
>

---

## 6. 위젯 Tick이 동작하는 조건

Slate 위젯의 `Tick()`은 **매 프레임 무조건 불리지 않는다.**  
`Paint()` 안에서 `EWidgetUpdateFlags::NeedsTick` 플래그가 켜진 위젯만 호출된다.

```cpp
// SWidget.cpp:1439
if (HasAnyUpdateFlags(EWidgetUpdateFlags::NeedsTick))
{
    MutableThis->Tick(DesktopSpaceGeometry, Args.GetCurrentTime(), Args.GetDeltaTime());
}
```

UMG의 `UUserWidget`에서 `Tick` 이벤트를 쓰면 자동으로 이 플래그가 세팅된다.

> **📌 내 노트**  
>

---

## 7. 전체 흐름 요약

```
[게임 코드]
  CreateWidget<UMyWidget>(PC, UMyWidget::StaticClass())
      → UUserWidget 인스턴스 생성 (아직 Slate 없음)
  
  MyWidget->AddToViewport()
      → TakeWidget()
          → RebuildWidget() → SObjectWidget[ SMySlateWidget ]
          → GameViewport Slate 트리에 삽입
  
[매 프레임 — FEngineLoop::Tick]
  FSlateApplication::Tick(TimeAndWidgets)
      │
      ├─ TickAndDrawWidgets()
      │       DrawWindows()
      │           PrivateDrawWindows()
      │               ① DrawPrepass()
      │                   SWidget::SlatePrepass() — 바텀업 DesiredSize 계산
      │               ② DrawWindowAndChildren()
      │                   SWidget::Paint()
      │                       Tick() (필요 시)
      │                       OnPaint() → FSlateWindowElementList에 드로우 명령 추가
      │
      └─ Renderer->DrawWindows(DrawBuffer)
              → RHI → GPU → 픽셀 출력
```

> **📌 내 노트**  
>

---

## 핵심 개념 정리

| 개념 | 설명 |
|------|------|
| **Slate** | 언리얼의 저수준 UI 프레임워크. `SWidget` 기반, TSharedRef로 메모리 관리 |
| **UMG** | Slate 위에 올린 UObject 래퍼. 블루프린트 노출, GC 통합, 에디터 디자이너 제공 |
| **TakeWidget()** | UWidget → SWidget 변환. 캐시가 유효하면 기존 SWidget 반환 |
| **SObjectWidget** | UUserWidget을 GC로부터 보호하는 Slate 래퍼 |
| **Prepass** | 레이아웃 계산 패스. 바텀업으로 DesiredSize 확정 |
| **OnPaint** | 페인트 패스. FSlateWindowElementList에 드로우 명령 발행 |
| **ActiveTimer** | 유휴 상태에서도 슬레이트가 틱하도록 강제하는 등록 메커니즘 |
| **AllottedGeometry** | 부모가 자식에게 할당한 실제 위치·크기 |

---

## 내 노트

