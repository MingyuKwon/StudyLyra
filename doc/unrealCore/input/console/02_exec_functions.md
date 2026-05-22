# Exec 함수 체계

> 출처: `C:/UE_5.7/Engine/Source/Runtime/CoreUObject/Public/UObject/Object.h:1544`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/Console.cpp:619`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/LocalPlayer.cpp:1488`

---

## 개요

Exec는 **텍스트 명령어를 UObject 계층에 전달**하는 시스템이다.  
CVar/CCmd로 처리되지 않은 명령어가 Exec 체인으로 넘어온다.

```cpp
// UObject.h:1544
virtual bool ProcessConsoleExec(const TCHAR* Cmd, FOutputDevice& Ar, UObject* Executor)
```

각 UObject가 이 함수를 오버라이드해 자신이 아는 명령어를 처리하고, 모르면 `false`를 반환해 다음으로 전달한다.

---

## 전체 라우팅 체인

```
UConsole::ConsoleCommand()
    └─ APlayerController::ConsoleCommand()
            └─ ULocalPlayer::Exec()
                    │  ← LocalPlayer 자신이 처리 (r.LockView 등)
                    └─ APlayerController::ProcessConsoleExec()
                            │  ← PC가 처리
                            ├─ UCheatManager::ProcessConsoleExec()   ← CheatManager
                            ├─ APawn::ProcessConsoleExec()           ← Pawn
                            ├─ AHUD::ProcessConsoleExec()            ← HUD
                            ├─ AGameModeBase::ProcessConsoleExec()   ← GameMode
                            ├─ AGameStateBase::ProcessConsoleExec()  ← GameState
                            ├─ UGameInstance::ProcessConsoleExec()   ← GameInstance
                            └─ UEngine::Exec()                       ← 엔진 (showdebug 등)
```

각 단계에서 `true`를 반환하면 체인 종료. 끝까지 처리 안 되면 "Unknown command" 출력.

---

## UFUNCTION(Exec) 선언 방법

```cpp
UCLASS()
class AMyPlayerController : public APlayerController
{
    GENERATED_BODY()

    UFUNCTION(Exec)
    void MyDebugCommand(int32 Value);   // 콘솔에서 "MyDebugCommand 5"로 실행
};
```

- `UFUNCTION(Exec)` 지정자 하나만 붙이면 된다.
- 함수는 반드시 `bool` 반환 또는 `void` 반환.
- 파라미터: `int32`, `float`, `bool`, `FString`, `FName`, `UObject*` 지원.
- 언리얼 리플렉션(UHT)이 자동으로 파라미터 파싱 코드를 생성한다.

```cpp
// 여러 파라미터도 가능
UFUNCTION(Exec)
void SpawnEnemy(FString EnemyType, int32 Count);
// 콘솔: "SpawnEnemy Goblin 5"
```

---

## ProcessConsoleExec 내부 동작

```
"MyDebugCommand 5" 입력
    ↓
APlayerController::ProcessConsoleExec()
    │
    ├─ UHT가 생성한 코드로 "MyDebugCommand" 함수명 매칭
    ├─ "5" 파싱 → int32(5)
    └─ MyDebugCommand(5) 호출
```

UHT가 `UFUNCTION(Exec)` 함수마다 파서 코드를 자동 생성하므로, 직접 파싱 코드를 작성할 필요가 없다.

---

## Exec vs CCommand 선택 기준

| 상황 | 권장 방식 |
|------|-----------|
| 특정 Actor/Component에 속하는 디버그 | `UFUNCTION(Exec)` |
| 글로벌 시스템 설정값 조정 | `TAutoConsoleVariable` (CVar) |
| 글로벌 디버그 동작 트리거 | `FAutoConsoleCommand` (CCmd) |
| Blueprint에서도 접근 필요 | `UFUNCTION(Exec)` |

---

## showdebug 명령어

`showdebug`는 특별한 Exec 명령어로, HUD의 `OnShowDebugInfo` 델리게이트를 통해 처리된다.

```
showdebug abilitysystem
    ↓
UEngine::Exec() 처리
    ↓
AHUD::OnShowDebugInfo 델리게이트 브로드캐스트
    ↓
UAbilitySystemComponent::OnShowDebugInfo() 호출
    (GameplayAbilitiesModule.cpp:83 에서 등록)
```

`showdebug` 카테고리 이름은 문자열 비교로 라우팅된다.

```cpp
// AbilitySystemComponent.cpp:2466
void UAbilitySystemComponent::OnShowDebugInfo(AHUD* HUD, UCanvas* Canvas,
    const FDebugDisplayInfo& DisplayInfo, float& YL, float& YPos)
{
    if (DisplayInfo.IsDisplayOn(TEXT("AbilitySystem")))
    {
        // HUD에 GAS 정보 그리기
    }
}
```
