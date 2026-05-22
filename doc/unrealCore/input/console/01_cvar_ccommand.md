# CVar / CCommand 시스템

> 출처: `C:/UE_5.7/Engine/Source/Runtime/Core/Public/HAL/IConsoleManager.h`

---

## 개요

언리얼의 콘솔 변수/명령어 시스템은 **게임 입력 파이프라인과 완전히 분리된** 전역 개발자 도구다.

| | CVar (Console Variable) | CCommand (Console Command) |
|---|---|---|
| **목적** | 값을 읽고 쓰는 변수 | 함수를 실행하는 명령어 |
| **타입** | bool, int32, float, FString | 없음 (콜백 함수) |
| **런타임 접근** | `GetValueOnGameThread()` | 실행 후 결과 없음 |
| **클래스** | `IConsoleVariable` | `IConsoleCommand` |

둘 다 `IConsoleObject`를 상속한다.

---

## IConsoleManager — 전역 싱글톤

```cpp
// 어디서든 전역 접근
IConsoleManager& Manager = IConsoleManager::Get();

// CVar 등록
IConsoleVariable* CVar = Manager.RegisterConsoleVariable(
    TEXT("MyGame.DebugMode"),   // 이름
    0,                           // 기본값 (int32)
    TEXT("디버그 모드 토글"),    // 도움말
    ECVF_Cheat                   // 플래그
);

// CCmd 등록
IConsoleCommand* Cmd = Manager.RegisterConsoleCommand(
    TEXT("MyGame.DumpState"),
    TEXT("현재 상태를 덤프"),
    FConsoleCommandWithWorldDelegate::CreateStatic(&DumpStateFn)
);
```

---

## 실제 사용 패턴 — TAutoConsoleVariable

직접 `IConsoleManager`를 쓰지 않고, **static 전역 객체**로 선언하는 것이 일반적.

```cpp
// 파일 상단 static 선언 (자동 등록/해제)
static TAutoConsoleVariable<int32> CVarDebugMode(
    TEXT("MyGame.DebugMode"),
    0,                          // 기본값
    TEXT("디버그 모드 토글"),
    ECVF_Cheat
);

// 값 읽기
int32 bDebug = CVarDebugMode.GetValueOnGameThread();

// 값 쓰기 (C++에서)
CVarDebugMode->Set(1, ECVF_SetByCode);
```

### FAutoConsoleCommand / FAutoConsoleCommandWithWorld

```cpp
// 인자 없는 명령어
static FAutoConsoleCommand CmdDump(
    TEXT("MyGame.Dump"),
    TEXT("상태 덤프"),
    FConsoleCommandDelegate::CreateStatic(&DumpFn)
);

// World + Args 있는 명령어 (가장 많이 쓰임)
static FAutoConsoleCommandWithWorldAndArgs CmdSpawn(
    TEXT("MyGame.Spawn"),
    TEXT("오브젝트 스폰"),
    FConsoleCommandWithWorldAndArgsDelegate::CreateStatic(&SpawnFn)
);
```

---

## CCommand 콜백 종류

`FConsoleCommandXxxDelegate` 패밀리에서 필요한 시그니처를 선택한다.

| 델리게이트 타입 | 파라미터 |
|---|---|
| `FConsoleCommandDelegate` | 없음 |
| `FConsoleCommandWithArgsDelegate` | `const TArray<FString>&` |
| `FConsoleCommandWithWorldDelegate` | `UWorld*` |
| `FConsoleCommandWithWorldAndArgsDelegate` | `const TArray<FString>&, UWorld*` |
| `FConsoleCommandWithOutputDeviceDelegate` | `FOutputDevice&` |
| `FConsoleCommandWithWorldArgsAndOutputDeviceDelegate` | `const TArray<FString>&, UWorld*, FOutputDevice&` |

---

## EConsoleVariableFlags — 주요 플래그

| 플래그 | 의미 |
|---|---|
| `ECVF_Default` | 기본값, 플래그 없음 |
| `ECVF_Cheat` | 릴리즈 빌드에서 숨겨짐, 콘솔에서 변경 불가 |
| `ECVF_ReadOnly` | 콘솔에서 변경 불가. C++/ini에서는 가능 |
| `ECVF_RenderThreadSafe` | 렌더 스레드에서도 안전하게 접근 가능 |
| `ECVF_Scalability` | Scalability.ini와 연동 |

### SetBy 우선순위 (낮음 → 높음)

```
Constructor < Scalability < GameSetting < ProjectSetting < SystemSettingsIni
    < DeviceProfile < ConsoleVariablesIni < Hotfix < Commandline < Code < Console
```

콘솔에서 입력한 값은 `ECVF_SetByConsole`(최고 우선순위). 낮은 우선순위의 Set 호출은 높은 우선순위 값을 덮어쓰지 못한다.

---

## 콘솔에서의 CVar 사용법

```
MyGame.DebugMode        ← 현재 값 출력
MyGame.DebugMode 1      ← 값을 1로 설정
MyGame.DebugMode ?      ← 도움말 출력
```

---

## CVar 변경 콜백 (Sink)

```cpp
// 변경 시 즉시 호출되는 콜백
static TAutoConsoleVariable<int32> CVarFoo(
    TEXT("MyGame.Foo"),
    0,
    TEXT("..."),
    FConsoleVariableDelegate::CreateLambda([](IConsoleVariable* Var)
    {
        int32 NewValue = Var->GetInt();
        // 변경에 반응
    })
);
```

또는 `FAutoConsoleVariableSink`로 여러 CVar 변경을 묶어 처리할 수 있다.

---

## 명령어 진입 경로 — 콘솔 창에서 실행 시

```
UConsole::ConsoleCommand(Command)         ← 콘솔 창에서 Enter
    └─ APlayerController::ConsoleCommand()
            └─ ULocalPlayer::ConsoleCommand()
                    └─ IConsoleManager::ProcessUserConsoleInput()
                            ├─ CVar 이름 매칭 → GetInt/Set
                            └─ CCmd 이름 매칭 → IConsoleCommand::Execute()
```

매칭되지 않으면 Exec 체인으로 전달 → [02_exec_functions.md](02_exec_functions.md) 참조
