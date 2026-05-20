# Ability System Globals (4.9)

> **GASDoc**: 4.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-asg"></a>
### AbilitySystemGlobals는 어떤 역할을 하며 서브클래싱이 필요한 경우는 언제인가?

[`AbilitySystemGlobals`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/UAbilitySystemGlobals/index.html) 클래스는 GAS에 관한 전역 정보를 보관한다. 대부분의 변수는 `DefaultGame.ini`에서 설정할 수 있다. 일반적으로 이 클래스를 직접 다룰 일은 없지만, 그 존재는 반드시 알고 있어야 한다. `GameplayCueManager`나 `GameplayEffectContext`를 서브클래싱해야 할 경우, 반드시 `AbilitySystemGlobals`를 통해야 한다.

`AbilitySystemGlobals`를 서브클래싱하려면 `DefaultGame.ini`에 클래스 이름을 지정한다:

```
[/Script/GameplayAbilities.AbilitySystemGlobals]
AbilitySystemGlobalsClassName="/Script/ParagonAssets.PAAbilitySystemGlobals"
```

<a name="concepts-asg-initglobaldata"></a>
#### InitGlobalData()는 왜 반드시 호출해야 하며 UE 버전별 요구사항은 어떻게 다른가?

UE 4.24에서 5.2 사이에서는 `TargetData`를 사용하기 위해 반드시 `UAbilitySystemGlobals::Get().InitGlobalData()`를 호출해야 한다. 이를 호출하지 않으면 `ScriptStructCache` 관련 오류가 발생하고 클라이언트가 서버에서 끊긴다. 이 함수는 프로젝트 내에서 단 한 번만 호출하면 된다. Fortnite는 `UAssetManager::StartInitialLoading()`에서, Paragon은 `UEngine::Init()`에서 호출한다. 샘플 프로젝트에서 보여주듯 `UAssetManager::StartInitialLoading()`에 두는 것이 좋은 위치다. `TargetData` 관련 문제를 방지하기 위해 프로젝트에 반드시 복사해야 하는 보일러플레이트 코드로 간주한다. **UE 5.3부터는 자동으로 호출**된다.

`AbilitySystemGlobals`의 `GlobalAttributeSetDefaultsTableNames`를 사용하는 도중 크래시가 발생한다면, Fortnite처럼 `AssetManager` 또는 `GameInstance`에서 더 늦게 `UAbilitySystemGlobals::Get().InitGlobalData()`를 호출해야 할 수 있다.

---

### AbilitySystemGlobals가 GAS에서 수행하는 세 가지 핵심 역할은 무엇인가?

**출처**: `Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AbilitySystemGlobals.h`  
**출처**: `Source/LyraGame/AbilitySystem/LyraAbilitySystemGlobals.cpp`

#### 커스텀 EffectContext나 ActorInfo 타입을 GAS 내부에 주입하려면 AbilitySystemGlobals에서 무엇을 오버라이드해야 하는가?

GAS 내부는 `FGameplayEffectContext`, `FGameplayAbilityActorInfo` 같은 구조체를 전부 가상함수(`AllocXxx`)를 통해 `new`로 할당한다. 프로젝트 전용 서브클래스로 교체하려면 이 팩토리 함수들을 오버라이드할 창구가 필요한데, 그게 `AbilitySystemGlobals`다.

```cpp
// 오버라이드 대상 가상함수들
virtual FGameplayEffectContext* AllocGameplayEffectContext() const;
virtual FGameplayAbilityActorInfo* AllocAbilityActorInfo() const;
virtual UGameplayCueManager* GetGameplayCueManager();
virtual void GlobalPreGameplayEffectSpecApply(FGameplayEffectSpec&, UAbilitySystemComponent*);
```

Lyra가 실제로 사용하는 방식:

```cpp
// LyraAbilitySystemGlobals.cpp — 딱 하나만 오버라이드
FGameplayEffectContext* ULyraAbilitySystemGlobals::AllocGameplayEffectContext() const
{
    return new FLyraGameplayEffectContext();
    // GAS 내부에서 EffectContext를 new할 때마다 Lyra 전용 타입이 반환됨
}
```

`FLyraGameplayEffectContext`는 `CartridgeID`(어떤 탄약 데이터로 히트했는지) 등 Lyra 전용 데이터를 담으며, ExecCalc / TargetData 콜백에서 캐스트해 꺼낸다.

#### AbilitySystemGlobals는 GAS의 어떤 공유 리소스에 대한 접근 허브 역할을 하는가?

```cpp
GetGameplayCueManager()       // GameplayCue 싱글톤
GetGlobalCurveTable()         // ScalableFloat에 쓰는 전역 CurveTable
GetGameplayTagResponseTable() // 태그 반응 테이블
TargetDataStructCache         // TargetData 네트워크 직렬화 캐시
EffectContextStructCache      // EffectContext 네트워크 직렬화 캐시
```

#### GA 활성화 실패 시 AbilitySystemGlobals가 관리하는 전역 실패 태그는 어떤 것들인가?

```cpp
ActivateFailCooldownTag     // GA 쿨다운 실패
ActivateFailCostTag         // GA 비용 실패
ActivateFailTagsBlockedTag  // 태그 차단 실패
ActivateFailTagsMissingTag  // 필수 태그 누락
ActivateFailNetworkingTag   // 네트워크 설정 오류
```

---

### 코드에서 AbilitySystemGlobals 싱글톤에 접근하는 방법은?

```cpp
// 어디서나 이 한 줄로 접근
UAbilitySystemGlobals& Globals = UAbilitySystemGlobals::Get();
```

내부 구현:

```cpp
static UAbilitySystemGlobals& Get()
{
    return *IGameplayAbilitiesModule::Get().GetAbilitySystemGlobals();
}
```

`IGameplayAbilitiesModule` 모듈 싱글톤 → 거기서 Globals 인스턴스 반환. 게임 전체에서 하나의 인스턴스를 공유한다.

---

### 커스텀 AbilitySystemGlobals 서브클래스를 UE 버전에 따라 어떻게 등록하는가?

**UE 5.4 이하** — `DefaultGame.ini`:
```ini
[/Script/GameplayAbilities.AbilitySystemGlobals]
AbilitySystemGlobalsClassName="/Script/LyraGame.LyraAbilitySystemGlobals"
```

**UE 5.5+** — Project Settings → Gameplay Abilities Settings UI에서 설정.  
(5.5에서 config 변수 대부분이 `UGameplayAbilitiesDeveloperSettings`로 이동됨)

---

### InitGlobalData()를 호출하지 않으면 어떤 문제가 발생하며 버전별 차이는?

- **UE 5.2 이하**: `TargetData` 사용 시 `UAbilitySystemGlobals::Get().InitGlobalData()`를 수동 호출해야 함. 미호출 시 `ScriptStructCache` 오류로 클라이언트 연결 끊김.
- **UE 5.3+**: 자동 호출되므로 신경 쓸 필요 없음.
- 내부적으로 `InitTargetDataScriptStructCache()`를 호출해 TargetData 복제에 필요한 구조체 캐시를 초기화한다.
