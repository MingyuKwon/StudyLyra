# Lyra GAS 분석 캐시 인덱스

각 파일의 핵심 키워드를 보고 관련 파일만 읽는다.

| 파일 | 담긴 주제 |
|------|----------|
| [gas_asc_ga.md](gas_asc_ga.md) | ASC 소유구조, InitAbilityActorInfo, AbilitySystemGlobals, GA Tags(Source/Target/이벤트 트리거), TagRelationshipMapping |
| [attribute_set.md](attribute_set.md) | AttributeSet 클래스계층/등록, 콜백체인(Pre/Post), Clamp, ATTRIBUTE_ACCESSORS, 파생Attribute, FGameplayAttributeData, FOnAttributeChangeData |
| [gameplay_effect.md](gameplay_effect.md) | GE Modifier(Additive/Mult/Override), Instant/Duration/Infinite, 데미지 실행(LyraDamageExecution), Ongoing Tag Requirements, CDO 패턴 |
| [ability_task.md](ability_task.md) | UGameplayTask 상태머신, EAbilityGenericReplicatedEvent, WaitNetSync, TargetData(구조/Lyra 실제 사용) |
| [input_system.md](input_system.md) | PlayerController 입력 파이프라인, ProcessAbilityInput, Lyra 입력 시스템(LyraInputConfig/HeroComponent) |
| [modular_gamefeature.md](modular_gamefeature.md) | ModularGameplay(GameFrameworkComponentManager/InitState), GameFeature/Experience 로드 흐름, World프레임워크(GameMode/GameState) |
| [networking.md](networking.md) | 언리얼 복제 파이프라인(RepLayout/RPC), GetLifetimeReplicatedProps 매크로, PredictionKey 생명주기/롤백 |
| [unreal_core.md](unreal_core.md) | UGameplayTagsManager, LooseGameplayTag vs GE태그, Slate/UMG UI 파이프라인, CommonUser, 카메라 시스템, GameplayMessageSubsystem, PlayerController vs LocalPlayer |
