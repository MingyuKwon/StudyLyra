# 엔진 입력 파이프라인

언리얼 엔진 ��벨의 입력 처리를 다룬다. OS 이벤트 수신부터 PlayerInput 적재, 틱 처리, Enhanced Input, 하드웨어별 차이��지.

| 문서 | 내용 |
|------|------|
| [01. 입력 수신 경로](01_reception.md) | OS(WM_KEYDOWN) → FWindowsApplication → FSlateApplication → UGameViewportClient → PlayerInput 적재, 패드 폴링 vs 키보드 이벤트 |
| [02. InputPreProcessor](02_input_preprocessor.md) | 위젯 라우팅 이전 단계 — IInputProcessor 인터페이스, Enhanced Input이 여기 속하는 이유, true/false 반환 의미 |
| [03. FSlateApplication 위젯 라우팅](03_slate_routing.md) | FWidgetPath, Tunnel/Bubble 두 단계(��계 이유 포함), SViewport→FSceneViewport 브릿지, 포커스/FReply 가로채기 |
| [04. 틱 처리 파이프라인](04_tick_pipeline.md) | PlayerController 틱 → ProcessInputStack, Accumulator 패턴, bDown 홀드 유지 원리, BuildInputStack 우선순위 |
| [05. Enhanced Input](05_enhanced_input.md) | Subsystem vs Component 역할 분리, BindAction 오버로드 3종, FInputActionValue vs FInputActionInstance, VarTypes 태그 고�� 패턴 |
| [06. 게임패드 입력](06_gamepad.md) | 아날로그 vs 디지털, 데드존(InputModifier), 진동/햅틱, 자이로스코프, DualSense 어댑티브 트리거 |
