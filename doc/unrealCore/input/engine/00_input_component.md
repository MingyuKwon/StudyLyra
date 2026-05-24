# InputComponent — 입력 바인딩 컨테이너

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/PlayerController.cpp`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/Pawn.cpp`

---

## InputComponent란

`UInputComponent`는 Actor가 "내가 이 입력들에 관심있다"고 등록하는 **바인딩 컨테이너**다.

`BindAction`, `BindAxis` 호출 결과(델리게이트 목록)를 저장하는 것이 전부다.  
입력을 직접 처리하거나 이벤트를 받지 않는다. 바인딩 목록만 들고 있다가 `ProcessInputStack`이 순회할 때 실행된다.

```
UEnhancedInputComponent (Pawn에 붙음)
    ├── BindAction(IA_Move, Triggered, this, &Input_Move)
    ├── BindAction(IA_Jump, Started,   this, &Input_Jump)
    └── BindAction(IA_Fire, Triggered, this, &Input_AbilityPressed, Tag_Fire)
```

---

## 기본 생성 위치

### PlayerController — InitInputSystem()

```
LocalPlayer가 PC에 연결될 때
    APlayerController::SetPlayer(LocalPlayer)
        → InitInputSystem()              ← PlayerInput + InputComponent 생성
            → PlayerInput = NewObject<UPlayerInput>(...)
            → SetupInputComponent()
                → InputComponent = NewObject<UInputComponent>(this,
                      UInputSettings::GetDefaultInputComponentClass())
                → InputComponent->RegisterComponent()
```

`SetupInputComponent()`는 가상 함수다. 서브클래스에서 오버라이드해서 PC 전용 바인딩을 추가한다.

### Pawn — PawnClientRestart()

```
APlayerController::Possess(Pawn)
    → Pawn->DispatchRestart()
        → Pawn->PawnClientRestart()      ← 로컬 PC일 때만 실행
            → [PC && IsLocalController()]
                → CreatePlayerInputComponent()   ← InputComponent 생성
                → SetupPlayerInputComponent(InputComponent)  ← 바인딩 등록 (가상 함수)
                → InputComponent->RegisterComponent()
```

`SetupPlayerInputComponent()`는 가상 함수다. 서브클래스에서 오버라이드해서 Pawn 전용 바인딩을 추가한다.  
**로컬 PC일 때만** 실행된다. 서버에서 빙의해도 서버 쪽 Pawn에는 InputComponent가 생성되지 않는다.

---

## 기본 클래스 — 어디서 결정되는가

```cpp
// PlayerController.cpp:2680
InputComponent = NewObject<UInputComponent>(this,
    UInputSettings::GetDefaultInputComponentClass(), TEXT("PC_InputComponent0"));
```

`UInputSettings::GetDefaultInputComponentClass()`가 반환하는 클래스는 **프로젝트 설정**에서 결정된다.

```
Project Settings → Engine → Input → Default Input Component Class
    Enhanced Input 플러그인 활성화 시: UEnhancedInputComponent (자동 설정)
    레거시:                            UInputComponent
```

Lyra는 `ULyraInputComponent`(UEnhancedInputComponent 서브클래스)를 기본 클래스로 설정해뒀다.

---

## BuildInputStack에 올라가는 방식

InputComponent가 생성·등록되면 매 틱 `BuildInputStack`이 자동으로 수집한다.  
수집 대상은 아래 5곳으로 고정되어 있다. **이 5곳 밖에 붙인 InputComponent는 수집되지 않는다.**

```
BuildInputStack() 수집 순서 (낮음 → 높음 = 스택 아래 → 위)
    [1] Pawn->InputComponent              ← 멤버 변수 직접 참조
    [2] Pawn의 추가 UInputComponent 컴포넌트  ← GetComponents() 전체 순회 + Cast
    [3] LevelScriptActor->InputComponent  ← GetWorld()->GetLevels() 순회
    [4] PlayerController->InputComponent  ← 멤버 변수 직접 참조
    [5] PushInputComponent() 추가분       ← CurrentInputStack 배열, 최우선
```

스택은 **위에서 아래로** 처리된다. 위(높은 우선순위)가 먼저 처리되고, 소비된 입력은 아래로 내려가지 않는다.

---

## 입력 소비 — 두 가지 레벨

### 바인딩 단위 — bConsumeInput

개별 바인딩마다 붙어있는 플래그다. 이 바인딩이 처리되면 해당 키에 `bConsumed = true`를 마킹한다.

```cpp
// EvaluateInputComponentDelegates 내부 (PlayerInput.cpp:1505)
if (!KeyWithEvent.Value->bConsumed)   // 이미 소비된 키는 건너뜀
{
    // 바인딩 처리
    KeyState->bConsumed = true;       // 처리 후 마킹
}
```

특정 키만 소비하고 나머지는 하위 컴포넌트로 계속 전달된다.

### 컴포넌트 단위 — bBlockInput

InputComponent 자체에 붙어있는 플래그다.  
이걸 켜면 `EvaluateInputComponentDelegates`가 `true`를 반환하고, **이 컴포넌트 이하 전체가 차단된다.**

```cpp
// ProcessInputStack 내부 (PlayerInput.cpp:1457)
for (StackIndex = 맨 위부터 아래로)
{
    bool bBlocks = EvaluateInputComponentDelegates(IC, ...);  // bBlockInput이면 true
    if (bBlocks)
    {
        break;  // 순회 중단
    }
}
// 차단된 나머지: 콜백 실행 없이 Axis 값만 0으로 초기화
for (나머지)
    EvaluateBlockedInputComponent(IC);
```

### 요약

| | bConsumeInput | bBlockInput |
|---|---|---|
| **단위** | 개별 바인딩 | InputComponent 전체 |
| **효과** | 해당 키만 소비, 나머지 전달 | 이 컴포넌트 이하 전부 차단 |
| **사용처** | 점프키를 상위에서 가로채고 이동키는 전달 | 컷신 중 UI가 모든 입력 독점 |

---

## EnableInput / DisableInput

`APawn::EnableInput(PC)` / `DisableInput(PC)` 는 `bInputEnabled` 플래그만 바꾼다.  
`BuildInputStack`이 Pawn의 InputComponent를 수집할 때 이 플래그를 보고 스킵한다.  
InputComponent 자체를 파괴하거나 바인딩을 지우는 게 아니다.

```cpp
// 예: 컷신 중 Pawn 입력 차단
Pawn->DisableInput(PlayerController);

// 컷신 종료 후 복구
Pawn->EnableInput(PlayerController);
```
