# InputPreProcessor — 위젯 라우팅 이전 단계

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Public/Framework/Application/SlateApplication.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`

---

`FSlateApplication`의 `ProcessKeyDownEvent`는 위젯 라우팅(Tunnel/Bubble)을 시작하기 전에 **InputPreProcessor**를 먼저 실행한다.

```
ProcessKeyDownEvent()
    ├─ ① InputPreProcessors.HandleKeyDownEvent()   ← 여기
    │        true  반환 → 위젯 라우팅 전체 생략
    │        false 반환 → 아래로 계속
    │
    └─ ② Tunnel/Bubble 위젯 라우팅   (→ 03_slate_routing.md)
```

위젯 라우팅과 완전히 분리된 레이어다. 포커스 경로, FWidgetPath, Tunnel/Bubble — 이 개념들과 무관하게 **모든 입력을 무조건 먼저 본다.**

---

## IInputProcessor 인터페이스

```cpp
// SlateApplication.h
class IInputProcessor
{
public:
    virtual bool HandleKeyDownEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) = 0;
    virtual bool HandleKeyUpEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) = 0;
    virtual bool HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent) = 0;
    // ...
};

void RegisterInputPreProcessor(TSharedRef<IInputProcessor> InputProcessor, const int32 Index = INDEX_NONE);
```

`IInputProcessor`를 구현해서 `FSlateApplication`에 등록하면 된다.

- **`true` 반환**: 이벤트를 소비. 이후 위젯 라우팅 실행 안 됨.
- **`false` 반환**: 패스스루. 이후 위젯 라우팅 정상 진행.
- **여러 개 등록 가능**: `Index`로 실행 순서를 지정한다.

---

## Enhanced Input이 PreProcessor인 이유

`UEnhancedInputLocalPlayerSubsystem`이 `IInputProcessor`를 구현하고 스스로 등록한다.

위젯이 아닌 시스템이 PreProcessor를 쓰는 이유는 두 가지다.

**포커스와 무관하게 항상 실행되어야 한다.**

Tunnel/Bubble은 포커스 경로 위젯에만 이벤트가 전달된다. UI가 열려서 포커스가 `SViewport`를 벗어나도 Enhanced Input은 W키를 받아야 한다.

```
UI가 열려 있을 때:
  포커스 → SMyUIWidget (SViewport는 포커스 없음)

  ① PreProcessor → Enhanced Input 실행 (포커스 무관)   ← 항상 실행
  ② Bubble       → SMyUIWidget::OnKeyDown 호출          ← 포커스 기반
                   (SViewport::OnKeyDown은 호출 안 됨)
```

**결과물이 위젯이 아닌 게임 코드로 간다.**

W키 → `InputAction "Move"` 변환 → `UEnhancedInputComponent` 콜백 호출.  
이 흐름은 Slate 위젯과 무관하다. PreProcessor가 적절한 위치다.

**`false`를 반환해 위젯 라우팅도 계속 진행한다.**

Enhanced Input은 키를 처리한 뒤 `false`를 반환한다.  
같은 키가 Enhanced Input 변환과 Bubble 라우팅을 동시에 거친다.

---

## PreProcessor vs 위젯 라우팅 — 레이어 비교

| | InputPreProcessor | Tunnel/Bubble |
|---|---|---|
| **실행 조건** | 무조건 | 포커스 경로에만 |
| **목적** | 위젯 시스템 진입 여부 결정 | 어느 위젯이 처리할지 결정 |
| **레이어** | 애플리케이션 레벨 | 위젯 레벨 |
| **사용 예** | Enhanced Input, 커스텀 입력 필터 | UI 위젯, SViewport |
