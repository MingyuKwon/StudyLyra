# Lyra 구현 분석

Lyra 소스 코드 기반으로 실제 구현을 분석한 문서 모음.

| 폴더/파일 | 내용 |
|-----------|------|
| [input/](../unrealCore/input/lyra/README.md) | 입력 수신부터 Ability 활성화까지 전체 흐름 |
| [experience.md](experience.md) | Experience 선택 → GameFeature 활성화 → Action 실행 전체 흐름 |
| [gas/](gas/README.md) | Lyra의 GAS 확장 구현 — ASC 소유 구조, AbilitySet, GA, 태그 시스템, 게임 페이즈 |
| [camera/](camera/README.md) | 카메라 시스템 — CameraMode 오브젝트, 블렌드 스택, DetermineCameraModeDelegate |
| [prediction/](prediction/README.md) | 히트스캔 Prediction — 클라 로컬 트레이스, TargetData RPC 전송, 히트마커 확인 시스템 |
