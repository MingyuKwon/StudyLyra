# UCommonSessionSubsystem — 세션 호스팅·검색·참여

출처: `Plugins/CommonUser/Source/CommonUser/Public/CommonSessionSubsystem.h`

---

## 역할

멀티플레이어 세션의 **생성, 검색, 참여** 전체 흐름을 관리하는 게임 인스턴스 서브시스템.
OSS Session Interface(또는 OSSv2 Lobbies)를 래핑해서 플랫폼 독립적인 API를 제공한다.

```cpp
UCLASS(MinimalAPI, BlueprintType, Config=Engine)
class UCommonSessionSubsystem : public UGameInstanceSubsystem
```

---

## 관련 데이터 클래스

### UCommonSession_HostSessionRequest — 호스팅 파라미터

```cpp
UCLASS(MinimalAPI, BlueprintType)
class UCommonSession_HostSessionRequest : public UObject
{
public:
    ECommonSessionOnlineMode OnlineMode;    // Offline / LAN / Online
    bool bUseLobbies;                       // P2P 로비 사용 여부 (EOS 필요)
    bool bUseLobbiesVoiceChat;
    bool bUsePresence;                      // 프레즌스에 게임 상태 표시
    FString ModeNameForAdvertisement;       // 매치메이킹 필터용 모드 이름
    FPrimaryAssetId MapID;                  // 로드할 맵 (Primary Asset ID)
    TMap<FString, FString> ExtraArgs;       // URL 옵션으로 전달될 추가 인자
    int32 MaxPlayerCount = 16;

    // 내부적으로 ServerTravel에 넘길 URL 조합
    virtual FString ConstructTravelURL() const;
};
```

### UCommonSession_SearchSessionRequest — 검색 파라미터 + 결과

```cpp
UCLASS(MinimalAPI, BlueprintType)
class UCommonSession_SearchSessionRequest : public UObject
{
public:
    ECommonSessionOnlineMode OnlineMode;
    bool bUseLobbies;

    // 검색 완료 후 채워지는 결과 배열
    TArray<TObjectPtr<UCommonSession_SearchResult>> Results;

    // 검색 완료 델리게이트
    FCommonSession_FindSessionsFinished OnSearchFinished;
};
```

### UCommonSession_SearchResult — 개별 검색 결과

```cpp
UCLASS(MinimalAPI, BlueprintType)
class UCommonSession_SearchResult : public UObject
{
public:
    // 내부 플랫폼별 구현 포인터
#if COMMONUSER_OSSV1
    FOnlineSessionSearchResult Result;
#else
    TSharedPtr<const UE::Online::FLobby> Lobby;
    UE::Online::FOnlineSessionId SessionID;
#endif

    // BP에서 쓸 수 있는 쿼리 함수들
    FString GetDescription() const;
    void    GetStringSetting(FName Key, FString& Value, bool& bFoundValue) const;
    int32   GetNumOpenPublicConnections() const;
    int32   GetPingInMs() const;
};
```

---

## 퍼블릭 API

### 세션 생성 및 참여

```cpp
// 새 세션 생성 후 맵으로 ServerTravel
// 성공 시 OnCreateSessionCompleteEvent 브로드캐스트 → 맵 이동
void HostSession(APlayerController* HostingPlayer, UCommonSession_HostSessionRequest* Request);

// 세션 검색 후 빈자리 있으면 참여, 없으면 새로 호스팅
// 가장 많이 쓰이는 매치메이킹 진입점
void QuickPlaySession(APlayerController* JoiningOrHostingPlayer, UCommonSession_HostSessionRequest* Request);

// 검색 결과 오브젝트로 특정 세션에 참여
// 성공 시 OnJoinSessionCompleteEvent 브로드캐스트 → 서버 Connect
void JoinSession(APlayerController* JoiningPlayer, UCommonSession_SearchResult* Request);

// 참여 가능한 세션 목록 조회
// 완료 시 Request->OnSearchFinished 델리게이트 호출
void FindSessions(APlayerController* SearchingPlayer, UCommonSession_SearchSessionRequest* Request);

// 메인 메뉴 복귀 시 세션 정리
void CleanUpSessions();
```

### 팩토리 함수

```cpp
// Config 기본값으로 채워진 요청 오브젝트 생성
UCommonSession_HostSessionRequest*   CreateOnlineHostSessionRequest();
UCommonSession_SearchSessionRequest* CreateOnlineSearchSessionRequest();
```

---

## 세션 생성 내부 흐름

```
HostSession()
  └─ CreateOnlineSessionInternal()
        ├─ [OSSv1] CreateOnlineSessionInternalOSSv1()
        │     └─ IOnlineSession::CreateSession()
        │           → OnCreateSessionComplete()
        │                 → FinishSessionCreation()
        │                       → CreateHostReservationBeacon()  (bUseBeacons=true)
        │                             → ServerTravel(PendingTravelURL)
        └─ [OSSv2] CreateOnlineSessionInternalOSSv2()
              └─ ILobbies::CreateLobby() 또는 ISessions::CreateSession()
```

세션 생성 완료 → 맵 이동 전에 `OnCreateSessionCompleteEvent`가 발행된다.

---

## 세션 참여 내부 흐름

```
JoinSession()
  └─ JoinSessionInternal()
        ├─ [OSSv1] JoinSessionInternalOSSv1()
        │     └─ IOnlineSession::JoinSession()
        │           → OnJoinSessionComplete()
        │                 → ConnectToHostReservationBeacon()  (bUseBeacons=true)
        │                       → InternalTravelToSession()
        │                             → ClientTravel(URL)
        └─ [OSSv2] JoinSessionInternalOSSv2()
```

참여 완료 → 서버 Connect 전에 `OnJoinSessionCompleteEvent`가 발행된다.

---

## QuickPlay 흐름

```
QuickPlaySession()
  └─ FindSessionsInternal(QuickPlaySearchSettings)
        → HandleQuickPlaySearchFinished()
              ├─ 결과 있음 → JoinSession()
              └─ 결과 없음 → HostSession()
```

`HandleQuickPlaySearchFinished()`는 virtual이라 서브클래스에서 오버라이드 가능.

---

## 주요 델리게이트

```cpp
// 세션 생성 완료 (맵 이동 직전)
FCommonSessionOnCreateSessionComplete OnCreateSessionCompleteEvent;

// 세션 참여 완료 (서버 Connect 직전)
FCommonSessionOnJoinSessionComplete   OnJoinSessionCompleteEvent;

// 플랫폼 오버레이에서 초대 수락 시
FCommonSessionOnUserRequestedSession  OnUserRequestedSessionEvent;

// 플랫폼 오버레이에서 세션 나가기 요청 시
FCommonSessionOnDestroySessionRequested OnDestroySessionRequestedEvent;

// 리치 프레즌스용 — 세션 상태 변경 알림
FCommonSessionOnSessionInformationChanged OnSessionInformationChangedEvent;

// ClientTravel URL 수정 기회 (native only)
FCommonSessionOnPreClientTravel OnPreClientTravelEvent;
```

---

## 예약 비콘 (Reservation Beacon)

`bUseBeacons = true`(Config 기본값)이면 서버 이동 전에 `APartyBeaconHost/Client`로 자리 예약을 먼저 한다.

```cpp
// Config 값
int32 BeaconTeamCount = 2;
int32 BeaconTeamSize  = 8;
int32 BeaconMaxReservations = 16;  // 기본 16명

// 내부 흐름
CreateHostReservationBeacon()  // 서버: 호스팅 후 비콘 생성
ConnectToHostReservationBeacon() // 클라: 참여 후 비콘으로 자리 예약
DestroyHostReservationBeacon()   // 맵 이동 후 비콘 정리
```

비콘이 있으면 서버 정원이 꽉 차기 전에 클라이언트가 안전하게 참여 가능 여부를 확인할 수 있다.

---

## ECommonSessionOnlineMode

```cpp
enum class ECommonSessionOnlineMode : uint8
{
    Offline,  // 온라인 백엔드 미사용 — 싱글 플레이어 세션
    LAN,      // 로컬 네트워크만
    Online    // 완전한 온라인 세션
};
```

`Offline`으로 `HostSession`을 호출하면 세션이 온라인 백엔드에 등록되지 않는다.
UI 코드가 싱글/멀티 구분 없이 동일한 흐름을 쓸 수 있게 해주는 설계.

---

## Lyra에서의 사용 흐름

```
W_ExperienceSelectionScreen
  ├─ QuickPlaySession() → 빠른 매치메이킹
  └─ W_HostSessionScreen → HostSession() → 맵 선택 후 호스팅

W_SessionBrowserScreen
  ├─ FindSessions() → 세션 목록 갱신
  └─ JoinSession(SearchResult) → 선택한 세션 참여
```

`ULyraUserFacingExperienceDefinition` 에셋이 어떤 맵과 모드를 쓸지 정의하고,
위젯이 이를 읽어서 `UCommonSession_HostSessionRequest`를 구성한다.
