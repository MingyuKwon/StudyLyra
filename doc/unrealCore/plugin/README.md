# 언리얼 엔진 공식 플러그인 분석

`Engine/Plugins/` 아래에 있는 Epic 공식 플러그인 분석 문서 모음.
Lyra 전용이 아닌 범용 엔진 플러그인이지만, Lyra에서 적극 활용하는 것들을 정리한다.

| 폴더 | 플러그인 경로 | 내용 |
|------|--------------|------|
| [modular_gameplay/](modular_gameplay/README.md) | `Engine/Plugins/Runtime/ModularGameplay/` | UGameFrameworkComponent 계층, 컴포넌트 주입, InitState 시스템, Lyra 활용 |
| [game_features.md](game_features.md) | `Engine/Plugins/Experimental/GameFeatures/` | UGameFeaturesSubsystem, UGameFeatureAction, Lyra Experience 시스템 전체 흐름 |
| [common_ui/](common_ui/README.md) | `Engine/Plugins/Runtime/CommonUI/` | 위젯 스택, 입력 모드, 게임패드 포커스, 버튼 스타일, UIAction 바인딩, 장치 감지 |
| [common_user/](common_user/README.md) | `Plugins/CommonUser/` | UCommonUserSubsystem(로그인·권한), UCommonSessionSubsystem(세션 호스팅·검색·참여) |
| [gameplay_message/](gameplay_message/README.md) | `Plugins/GameplayMessageRouter/` | UGameplayMessageSubsystem — GameplayTag 채널 기반 pub/sub 메시지 버스 |
