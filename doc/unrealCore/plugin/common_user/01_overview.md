# CommonUser 플러그인 — 개요 및 구조

출처: `Plugins/CommonUser/Source/CommonUser/`

---

## 설계 철학

OSS(Online Subsystem)는 플랫폼별 기능(로그인, 세션 등)에 대한 저수준 인터페이스다.
유연하지만 **게임플레이 세션의 하이레벨 플로**를 직접 지원하지 않는다.

CommonUser 플러그인은 그 위에 앉아서:
- 참여 화면(Press Start)
- 컨트롤러 → 유저 매핑
- 멀티플레이 세션 호스팅/검색/참여

같은 **게임에서 반복되는 공통 작업**을 추상화한다.

> Lyra 전용이 아니라 어느 프로젝트에나 복사해서 쓸 수 있다.

---

## 파일 구조

```
Plugins/CommonUser/Source/CommonUser/Public/
  CommonUserTypes.h           ← 열거형·구조체 정의
  CommonUserSubsystem.h       ← UCommonUserSubsystem, UCommonUserInfo
  CommonSessionSubsystem.h    ← UCommonSessionSubsystem, 세션 관련 오브젝트들
  AsyncAction_CommonUserInitialize.h  ← BP용 비동기 액션 래퍼
  CommonUserBasicPresence.h   ← 프레즌스(상태 표시) 기능
```

---

## OSSv1 vs OSSv2 전환

파일 전체에 `#if COMMONUSER_OSSV1` 분기가 있다.

```cpp
// CommonUser.Build.cs 에서 설정
bool bUseOnlineSubsystemV1 = true; // 기본값

// false로 바꾸면 OSSv2(실험 단계) 사용
```

OSSv2로 전환하려면 `DefaultEngine.ini`에도 추가해야 한다:

```ini
[/Script/Engine.OnlineEngineInterface]
bUseOnlineServicesV2=true
```

EOS를 쓰면서 v2로 전환할 때는 `OnlineSubsystemEOS`도 비활성화해야 충돌이 없다:

```ini
[OnlineSubsystemEOS]
bEnabled=false
```

두 버전은 API 이름이 다르다:

| 역할 | OSSv1 | OSSv2 |
|------|-------|-------|
| 서브시스템 | `IOnlineSubsystem*` | `UE::Online::IOnlineServicesPtr` |
| 인증 인터페이스 | `IOnlineIdentity*` | `UE::Online::IAuthPtr` |
| 에러 타입 | `FOnlineError` | `UE::Online::FOnlineError` |
| 로그인 상태 | `ELoginStatus::Type` | `UE::Online::ELoginStatus` |

내부적으로는 `using FOnlineErrorType = ...` 으로 aliasing해서 공통 코드가 두 버전 모두 컴파일된다:

```cpp
// CommonUserTypes.h
#if COMMONUSER_OSSV1
    using FOnlineErrorType = FOnlineError;
    using ELoginStatusType = ELoginStatus::Type;
#else
    using FOnlineErrorType = UE::Online::FOnlineError;
    using ELoginStatusType = UE::Online::ELoginStatus;
#endif
```

---

## Lyra에서의 설치 방식

Lyra는 CommonUser를 게임 플러그인으로 포함한다 (`Plugins/CommonUser/`).
엔진 기본 포함이 아니므로 다른 프로젝트에 쓰려면 폴더째 복사 후 활성화해야 한다.

C++ 의존성 추가:
```csharp
// ModuleName.Build.cs
PrivateDependencyModuleNames.Add("CommonUser");
```

---

## Lyra 연결 지점

| 클래스 | 역할 |
|--------|------|
| `UCommonGameInstance` (CommonGame 플러그인) | `UCommonUserSubsystem` 이벤트를 받아 에러 팝업 표시 |
| `ULyraFrontendStateComponent` | `UCommonUserSubsystem`에 직접 접근해 로그인 흐름 조율 |
| `W_LyraStartup` (위젯 BP) | Press Start 화면 — `ListenForLoginKeyInput` 호출 |
| `W_ExperienceSelectionScreen` | 온라인 로그인 요청 + 세션 호스팅/퀵플레이 |
| `W_HostSessionScreen` | `UCommonSessionSubsystem::HostSession` 호출 |
| `W_SessionBrowserScreen` | `FindSessions` + `JoinSession` 호출 |
