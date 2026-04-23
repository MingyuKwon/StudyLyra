# GAS 디버깅

> **GASDoc**: 6 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="debugging"></a>
## 6. GAS 디버깅

GAS 관련 문제를 디버깅할 때 주로 확인하고 싶은 정보는 다음과 같다:
- Attribute의 현재 값이 무엇인가?
- 현재 어떤 GameplayTag를 보유하고 있는가?
- 현재 어떤 GameplayEffect가 적용되어 있는가?
- 어떤 GameplayAbility가 부여되어 있고, 어떤 것이 실행 중이며, 어떤 것이 활성화 차단 상태인가?

GAS는 런타임에 이 질문들에 답할 수 있는 두 가지 기술을 제공한다: `showdebug abilitysystem`과 Gameplay Debugger의 훅이다.

**팁:** 언리얼 엔진은 C++ 코드를 최적화하기 때문에 일부 함수를 디버깅하기 어려울 수 있다. Visual Studio 솔루션 구성을 `DebugGame Editor`로 설정해도 코드 추적이나 변수 검사가 어렵다면, `UE_DISABLE_OPTIMIZATION`과 `UE_ENABLE_OPTIMIZATION` 매크로(또는 CoreMiscDefines.h에 정의된 ship 변형 버전)로 해당 함수의 최적화를 일시 비활성화할 수 있다. 플러그인 코드는 소스에서 직접 빌드하지 않는 한 이 매크로를 사용할 수 없다. 인라인 함수에는 동작하지 않을 수도 있다. 디버깅이 끝나면 반드시 매크로를 제거해야 한다.

```c++
UE_DISABLE_OPTIMIZATION
void MyClass::MyFunction(int32 MyIntParameter)
{
	// My code
}
UE_ENABLE_OPTIMIZATION
```

<a name="debugging-sd"></a>
### 6.1 showdebug abilitysystem

인게임 콘솔에 `showdebug abilitysystem`을 입력한다. 이 기능은 세 개의 "페이지"로 구성되며, 모든 페이지에서 현재 보유한 GameplayTag를 표시한다. 콘솔에 `AbilitySystem.Debug.NextCategory`를 입력하면 페이지를 전환할 수 있다.

**1페이지**에서는 모든 Attribute의 CurrentValue를 표시한다.

**2페이지**에서는 현재 적용 중인 모든 Duration 및 Infinite GameplayEffect 목록을 보여주며, 스택 수, 부여하는 GameplayTag, 적용하는 Modifier가 포함된다.

**3페이지**에서는 부여된 모든 GameplayAbility 목록을 보여주며, 현재 실행 중인지 여부, 활성화 차단 여부, 현재 실행 중인 AbilityTask의 상태가 포함된다.

대상을 전환하려면(선택된 Actor는 녹색 직육면체로 표시됨) `PageUp` 키 또는 `NextDebugTarget` 콘솔 명령으로 다음 대상으로, `PageDown` 키 또는 `PreviousDebugTarget` 콘솔 명령으로 이전 대상으로 이동한다.

**주의:** 현재 선택된 debug Actor에 따라 Ability System 정보가 갱신되려면, `DefaultGame.ini`의 AbilitySystemGlobals 설정에 다음을 추가해야 한다:
```
[/Script/GameplayAbilities.AbilitySystemGlobals]
bUseDebugTargetFromHud=true
```

**주의:** `showdebug abilitysystem`이 정상 동작하려면 GameMode에 실제 HUD 클래스가 설정되어 있어야 한다. HUD 클래스가 없으면 명령을 찾지 못해 "Unknown Command"가 반환된다.

<a name="debugging-gd"></a>
### 6.2 Gameplay Debugger

Apostrophe(`'`) 키로 Gameplay Debugger를 열고, 넘패드 `3`을 눌러 Abilities 카테고리를 활성화한다. 플러그인 구성에 따라 키가 다를 수 있으며, 넘패드가 없는 노트북 키보드라면 프로젝트 설정에서 키 바인딩을 변경할 수 있다.

**다른 캐릭터**의 GameplayTag, GameplayEffect, GameplayAbility를 확인하고 싶을 때 유용하다. 단, 대상의 Attribute CurrentValue는 표시되지 않는다. 화면 중앙에 위치한 캐릭터가 자동으로 대상이 되며, 에디터의 World Outliner에서 선택하거나 다른 캐릭터를 바라보며 Apostrophe(`'`)를 다시 누르면 대상을 변경할 수 있다. 현재 검사 중인 캐릭터 머리 위에는 가장 큰 빨간 원이 표시된다.

<a name="debugging-log"></a>
### 6.3 GAS 로그

GAS 소스 코드에는 다양한 verbosity 레벨로 `ABILITY_LOG()` 형태의 로그 구문이 삽입되어 있다. 기본 verbosity 레벨은 `Display`이며, 그보다 높은 레벨은 기본적으로 콘솔에 표시되지 않는다.

로그 카테고리의 verbosity 레벨을 변경하려면 콘솔에 다음을 입력한다:

```
log [category] [verbosity]
```

예를 들어 `ABILITY_LOG()` 구문을 활성화하려면 콘솔에 다음과 같이 입력한다:
```
log LogAbilitySystem VeryVerbose
```

기본값으로 되돌리려면:
```
log LogAbilitySystem Display
```

모든 로그 카테고리를 표시하려면:
```
log list
```

주요 GAS 관련 로그 카테고리:

| 로그 카테고리 | 기본 Verbosity |
| ----------- | -------------- |
| LogAbilitySystem | Display |
| LogAbilitySystemComponent | Log |
| LogGameplayCueDetails | Log |
| LogGameplayCueTranslator | Display |
| LogGameplayEffectDetails | Log |
| LogGameplayEffects | Display |
| LogGameplayTags | Log |
| LogGameplayTasks | Log |
| VLogAbilitySystem | Display |

자세한 내용은 [Wiki의 로깅 문서](https://unrealcommunity.wiki/logging-lgpidy6i)를 참조한다.

---

## 내 분석
