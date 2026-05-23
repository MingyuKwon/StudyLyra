# InputPreProcessor — 위젯 라우팅 이전 단계

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Public/Framework/Application/SlateApplication.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`

---

`ProcessKeyDownEvent`는 위젯 라우팅(Tunnel/Bubble)보다 먼저 PreProcessor를 실행한다.  
반환값이 이후 흐름을 결정한다.

```
ProcessKeyDownEvent()
    ├─ InputPreProcessors.HandleKeyDownEvent()
    │        true  반환 → 여기서 종료. 위젯 라우팅 실행 안 됨
    │        false 반환 → 위젯 라우팅 정상 진행
    │
    └─ Tunnel/Bubble 위젯 라우팅   (→ 02_slate_routing.md)
```

**`false`가 기본값이다.** 대부분의 PreProcessor는 입력을 관찰하거나 변환만 하고 `false`를 반환한다. 위젯이 정상적으로 입력을 받는다.  
`true`는 의도적으로 입력을 차단할 때만 쓴다.

---

## IInputProcessor 인터페이스

```cpp
class IInputProcessor
{
public:
    virtual bool HandleKeyDownEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) = 0;
    virtual bool HandleKeyUpEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) = 0;
    virtual bool HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent) = 0;
    virtual void Tick(const float DeltaTime, FSlateApplication& SlateApp, TSharedRef<ICursor> Cursor) {}
};
```

---

## Enhanced Input은 false를 반환한다

`UEnhancedInputLocalPlayerSubsystem`이 `IInputProcessor`를 구현하고 스스로 등록한다.

Enhanced Input이 W키를 받으면:
1. W → `InputAction "Move"` 변환 → `UEnhancedInputComponent` 콜백 호출
2. **`false` 반환** — 위젯 라우팅 계속 진행

```
W키 누름
    → Enhanced Input PreProcessor
          W → "Move" 액션 변환, 콜백 실행
          return false
    → Bubble 위젯 라우팅
          SViewport → UGameViewportClient → PlayerInput 적재
```

두 경로가 동시에 일어난다. Enhanced Input을 써도 위젯은 정상적으로 입력을 받는다.

Enhanced Input이 PreProcessor인 이유는 포커스와 무관하게 실행되어야 하기 때문이다. Tunnel/Bubble은 포커스 경로 위젯에만 전달된다. UI가 열려 있을 때도 게임 입력이 처리되어야 하므로 위젯 라우팅 밖에 위치한다.

---

## 커스텀 PreProcessor 만들기

### 언제 쓰는가

- 컷신, 로딩 중 게임 입력 전체 차단 (`true` 반환)
- 특정 키만 허용하는 모달 상태
- 포커스 무관 글로벌 단축키 (어떤 UI가 열려 있어도 작동)
- 입력 리매핑, 로깅

### 구현

```cpp
class FMyInputPreProcessor : public IInputProcessor
{
public:
    virtual bool HandleKeyDownEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) override
    {
        if (InKeyEvent.GetKey() == EKeys::F1)
        {
            // 포커스 무관 글로벌 단축키 — UI가 열려 있어도 실행
            OpenDebugPanel();
            return false;  // 위젯도 이 키를 받게 한다
        }
        return false;
    }

    virtual bool HandleKeyUpEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) override
    {
        return false;
    }

    virtual bool HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent) override
    {
        return false;
    }
};
```

### 등록 / 해제

```cpp
// 등록 — TSharedPtr로 보관해야 나중에 해제 가능
TSharedPtr<FMyInputPreProcessor> MyProcessor = MakeShared<FMyInputPreProcessor>();
FSlateApplication::Get().RegisterInputPreProcessor(MyProcessor.ToSharedRef(), 0);
// Index: 낮을수록 먼저 실행. Enhanced Input보다 앞에 두려면 0.

// 해제
FSlateApplication::Get().UnregisterInputPreProcessor(MyProcessor);
```

등록한 객체를 멤버 변수로 보관해야 `UnregisterInputPreProcessor`에 전달할 수 있다.  
`GameInstance`, `LocalPlayerSubsystem` 등 적절한 수명을 가진 곳에서 관리한다.

### 컷신 입력 차단 예시

```cpp
class FCutsceneInputBlocker : public IInputProcessor
{
public:
    virtual bool HandleKeyDownEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) override
    {
        if (InKeyEvent.GetKey() == EKeys::Escape)
            return false;  // Escape만 통과 (컷신 스킵용)

        return true;  // 나머지 전부 차단 — 위젯 라우팅 안 됨
    }

    virtual bool HandleKeyUpEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) override
    {
        return InKeyEvent.GetKey() != EKeys::Escape;
    }

    virtual bool HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent) override
    {
        return true;  // 스틱/트리거도 차단
    }
};
```

---

## PreProcessor vs 위젯 라우팅

| | InputPreProcessor | Tunnel/Bubble |
|---|---|---|
| **실행 조건** | 무조건 (포커스 무관) | 포커스 경로 위젯에만 |
| **목적** | 위젯 시스템 진입 전 처리/차단 | 어느 위젯이 처리할지 결정 |
| **반환값** | true=차단, false=통과 | Handled()=중단, Unhandled()=전파 |
| **대표 사용처** | Enhanced Input, 커스텀 필터 | UI 위젯, SViewport |
