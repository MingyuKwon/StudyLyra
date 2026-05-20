# GAS 디버깅

> **GASDoc**: 6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="debugging"></a>
## GAS 런타임 디버깅 시 어떤 정보를 확인해야 하며 사용할 수 있는 도구는?

런타임에 확인할 핵심 정보: Attribute 현재 값, 보유 중인 GameplayTag, 적용된 GameplayEffect, 부여·실행·차단 상태인 GameplayAbility.

GAS는 이를 위해 두 가지 도구를 제공한다: `showdebug abilitysystem`과 Gameplay Debugger.

최적화로 인해 특정 함수 디버깅이 어려우면 `UE_DISABLE_OPTIMIZATION` / `UE_ENABLE_OPTIMIZATION` 매크로로 해당 함수만 최적화를 일시 해제할 수 있다.

```c++
UE_DISABLE_OPTIMIZATION
void MyClass::MyFunction(int32 MyIntParameter)
{
    // My code
}
UE_ENABLE_OPTIMIZATION
```

<a name="debugging-sd"></a>
### showdebug abilitysystem 명령으로 볼 수 있는 정보는 무엇이며 페이지마다 무엇이 표시되는가?

인게임 콘솔에 `showdebug abilitysystem` 입력. `AbilitySystem.Debug.NextCategory`로 페이지 전환.

| 페이지 | 표시 내용 |
|---|---|
| 공통 | 현재 보유한 GameplayTag 전체 |
| 1페이지 | 모든 Attribute의 CurrentValue |
| 2페이지 | 적용 중인 Duration·Infinite GE 목록 (스택 수, 부여 태그, 적용 Modifier 포함) |
| 3페이지 | 부여된 GA 목록 (실행 중·차단 여부, 현재 AbilityTask 상태 포함) |

대상 전환: `PageUp` / `NextDebugTarget` → 다음 대상, `PageDown` / `PreviousDebugTarget` → 이전 대상. 선택된 Actor는 녹색 직육면체로 표시된다.

주의사항:
- `DefaultGame.ini`에 `bUseDebugTargetFromHud=true` 추가 필요:
  ```
  [/Script/GameplayAbilities.AbilitySystemGlobals]
  bUseDebugTargetFromHud=true
  ```
- GameMode에 실제 HUD 클래스가 설정되어 있어야 한다. 없으면 "Unknown Command"가 반환된다.

<a name="debugging-gd"></a>
### Gameplay Debugger를 언제 쓰며 showdebug abilitysystem과 어떻게 다른가?

Apostrophe(`'`) 키로 열고, 넘패드 `3`으로 Abilities 카테고리 활성화.

**다른 캐릭터**의 GameplayTag·GE·GA를 확인할 때 유용하다. Attribute CurrentValue는 표시되지 않는다. 화면 중앙의 캐릭터가 자동으로 대상이 되며, 검사 중인 캐릭터 머리 위에 가장 큰 빨간 원이 표시된다.

| 항목 | showdebug abilitysystem | Gameplay Debugger |
|---|---|---|
| 대상 | 로컬 플레이어 위주 | 다른 캐릭터도 가능 |
| Attribute CurrentValue | 표시됨 | 표시 안 됨 |
| 진입 방법 | 콘솔 명령 | `'` 키 |

<a name="debugging-log"></a>
### GAS 로그 verbosity를 높여 상세 출력을 얻으려면 어떻게 해야 하는가?

콘솔에서 `log [category] [verbosity]` 형식으로 변경한다.

```
log LogAbilitySystem VeryVerbose   ← 상세 출력 활성화
log LogAbilitySystem Display       ← 기본값으로 복원
log list                           ← 전체 카테고리 목록 확인
```

주요 GAS 로그 카테고리:

| 로그 카테고리 | 기본 Verbosity |
|---|---|
| LogAbilitySystem | Display |
| LogAbilitySystemComponent | Log |
| LogGameplayCueDetails | Log |
| LogGameplayCueTranslator | Display |
| LogGameplayEffectDetails | Log |
| LogGameplayEffects | Display |
| LogGameplayTags | Log |
| LogGameplayTasks | Log |
| VLogAbilitySystem | Display |

---
