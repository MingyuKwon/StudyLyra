# 엔진 입력 파이프라인

언리얼 엔진 레벨의 입력 처리를 다룬다. OS 이벤트 수신부터 PlayerInput 적재, 틱 처리, Enhanced Input, 하드웨어별 차이까지.

| 문서 | 내용 |
|------|------|
| [01. 입력 수신 경로](01_reception.md) | OS(WM_KEYDOWN) → FWindowsApplication → FSlateApplication → UGameViewportClient → PlayerInput 적재, 패드 폴링 vs 키보드 이벤트 |
| [02. FSlateApplication 라우팅](02_slate_routing.md) | ProcessKeyDownEvent 내부, FWidgetPath, Tunnel/Bubble 두 단계, SViewport→FSceneViewport 브릿지, 가로채기 3메커니즘 |
| [03. 틱 처리 파이프라인](03_tick_pipeline.md) | PlayerController 틱 → ProcessInputStack, Accumulator 패턴, bDown 홀드 유지 원리, BuildInputStack 우선순위 |
| [04. Enhanced Input](04_enhanced_input.md) | Subsystem vs Component 역할 분리, BindAction 오버로드 3종, FInputActionValue vs FInputActionInstance, VarTypes 태그 고정 패턴 |
| [05. 게임패드 입력](05_gamepad.md) | 아날로그 vs 디지털, 데드존(InputModifier), 진동/햅틱, 자이로스코프, DualSense 어댑티브 트리거 |
