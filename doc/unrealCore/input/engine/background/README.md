# 배경 지식 — 엔진 입력 내부 구조

Enhanced Input을 사용하기 위해 반드시 알아야 하는 내용은 아니다.  
Slate 라우팅, ViewportClient 경로, 레거시 입력 처리가 어떻게 동작하는지 궁금할 때 참고한다.

| 문서 | 내용 |
|------|------|
| [01. Slate 위젯 라우팅](01_slate_routing.md) | FWidgetPath, Tunnel/Bubble 두 단계, SViewport→FSceneViewport 브릿지, 포커스/FReply |
| [02. ViewportClient → PlayerInput](02_viewport_pipeline.md) | UGameViewportClient 처리 순서, APlayerController 필터링, EventAccumulator 적재 |
| [03. 레거시 틱 처리 상세](03_legacy_tick_detail.md) | Accumulator 패턴, EvaluateKeyMapState, bDown 홀드 원리, EvaluateInputDelegates |
