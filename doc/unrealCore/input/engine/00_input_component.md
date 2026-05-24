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

```
BuildInputStack() 호출 순서 (낮음 → 높음)
    [1] Pawn->InputComponent
    [2] Pawn에 붙은 다른 UInputComponent 파생 컴포넌트
    [3] LevelScriptActor->InputComponent
    [4] PlayerController->InputComponent
    [5] PushInputComponent()로 수동 추가된 것  ← 최우선
```

상위가 입력을 **소비(consume)** 하면 하위로 전달되지 않는다.

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
