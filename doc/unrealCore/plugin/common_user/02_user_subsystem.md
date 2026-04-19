# UCommonUserSubsystem — 유저 로그인·권한 관리

출처: `Plugins/CommonUser/Source/CommonUser/Public/CommonUserSubsystem.h`

---

## 역할

게임 인스턴스 서브시스템으로, **유저 1명의 로그인/인증/권한** 전체 흐름을 관리한다.
OSS Identity Interface 초기화를 처리하고, 그 결과를 `UCommonUserInfo` 오브젝트에 캐싱한다.

```cpp
UCLASS(MinimalAPI, BlueprintType, Config=Engine)
class UCommonUserSubsystem : public UGameInstanceSubsystem
```

게임별 서브클래스가 존재하면 베이스 클래스는 생성되지 않는다 (`ShouldCreateSubsystem` 오버라이드).

---

## 핵심 타입 (CommonUserTypes.h)

### ECommonUserOnlineContext

어느 온라인 시스템을 쓸지 지정하는 열거형.

```cpp
enum class ECommonUserOnlineContext : uint8
{
    Game,              // 기본값 — 여러 컨텍스트 결과를 합쳐서 반환
    Default,           // 항상 존재하는 엔진 기본 시스템
    Service,           // EOS 같은 외부 서비스 (없을 수 있음)
    ServiceOrDefault,  // Service 우선, 없으면 Default
    Platform,          // 콘솔 플랫폼 시스템 (없을 수 있음)
    PlatformOrDefault, // Platform 우선, 없으면 Default
    Invalid
};
```

> PC/모바일에서는 보통 Service = Default = Platform 이 같다.
> 콘솔에서는 플랫폼 로그인(Platform)과 EOS 로그인(Service)이 분리된다.

### ECommonUserInitializationState

유저 초기화 상태 머신의 각 상태.

```cpp
enum class ECommonUserInitializationState : uint8
{
    Unknown,            // 로그인 시작 전
    DoingInitialLogin,  // 로컬 로그인 진행 중
    DoingNetworkLogin,  // 온라인 로그인 진행 중 (로컬 완료 후)
    FailedtoLogin,      // 로그인 실패
    LoggedInOnline,     // 온라인 포함 완전 로그인
    LoggedInLocalOnly,  // 로컬만 로그인 (온라인 불가)
    Invalid,
};
```

### ECommonUserPrivilege

유저가 가질 수 있는 권한 종류.

```cpp
enum class ECommonUserPrivilege : uint8
{
    CanPlay,                       // 게임 자체 플레이 가능
    CanPlayOnline,                 // 온라인 플레이 가능
    CanCommunicateViaTextOnline,   // 텍스트 채팅
    CanCommunicateViaVoiceOnline,  // 음성 채팅
    CanUseUserGeneratedContent,    // UGC 접근
    CanUseCrossPlay,               // 크로스플레이
    Invalid_Count
};
```

### ECommonUserAvailability

권한의 현재 가용 수준.

```cpp
enum class ECommonUserAvailability : uint8
{
    Unknown,             // 아직 쿼리 안 함
    NowAvailable,        // 지금 사용 가능
    PossiblyAvailable,   // 로그인 완료 후 사용 가능할 수 있음
    CurrentlyUnavailable,// 지금은 불가(네트워크 등) — 나중에 가능할 수 있음
    AlwaysUnavailable,   // 영구적으로 불가(계정 밴 등)
    Invalid,
};
```

---

## UCommonUserInfo

유저 1명의 상태를 저장하는 UObject.
`UCommonUserSubsystem::LocalUserInfos` TMap에 LocalPlayerIndex 키로 보관된다.

```cpp
UCLASS(MinimalAPI, BlueprintType)
class UCommonUserInfo : public UObject
{
public:
    FInputDeviceId PrimaryInputDevice;   // 이 유저의 기본 컨트롤러
    FPlatformUserId PlatformUser;        // 플랫폼 유저 ID
    int32 LocalPlayerIndex = -1;         // GameInstance 내 LocalPlayer 인덱스
    bool bCanBeGuest = false;
    bool bIsGuest = false;
    ECommonUserInitializationState InitializationState;

    // 캐시 — 온라인 컨텍스트별로 분리 저장
    struct FCachedData
    {
        FUniqueNetIdRepl CachedNetId;
        FString CachedNickname;
        TMap<ECommonUserPrivilege, ECommonUserPrivilegeResult> CachedPrivileges;
    };
    TMap<ECommonUserOnlineContext, FCachedData> CachedDataMap;
};
```

주요 퍼블릭 함수:

```cpp
bool IsLoggedIn() const;
bool IsDoingLogin() const;
ECommonUserPrivilegeResult GetCachedPrivilegeResult(ECommonUserPrivilege, ECommonUserOnlineContext) const;
ECommonUserAvailability    GetPrivilegeAvailability(ECommonUserPrivilege) const;
FUniqueNetIdRepl           GetNetId(ECommonUserOnlineContext) const;
FString                    GetNickname(ECommonUserOnlineContext) const;
```

---

## 초기화 흐름 (스테이트 머신)

```
[Unknown]
    │ TryToInitializeForLocalPlay() 또는 TryToInitializeUser()
    ▼
[DoingInitialLogin]
    │ AutoLogin → 플랫폼 로그인 UI → 권한 쿼리
    ▼
[LoggedInLocalOnly]   ← 여기까지: 로컬 저장, 싱글 플레이 가능
    │ TryToLoginForOnlinePlay()
    ▼
[DoingNetworkLogin]
    │ 온라인 서비스 로그인 → 온라인 권한 쿼리
    ▼
[LoggedInOnline]      ← 여기까지: 멀티플레이 세션 생성/참여 가능
```

실패 시 `[FailedtoLogin]` 으로 전환되고 `OnHandleSystemMessage` 델리게이트가 발행된다.

내부적으로 `FUserLoginRequest` 구조체가 각 단계의 비동기 상태를 추적한다:

```cpp
struct FUserLoginRequest : public TSharedFromThis<FUserLoginRequest>
{
    TWeakObjectPtr<UCommonUserInfo> UserInfo;
    ECommonUserAsyncTaskState OverallLoginState;
    ECommonUserAsyncTaskState TransferPlatformAuthState; // OSSv2 전용
    ECommonUserAsyncTaskState AutoLoginState;
    ECommonUserAsyncTaskState LoginUIState;
    ECommonUserAsyncTaskState PrivilegeCheckState;
    ECommonUserPrivilege      DesiredPrivilege;
    ECommonUserOnlineContext  DesiredContext;
    ECommonUserOnlineContext  CurrentContext;
    TOptional<FOnlineErrorType> Error;
};
```

단계별 내부 함수 체인:

```
ProcessLoginRequest()
  ├─ TransferPlatformAuth()   // 콘솔: 플랫폼 토큰을 서비스에 전달
  ├─ AutoLogin()              // 자동 로그인 시도
  ├─ ShowLoginUI()            // 실패 시 플랫폼 로그인 UI 표시
  └─ QueryUserPrivilege()     // 로그인 성공 후 권한 확인
```

---

## 퍼블릭 API

### 초기화 함수

```cpp
// 로컬 플레이용 초기화 (컨트롤러 지정)
bool TryToInitializeForLocalPlay(int32 LocalPlayerIndex, FInputDeviceId PrimaryInputDevice, bool bCanUseGuestLogin);

// 이미 로컬 로그인된 유저를 온라인까지 초기화
bool TryToLoginForOnlinePlay(int32 LocalPlayerIndex);

// 세부 파라미터로 전체 제어 (AsyncAction이 내부적으로 호출)
bool TryToInitializeUser(FCommonUserInitializeParams Params);

// Press Start 화면용 — 키 입력을 감지해 자동으로 TryToInitializeUser 호출
void ListenForLoginKeyInput(TArray<FKey> AnyUserKeys, TArray<FKey> NewUserKeys, FCommonUserInitializeParams Params);
```

### 유저 정보 조회

```cpp
const UCommonUserInfo* GetUserInfoForLocalPlayerIndex(int32 LocalPlayerIndex) const;
const UCommonUserInfo* GetUserInfoForPlatformUser(FPlatformUserId PlatformUser) const;
const UCommonUserInfo* GetUserInfoForUniqueNetId(const FUniqueNetIdRepl& NetId) const;
const UCommonUserInfo* GetUserInfoForInputDevice(FInputDeviceId InputDevice) const;
```

### 플랫폼 특성 태그

콘솔/PC별 동작 차이를 GameplayTag로 표현한다.

```cpp
struct FCommonUserTags
{
    // 콘솔: 컨트롤러 ID가 유저와 1:1 매핑됨
    static FNativeGameplayTag Platform_Trait_RequiresStrictControllerMapping;

    // 플랫폼에 온라인 유저가 1명만 있음 (index 0만 사용)
    static FNativeGameplayTag Platform_Trait_SingleOnlineUser;
};

// ShouldWaitForStartInput()은 이 태그를 보고 Press Start 화면이 필요한지 판단
bool ShouldWaitForStartInput() const;
```

### 주요 델리게이트

```cpp
// 초기화 성공/실패 (5파라미터: UserInfo, bSuccess, Error, RequestedPrivilege, OnlineContext)
FCommonUserOnInitializeCompleteMulticast OnUserInitializeComplete;

// 에러/경고 시스템 메시지 (MessageType 태그로 구분)
FCommonUserHandleSystemMessageDelegate OnHandleSystemMessage;

// 권한 변경 알림 (네트워크 끊김 등)
FCommonUserAvailabilityChangedDelegate OnUserPrivilegeChanged;
```

---

## BP용 비동기 액션 (AsyncAction_CommonUserInitialize.h)

BP 이벤트 그래프에서 사용하기 위한 `UCancellableAsyncAction` 래퍼.

```cpp
// 로컬 플레이 초기화 노드
static UAsyncAction_CommonUserInitialize* InitializeForLocalPlay(
    UCommonUserSubsystem* Target,
    int32 LocalPlayerIndex,
    FInputDeviceId PrimaryInputDevice,
    bool bCanUseGuestLogin);

// 온라인 로그인 노드
static UAsyncAction_CommonUserInitialize* LoginForOnlinePlay(
    UCommonUserSubsystem* Target,
    int32 LocalPlayerIndex);

// 완료 시 브로드캐스트
FCommonUserOnInitializeCompleteMulticast OnInitializationComplete;
```

내부적으로 `Activate()` → `TryToInitializeUser(Params)` → `HandleInitializationComplete()` 순서로 동작한다.

---

## 내부 구조: FOnlineContextCache

OSS 포인터와 연결 상태를 컨텍스트별로 캐싱하는 내부 구조체.

```cpp
struct FOnlineContextCache
{
#if COMMONUSER_OSSV1
    IOnlineSubsystem*               OnlineSubsystem;
    IOnlineIdentityPtr              IdentityInterface;
    EOnlineServerConnectionStatus::Type CurrentConnectionStatus;
#else
    UE::Online::IOnlineServicesPtr  OnlineServices;
    UE::Online::IAuthPtr            AuthService;
    UE::Online::EOnlineServicesConnectionStatus CurrentConnectionStatus;
#endif
};

// 서브시스템 내부에 세 컨텍스트 인스턴스를 보유
FOnlineContextCache* DefaultContextInternal  = nullptr;
FOnlineContextCache* ServiceContextInternal  = nullptr;
FOnlineContextCache* PlatformContextInternal = nullptr;
```
