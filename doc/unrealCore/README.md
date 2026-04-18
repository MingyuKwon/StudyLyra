# 언리얼 엔진 코어 분석

Lyra와 무관한 UE5 엔진 자체 시스템 분석 문서 모음.

| 파일/폴더 | 내용 |
|-----------|------|
| [input_pipeline.md](input_pipeline.md) | PlayerController 틱 → ProcessAbilityInput까지 입력 처리 경로 |
| [actor_lifecycle/](actor_lifecycle/README.md) | Actor/Component 전체 생명주기 — PostInitProperties부터 Destroyed까지 |
| [plugin/](plugin/README.md) | 엔진 공식 플러그인 분석 (ModularGameplay 등) |
| [replication/](replication/README.md) | 복제 시스템 — NetDriver 파이프라인, Actor 복제, Shadow Buffer, Relevancy |
| [world_framework.md](world_framework.md) | UWorld · AWorldSettings · GameMode · GameState — 역할 구분, 생성 체인, Lyra Experience 연결 |
