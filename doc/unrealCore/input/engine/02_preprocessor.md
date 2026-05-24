# InputPreProcessor — 위젯 라우팅 이전 단계

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Slate/Public/Framework/Application/SlateApplication.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Slate/Private/Framework/Application/SlateApplication.cpp`  
>        `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Private/EnhancedInputWorldProcessor.cpp`

---

## PreProcessor 개요

`ProcessKeyDownEvent`는 위젯 라우팅(Tunnel/Bubble)보다 먼저 PreProcessor를 실행한다.  
반환값이 이후 흐름을 결정한다.

```
ProcessKeyDownEvent()
    ├─ InputPreProcessors.HandleKeyDownEvent()
    │        true  반환 → 여기서 종료. 위젯 라우팅 실행 안 됨
    │        false 반환 → 위젯 라우팅 정상 진행
    │
    └─ Tunnel/Bubble 위젯 라우팅
```

**`false`가 기본값이다.** 대부분의 PreProcessor는 입력을 관찰하거나 변환만 하고 `false`를 반환한다.  
`true`는 의도적으로 입력을 차단할 때만 쓴다.

### IInputProcessor 인터페이스

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

## FEnhancedInputWorldProcessor

`FSlateApplication`에 등록된 Enhanced Input PreProcessor는 `FEnhancedInputWorldProcessor`다.  
`UEnhancedInputLocalPlayerSubsystem`이 아니다.

```cpp
bool FEnhancedInputWorldProcessor::HandleKeyDownEvent(...)
{
    InputKeyToSubsystem(Params);   // UEnhancedInputWorldSubsystem에만 전달
    return false;                  // 항상 false — 위젯 라우팅 계속
}
```

`return false`이므로 WorldSubsystem 전달과 LocalPlayer 경로가 **동시에** 실행된다.

```
[키 누름]
    → FEnhancedInputWorldProcessor::HandleKeyDownEvent()
          WorldSubsystem 전달, return false       ← 차단 아님, 계속 진행
    → 위젯 라우팅
          SViewport → UGameViewportClient → UEnhancedPlayerInput::InputKey() 적재
    (PlayerController Tick에서 LocalPlayer 콜백 발화)
```

LocalPlayer의 Enhanced Input 콜백은 이 PreProcessor에서 실행되지 않는다.  
PlayerController Tick의 `UEnhancedPlayerInput::EvaluateInputDelegates()`에서 실행된다.

LocalPlayer와 구조가 대칭이다.

| | LocalPlayer | Controller 없는 엔티티 |
|---|---|---|
| **입력 진입** | PlayerController Tick | FEnhancedInputWorldProcessor |
| **구독 대상** | UEnhancedInputLocalPlayerSubsystem | UEnhancedInputWorldSubsystem |

---

## UEnhancedInputWorldSubsystem — 용도와 한계

PlayerController 없는 엔티티는 `UEnhancedInputWorldSubsystem`에 바인딩해두면 입력을 받는다.

```cpp
UEnhancedInputWorldSubsystem* Sub = GetWorld()->GetSubsystem<UEnhancedInputWorldSubsystem>();
Sub->AddMappingContext(IMC, Priority);
Sub->BindAction(IA_Something, Triggered, this, &MyFunc);
```

### 한계 — 플레이어 구분 불가

`FEnhancedInputWorldProcessor`는 `UGameViewportClient` 분기 이전 단계라 **모든 플레이어의 입력을 다 받는다.**  
키 이벤트에서 "누가 눌렀는가"를 구분하지 않는다.

로컬 2인 플레이에서 플레이어별 분기는 `UGameViewportClient` 단계에서 일어난다.  
키 이벤트의 `ControllerId`를 보고 해당 LocalPlayer의 PlayerController에만 전달한다.

```
[키 이벤트 (ControllerId = 1)]
    ↓
UGameViewportClient::InputKey()
    GEngine->GetLocalPlayerFromControllerId(ControllerId = 1)
        → LocalPlayer[1]->PlayerController->InputKey()
            → LocalPlayer[1]의 UEnhancedPlayerInput::InputKey() 적재
```

`LocalPlayer[0]`의 `UEnhancedPlayerInput`에는 신호가 가지 않는다.  
WorldSubsystem은 이 분기 이전에 실행되므로 누가 눌렀는지 알 수 없다.

### 쓸 수 있는 곳

- **싱글플레이어**: 플레이어가 1명이라 구분 불필요. PlayerController 없는 월드 액터가 Enhanced Input 쓸 때
- **전역 이벤트**: 누가 눌러도 발동하는 일시정지, 스크린샷, 글로벌 디버그 토글
- **Dedicated Server**: 서버에는 LocalPlayer 자체가 없음
- **에디터 / 툴**: 플레이어 컨텍스트 없이 뷰포트 단축키 처리

로컬 멀티플레이어에서 "2번 플레이어가 눌렀을 때만 반응"같은 용도로는 쓸 수 없다.  
그런 경우에는 각 PlayerController의 Enhanced Input 경로를 써야 한다.

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
            OpenDebugPanel();
            return false;  // 위젯도 이 키를 받게 한다
        }
        return false;
    }

    virtual bool HandleKeyUpEvent(FSlateApplication& SlateApp, const FKeyEvent& InKeyEvent) override { return false; }
    virtual bool HandleAnalogInputEvent(FSlateApplication& SlateApp, const FAnalogInputEvent& InAnalogInputEvent) override { return false; }
};
```

### 등록 / 해제

```cpp
// 등록 — TSharedPtr로 보관해야 나중에 해제 가능
TSharedPtr<FMyInputPreProcessor> MyProcessor = MakeShared<FMyInputPreProcessor>();
FSlateApplication::Get().RegisterInputPreProcessor(MyProcessor.ToSharedRef(), 0);
// Index: 낮을수록 먼저 실행. 0이면 가장 먼저 실행.

// 해제
FSlateApplication::Get().UnregisterInputPreProcessor(MyProcessor);
```

등록한 객체를 멤버 변수로 보관해야 해제할 수 있다.  
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
        return true;       // 나머지 전부 차단
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
| **대표 사용처** | WorldSubsystem Enhanced Input, 커스텀 필터 | UI 위젯, SViewport |
