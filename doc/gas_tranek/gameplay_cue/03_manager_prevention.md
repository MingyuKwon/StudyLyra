# Cue Manager & 차단

> **GASDoc**: 4.8.5~6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-manager"></a>
#### GameplayCueManager가 시작 시 전체 에셋을 메모리에 로드하는 것이 왜 문제이며 어떻게 최적화하는가?

기본 동작으로 `GameplayCueManager`는 플레이 시작 시 게임 디렉토리 전체를 스캔해 모든 `GameplayCueNotify`를 메모리에 로드한다. 레벨에서 실제로 사용되지 않는 GameplayCueNotify까지 포함해 참조하는 모든 사운드·파티클이 올라오므로, Paragon 같은 대형 게임에서는 수백 MB의 불필요한 메모리 점유와 시작 시 프리즈를 유발한다.

**스캔 경로 제한** (`DefaultGame.ini`):
```
[/Script/GameplayAbilities.AbilitySystemGlobals]
GameplayCueNotifyPaths="/Game/GASDocumentation/Characters"
```

**필요 시점 비동기 로드로 전환**: 시작 시 일괄 로드 대신, 실제 트리거 시점에만 로드하도록 변경하면 불필요한 메모리와 프리즈를 방지한다. 단, 처음 트리거될 때 약간의 딜레이가 생길 수 있다(SSD에서는 거의 없음).

`UGameplayCueManager`를 서브클래싱하고 `DefaultGame.ini`에서 등록한다:

```
[/Script/GameplayAbilities.AbilitySystemGlobals]
GlobalGameplayCueManagerClass="/Script/ParagonAssets.PBGameplayCueManager"
```

서브클래스에서 `ShouldAsyncLoadRuntimeObjectLibraries()`를 오버라이드한다:

```c++
virtual bool ShouldAsyncLoadRuntimeObjectLibraries() const override
{
    return false;
}
```

<a name="concepts-gc-prevention"></a>
#### 특정 상황에서 GameplayCue 발동을 차단하거나 다른 Cue로 교체하려면 어떻게 해야 하는가?

**특정 GE의 Cue만 차단하고 다른 Cue로 교체**: `GameplayEffectExecutionCalculation` 내에서 `OutExecutionOutput.MarkGameplayCuesHandledManually()`를 호출한다. 이후 Target 또는 Source의 ASC에 원하는 GameplayCue 이벤트를 수동으로 전달하면 된다.

**특정 ASC에서 모든 GameplayCue를 완전히 억제**: `AbilitySystemComponent->bSuppressGameplayCues = true`로 설정한다.

---
