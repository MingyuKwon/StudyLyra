# 08. UCommonUIActionRouterBase

> 소스 경로  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Public/Input/CommonUIActionRouterBase.h`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/Input/CommonUIActionRouterBase.cpp`  
> - `Engine/Plugins/Runtime/CommonUI/Source/CommonUI/Private/Input/UIActionRouterTypes.h`

---

## 1. 한 줄 정의

헤더 주석 원문:

> **The nucleus of the CommonUI input routing system.**  
> Gathers input from external sources such as game viewport client and forwards them to widgets via activatable tree node representation.

CommonUI 입력 시스템의 **핵(核)**. 입력을 받아서 올바른 위젯에 전달하는 모든 과정을 총괄한다.

---

## 2. 정체

```cpp
UCLASS(MinimalAPI)
class UCommonUIActionRouterBase : public ULocalPlayerSubsystem
```

`ULocalPlayerSubsystem`이다. 즉 **플레이어 1명당 1개**, `ULocalPlayer`의 생명주기를 따른다.  
특정 플레이어의 UI 입력 전체를 담당하는 per-player 허브다.

---

## 3. 담당하는 역할 전체

ActionRouter가 하는 일을 크게 나누면 다섯 가지다.

### 3-1. AnalogCursor 생성 및 등록

```cpp
void UCommonUIActionRouterBase::Initialize(...)
{
    AnalogCursor = MakeAnalogCursor();          // FCommonAnalogCursor 생성
    PostAnalogCursorCreate();
      └── RegisterAnalogCursorTick()
            └── SlateApp.RegisterInputPreProcessor(AnalogCursor, ...)
}
```

커서를 생성하고 SlateApplication에 `IInputProcessor`로 등록하는 것이 ActionRouter의 첫 번째 역할이다.  
`FCommonAnalogCursor`가 ActionRouter를 참조 멤버로 보유하는 이유도 여기서 비롯된다 — 커서가 동작하는 데 필요한 모든 컨텍스트(플레이어, 입력 장치, 캡처 모드, 스크롤 대상 등)가 ActionRouter에 모여 있기 때문이다.

### 3-2. Activatable Widget Tree 관리

ActionRouter는 화면에 활성화된 `UCommonActivatableWidget`들을 **트리 구조**로 관리한다.

```
FActivatableTreeRoot          ← 루트 위젯 (예: 전체 HUD 레이어)
  └── FActivatableTreeNode    ← 자식 위젯 (예: 팝업)
        └── FActivatableTreeNode  ← 손자 위젯 (예: 팝업 안 확인 다이얼로그)
```

- `RootNodes` — 등록된 루트 노드 전체 목록
- `ActiveRootNode` — 현재 입력을 받는 루트
- 위젯이 `Activate()` 되면 노드가 생기고, `Deactivate()` 되면 제거된다

이 트리가 있어야 "어느 위젯이 지금 입력을 받아야 하는가"를 판단할 수 있다.

### 3-3. UIAction 바인딩 등록 및 입력 라우팅

```cpp
// 위젯이 바인딩을 등록할 때
FUIActionBindingHandle RegisterUIActionBinding(const UWidget& Widget, const FBindUIActionArgs& Args);

// 입력 이벤트가 들어올 때
ERouteUIInputResult ProcessInput(FKey Key, EInputEvent InputEvent) const;
```

`RegisterUIActionBinding`은 입력 바인딩을 해당 위젯의 트리 노드에 연결한다.  
`ProcessInput`은 트리의 **리프(Leaf, 가장 최근에 활성화된 노드)에서 루트 방향으로** 올라가며 바인딩을 탐색하고 핸들러를 호출한다.

```
입력 발생 (예: B버튼)
    ↓
ProcessInput()
    ↓
리프 노드의 바인딩 검색 → 처리 가능하면 호출
    ↓ (처리 못하면)
부모 노드로 올라감
    ↓ (처리 못하면)
PersistentActions (항상 살아있는 바인딩) 검색
```

이 구조 덕분에 팝업이 열려 있으면 팝업이 입력을 먼저 받고, 팝업이 닫히면 자동으로 아래 레이어가 입력을 받게 된다.

### 3-4. 입력 설정(InputConfig) 관리

```cpp
void SetActiveUIInputConfig(const FUIInputConfig& NewConfig, ...);
ECommonInputMode GetActiveInputMode(...) const;
EMouseCaptureMode GetActiveMouseCaptureMode(...) const;
```

`FUIInputConfig`는 현재 활성 위젯이 원하는 입력 모드(Game / Menu / GameAndMenu)와 마우스 캡처 모드를 담는다.  
트리의 리프 노드가 바뀔 때마다 해당 노드의 InputConfig를 읽어 `SetActiveUIInputConfig`로 적용한다.

`FCommonAnalogCursor`는 `GetActiveMouseCaptureMode()`로 현재 캡처 상태를 조회해 입력 처리 여부를 결정한다.

### 3-5. 스크롤 수신자 및 기타 컨텍스트 제공

```cpp
void RegisterScrollRecipient(const UWidget& ScrollableWidget);
void UnregisterScrollRecipient(const UWidget& ScrollableWidget);
TArray<const UWidget*> GatherActiveAnalogScrollRecipients() const;
```

오른쪽 스틱 스크롤을 받아야 하는 위젯들을 관리한다.  
`FCommonAnalogCursor::Tick()`에서 `GatherActiveAnalogScrollRecipients()`를 호출해 스크롤 이벤트를 전달한다.

이 외에도 `GetLocalPlayerIndex()`, `GetLocalPlayerChecked()`, `GetInputSubsystem()`, `ShouldAlwaysShowCursor()` 등 커서와 입력 처리에 필요한 컨텍스트를 모두 제공한다.

---

## 4. 전체 구조 한눈에 보기

```
ULocalPlayer
  └── UCommonUIActionRouterBase  (LocalPlayerSubsystem)
        │
        ├── FCommonAnalogCursor          ← SlateApp IInputProcessor로 등록
        │     └── (ActionRouter 참조)   ← 커서가 컨텍스트를 ActionRouter에서 가져옴
        │
        ├── RootNodes[]                  ← 활성 위젯 트리
        │     └── FActivatableTreeRoot
        │           └── FActivatableTreeNode (자식들)
        │                 └── UIActionBinding들
        │
        ├── ActiveRootNode               ← 지금 입력 받는 루트
        ├── ActiveInputConfig            ← 현재 적용된 입력 모드
        └── PersistentActions            ← 항상 활성화된 바인딩
```

---

## 5. 입력 흐름 전체

```
[하드웨어 입력]
      ↓
FCommonAnalogCursor::HandleKeyDownEvent()   ← IInputProcessor, Slate 최상단
  ├── IsRelevantInput() 체크 (게임패드? 뷰포트 포커스?)
  ├── ActionRouter.ProcessInput()           ← UIAction 바인딩 우선 처리
  └── FAnalogCursor::HandleKeyDownEvent()  ← 아니면 마우스 클릭 시뮬레이션
      ↓ (처리 안 된 경우)
SlateApplication 기본 이벤트 처리
  └── 위젯 OnKeyDown, OnClick 등
```

ActionRouter는 이 흐름의 **판단 센터**다. 커서(`FCommonAnalogCursor`)가 "이 입력을 내가 처리해야 하나?"를 물어볼 때마다 ActionRouter가 답을 제공한다.

---

## 6. "ActionRouter"라는 이름이 오해를 부르는 이유

"버튼 클릭 후 액션을 라우팅하는 놈"처럼 들리지만, 실제로는 입력 파이프라인 **전체**를 총괄한다.

| 단계 | 역할 |
|------|------|
| 입력 전처리 | AnalogCursor를 SlateApp에 등록 |
| 입력 판단 | IsRelevantInput 조건 제공 (캡처 모드, 플레이어 인덱스 등) |
| 입력 라우팅 | ProcessInput → 트리 탐색 → 바인딩 핸들러 호출 |
| 입력 설정 | ActiveInputConfig 관리, 뷰포트 캡처 모드 관리 |
| 커서 제어 | 스크롤 수신자 제공, 커서 표시 정책 제공 |

"UI 입력 시스템의 핵"이 더 정확한 표현이다.
