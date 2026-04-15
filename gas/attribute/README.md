# Attribute & AttributeSet

GAS의 Attribute 시스템에 관한 세부 주제 모음.

---

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. Attribute 타입 구분](01_attribute_types.md) | `FGameplayAttribute` vs `FGameplayAttributeData` 역할과 관계 |
| [02. BaseValue vs CurrentValue](02_base_current_value.md) | 값 구조, GE 종류별 동작, BaseValue→CurrentValue 동기화 콜체인 |
| [03. ATTRIBUTE_ACCESSORS & Clamp](03_accessors_and_clamp.md) | 매크로가 생성하는 함수, 클램프 콜백 |
| [04. Meta Attribute 패턴](04_meta_attribute.md) | 임시 중간 Attribute, Damage/Healing 흐름, ExecCalc 연동 |
| [05. 파생 Attribute](05_derived_attribute.md) | AttributeBased GE, PostAttributeChange, MMC 세 가지 방법 |

---

## 참고 파일

- `Source/LyraGame/AbilitySystem/Attributes/LyraHealthSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraCombatSet.h / .cpp`
- `Source/LyraGame/AbilitySystem/Attributes/LyraAttributeSet.h`
