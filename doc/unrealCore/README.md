# 언리얼 엔진 코어 분석

Lyra와 무관한 UE5 엔진 자체 시스템 분석 문서 모음.

| 파일/폴더 | 내용 |
|-----------|------|
| [uobject/](uobject/README.md) | UObject 시스템 — GC, CDO, DefaultSubobject, IsValid, Blueprint Asset |
| [reflection/](reflection/README.md) | 리플렉션 시스템 — UHT 파이프라인, 타입 객체 계층, 지정자, GC/직렬화/Blueprint/RPC 활용 |
| [actor/](actor/README.md) | Actor·Component 개념, SpawnActor 메커니즘, 생명주기 |
| [collision/](collision/README.md) | Collision 시스템 — Block/Overlap/Ignore, CollisionEnabled 종류, 성능 최적화 |
| [input/](input/README.md) | 입력 시스템 전체 — 엔진 파이프라인, Enhanced Input, Lyra 구현, 콘솔 입력 |
| [plugin/](plugin/README.md) | 엔진 공식 플러그인 분석 (ModularGameplay 등) |
| [replication/](replication/README.md) | 복제 시스템 — NetDriver 파이프라인, Actor 복제, Shadow Buffer, Relevancy |
| [network/](network/README.md) | 네트워크 기초 — RPC vs Property Replication Owner 체인 차이, Controller 없는 NPC 제약 |
| [string_types.md](string_types.md) | FString · FName · FText — 내부 구조, 비교 속도, 용도 구분, 타입 간 변환 |
| [delegate/](delegate/README.md) | Delegate — Single/Multicast/Dynamic 종류, 선언·바인딩·실행, 내부 구현, 안전성 |
| [world_framework.md](world_framework.md) | UWorld · AWorldSettings · GameMode · GameState — 역할 구분, 생성 체인, Lyra Experience 연결 |
| [player_framework.md](player_framework.md) | PlayerController · LocalPlayer — 생존 범위 차이, 분리 이유, 스플릿스크린 |
| [prediction_key.md](prediction_key.md) | FPredictionKey — 구조, 예측 윈도우 수명, Reject/CatchUp 두 종료 경로, NetSerialize 특수 동작, 의존성 체인 |
| [slate/](slate/README.md) | Slate UI 프레임워크 — SWidget 계층, TSharedRef 메모리 모델, 레이아웃 시스템, 선언형 문법 |
| [umg/](umg/README.md) | UMG — UWidget 계층, UUserWidget 생명주기, 뷰포트 추가/제거, BindWidget/Property Binding |
| [ui_pipeline.md](ui_pipeline.md) | Slate/UMG 렌더 흐름 — FEngineLoop 틱, DrawPrepass/OnPaint 두 단계 Pass, TakeWidget 브릿지 |
