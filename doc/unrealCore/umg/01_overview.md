# UMG 개요

> 출처:  
> `Engine/Source/Runtime/UMG/Public/Blueprint/UserWidget.h`  
> `Engine/Source/Runtime/UMG/Public/Components/Widget.h`

UMG(Unreal Motion Graphics)는 Slate 위에 올린 **UObject 기반 UI 시스템**이다.  
게임 코드와 블루프린트에서 직접 다루는 UI의 실체가 UMG다.

---

## Slate와의 역할 분담

Slate는 실제 렌더링을 담당하지만 UObject가 아니라 블루프린트에서 직접 쓸 수 없다.  
UMG는 그 Slate 위젯을 UObject로 감싸 게임 코드·블루프린트에서 쓸 수 있게 한다.

```
[블루프린트 / C++ 게임 코드]
        │
        │ CreateWidget<UMyWidget>()
        ▼
    UMG 레이어
      UUserWidget (UObject)          ← 개발자가 직접 만드는 UI 클래스
        └── WidgetTree               ← 자식 UWidget들의 트리
              ├── UVerticalBox
              ├── UTextBlock
              └── UButton
        │ AddToViewport() → TakeWidget() 호출
        ▼
    Slate 레이어
      SObjectWidget                  ← UUserWidget GC 보호
        └── SVerticalBox
              ├── STextBlock
              └── SButton
        │
        ▼
    RHI / GPU
```

UMG가 추가로 제공하는 것:

| 기능 | 설명 |
|------|------|
| 블루프린트 노출 | UFUNCTION, UPROPERTY, Blueprint Implementable Event |
| GC 통합 | UPROPERTY로 자식 위젯 소유, 언리얼 GC가 수명 관리 |
| 에디터 디자이너 | WBP(Widget Blueprint) 에디터에서 드래그 앤 드롭 UI 설계 |
| 애니메이션 | UWidgetAnimation — 위젯 속성의 키프레임 애니메이션 |
| 데이터 바인딩 | Property Binding — 함수 반환값을 위젯 속성에 연결 |

---

## 언제 UMG를 쓰고 언제 Slate를 직접 쓰는가

| 상황 | 선택 |
|------|------|
| 인게임 HUD, 인벤토리, 메뉴 등 일반 게임 UI | UMG |
| 블루프린트 디자이너가 작업하는 UI | UMG |
| 언리얼 에디터 플러그인 · 커스텀 툴 창 | Slate 직접 |
| 엔진 초기화 중 로딩 화면, 스플래시 | Slate 직접 |
| 초고성능 HUD (UObject 오버헤드 제거) | Slate 직접 |

대부분의 경우 UMG를 쓰면 된다.  
Slate를 직접 써야 하는 이유가 명확할 때만 Slate로 내려간다.

---

## 내 노트

