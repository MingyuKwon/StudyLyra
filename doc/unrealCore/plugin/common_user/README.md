# CommonUser 플러그인 분석

`Plugins/CommonUser/` — Lyra에 포함된 독립형 플러그인.

C++, 블루프린트, OSSv1/v2 사이의 **공통 인터페이스** 역할을 한다.
게임 인스턴스 서브시스템 두 개가 핵심이다.

| 문서 | 내용 |
|------|------|
| [01_overview.md](01_overview.md) | 설계 철학, 파일 구조, OSSv1/v2 전환 |
| [02_user_subsystem.md](02_user_subsystem.md) | UCommonUserSubsystem — 로그인·권한·초기화 스테이트 머신 |
| [03_session_subsystem.md](03_session_subsystem.md) | UCommonSessionSubsystem — 세션 호스팅·검색·참여 |

## 핵심 클래스 요약

```
UCommonUserSubsystem          (GameInstanceSubsystem)
  └─ UCommonUserInfo          (UObject, 유저 1명의 상태 오브젝트)

UCommonSessionSubsystem       (GameInstanceSubsystem)
  ├─ UCommonSession_HostSessionRequest   (세션 호스팅 파라미터)
  ├─ UCommonSession_SearchSessionRequest (세션 검색 파라미터 + 결과 배열)
  └─ UCommonSession_SearchResult         (개별 검색 결과)

UAsyncAction_CommonUserInitialize  (UCancellableAsyncAction, BP용 래퍼)
```
