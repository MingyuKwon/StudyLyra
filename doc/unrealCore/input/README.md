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

> 상세 인덱스: [engine/README.md](engine/README.md)

| 문서 | 내용 |
|------|------|
| [01. Enhanced Input](engine/01_enhanced_input.md) | Subsystem vs Component 역할 분리, IMC, BindAction 오버로드 3종 |
| [02. InputPreProcessor](engine/02_preprocessor.md) | Enhanced Input이 IInputProcessor를 구현하는 이유, 커스텀 PreProcessor 패턴 |
| [03. 틱 처리 · GAS 연결](engine/03_tick_and_gas.md) | PostProcessInput → ProcessAbilityInput, bDown 홀드 유지, BuildInputStack |
| [04. 게임패드](engine/04_gamepad.md) | 디지털/아날로그 분기, FSlateApplication 진입 경로, 데드존, 진동 |
| [05. 레거시 vs Enhanced Input](engine/05_legacy_vs_enhanced.md) | 두 구조 비교, UPlayerInput이 여전히 살아있는 이유, 공존 방식 |
| [배경 지식](engine/background/README.md) | Slate 라우팅, ViewportClient 경로, 레거시 입력 처리 상세 |

---

## lyra/ — Lyra 입력 구현

| 문서 | 내용 |
|------|------|
| [개요](lyra/README.md) | 전체 흐름 다이어그램, Ability/Native 경로 비교, AbilitySpecInputPressed 상세 |
| [01. 데이터 에셋](lyra/01_data_assets.md) | LyraInputConfig, FLyraInputAction, NativeInputActions vs AbilityInputActions, GameplayTag-AbilitySpec 연결 원리 |
| [02. 초기화 흐름](lyra/02_initialization.md) | HeroComponent InitState 단계, InitializePlayerInput(), IMC 등록, BindAbilityActions/BindNativeAction |
| [03. Ability 입력 경로](lyra/03_ability_input.md) | AbilityInputTagPressed → InputPressedSpecHandles → ProcessAbilityInput, 3개 배열 생명주기, InputBlocked 태그 |
| [04. Native 입력 경로](lyra/04_native_input.md) | Input_Move/LookMouse/LookStick/Crouch/AutoRun 구현, 마우스 vs 스틱 차이 |

