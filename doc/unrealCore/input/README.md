# 언리얼 입력 시스템

언리얼 엔진의 입력 파이프라인과 Lyra의 구현을 다룬다.

---

## 구조

```
input/
  engine/   ← 엔진 레벨 — 키 이벤트가 어떻게 처리되는가
  lyra/     ← Lyra 구현 — Enhanced Input + GAS 연결
```

---

## engine/ — 엔진 입력 파이프라인

| 문서 | 내용 |
|------|------|
| [00. 입력이 도달하는 원리](engine/00_how_input_arrives.md) | OS(WM_KEYDOWN) → FWindowsApplication → FSlateApplication → UGameViewportClient → PlayerController → UPlayerInput, 패드 폴링 vs 키보드 이벤트 |
| [01. 엔진 입력 파이프라인](engine/01_pipeline.md) | PlayerController 틱 → ProcessInputStack, Accumulator 패턴, bDown 홀드 유지 원리, BuildInputStack 우선순위 |
| [02. Enhanced Input](engine/02_enhanced_input.md) | Subsystem vs Component 역할 분리, BindAction 오버로드 3종, FInputActionValue vs FInputActionInstance, VarTypes 태그 고정 패턴 |
| [03. 패드(게임패드) 입력](engine/03_gamepad.md) | 아날로그 vs 디지털, 데드존(InputModifier), 진동/햅틱, 자이로스코프, 터치패드, DualSense 어댑티브 트리거, PS 버튼 명칭 혼란 |

---

## lyra/ — Lyra 입력 구현

| 문서 | 내용 |
|------|------|
| [개요](lyra/README.md) | 전체 흐름 다이어그램, Ability/Native 경로 비교, AbilitySpecInputPressed 상세 |
| [01. 데이터 에셋](lyra/01_data_assets.md) | LyraInputConfig, FLyraInputAction, NativeInputActions vs AbilityInputActions, GameplayTag-AbilitySpec 연결 원리 |
| [02. 초기화 흐름](lyra/02_initialization.md) | HeroComponent InitState 단계, InitializePlayerInput(), IMC 등록, BindAbilityActions/BindNativeAction |
| [03. Ability 입력 경로](lyra/03_ability_input.md) | AbilityInputTagPressed → InputPressedSpecHandles → ProcessAbilityInput, 3개 배열 생명주기, InputBlocked 태그 |
| [04. Native 입력 경로](lyra/04_native_input.md) | Input_Move/LookMouse/LookStick/Crouch/AutoRun 구현, 마우스 vs 스틱 차이 |

