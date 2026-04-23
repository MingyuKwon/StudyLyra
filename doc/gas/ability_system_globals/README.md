# Ability System Globals (4.9)

> **GASDoc**: 4.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-asg"></a>
### 4.9 Ability System Globals

[`AbilitySystemGlobals`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UAbilitySystemGlobals/index.html) 클래스는 GAS에 관한 전역 정보를 보관한다. 대부분의 변수는 `DefaultGame.ini`에서 설정할 수 있다. 일반적으로 이 클래스를 직접 다룰 일은 없지만, 그 존재는 반드시 알고 있어야 한다. [`GameplayCueManager`](#concepts-gc-manager)나 [`GameplayEffectContext`](#concepts-ge-context)를 서브클래싱해야 할 경우, 반드시 `AbilitySystemGlobals`를 통해야 한다.

`AbilitySystemGlobals`를 서브클래싱하려면 `DefaultGame.ini`에 클래스 이름을 지정한다:

```
[/Script/GameplayAbilities.AbilitySystemGlobals]
AbilitySystemGlobalsClassName="/Script/ParagonAssets.PAAbilitySystemGlobals"
```

<a name="concepts-asg-initglobaldata"></a>
#### 4.9.1 InitGlobalData()

UE 4.24에서 5.2 사이에서는 [`TargetData`](#concepts-targeting-data)를 사용하기 위해 반드시 `UAbilitySystemGlobals::Get().InitGlobalData()`를 호출해야 한다. 이를 호출하지 않으면 `ScriptStructCache` 관련 오류가 발생하고 클라이언트가 서버에서 끊긴다. 이 함수는 프로젝트 내에서 단 한 번만 호출하면 된다. Fortnite는 `UAssetManager::StartInitialLoading()`에서, Paragon은 `UEngine::Init()`에서 호출한다. 샘플 프로젝트에서 보여주듯 `UAssetManager::StartInitialLoading()`에 두는 것이 좋은 위치다. `TargetData` 관련 문제를 방지하기 위해 프로젝트에 반드시 복사해야 하는 보일러플레이트 코드로 간주한다. **UE 5.3부터는 자동으로 호출**된다.

`AbilitySystemGlobals`의 `GlobalAttributeSetDefaultsTableNames`를 사용하는 도중 크래시가 발생한다면, Fortnite처럼 `AssetManager` 또는 `GameInstance`에서 더 늦게 `UAbilitySystemGlobals::Get().InitGlobalData()`를 호출해야 할 수 있다.

---

## 내 분석
