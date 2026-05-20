# PostGameplayEffectExecute()

> **GASDoc**: 4.4.6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-as-postgameplayeffectexecute"></a>
#### PostGameplayEffectExecute()는 언제 호출되며, PreAttributeChange()와 어떻게 역할이 나뉘는가?

`PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)`는 **Instant GE가 Attribute의 `BaseValue`를 변경한 직후**에만 호출된다.

| 함수 | 호출 시점 | 주요 용도 |
|------|-----------|-----------|
| `PreAttributeChange()` | `CurrentValue` 변경 직전 | 클램핑 |
| `PostGameplayEffectExecute()` | Instant GE로 `BaseValue` 변경 직후 | 파생 로직, 게임플레이 이벤트 |

GE로 인한 Attribute 변경 후 추가 조작에 적합하다. 샘플 프로젝트의 사용 예시:
- 피해 Meta Attribute를 Health에서 차감 (Shield가 있다면 Shield 먼저 차감)
- 피격 반응 애니메이션 재생
- 부유 피해 숫자(Floating Damage Numbers) 표시
- 처치자에게 경험치/골드 지급
- Mana, Stamina 등을 최대값 Attribute에 맞춰 클램핑

**중요**: `PostGameplayEffectExecute()` 호출 시점에 Attribute 변경은 이미 완료됐지만 아직 클라이언트에 복제되지 않은 상태다. 따라서 이 시점에 값을 클램핑해도 클라이언트에 두 번의 네트워크 업데이트가 발생하지 않는다. 클라이언트는 클램핑 이후의 최종값만 받는다.

---
