# Cue Manager & 차단

> **GASDoc**: 4.8.5~6 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gc-manager"></a>
#### 4.8.5 GameplayCueManager

기본적으로 `GameplayCueManager`는 플레이 시작 시 게임 디렉토리 전체를 스캔하여 `GameplayCueNotify`를 모두 찾아 메모리에 로드한다. `DefaultGame.ini`에서 `GameplayCueManager`가 스캔하는 경로를 변경할 수 있다.

```
[/Script/GameplayAbilities.AbilitySystemGlobals]
GameplayCueNotifyPaths="/Game/GASDocumentation/Characters"
```

`GameplayCueManager`가 모든 `GameplayCueNotify`를 스캔하고 찾아내는 것 자체는 원하는 동작이지만, 플레이 시작 시 모든 것을 비동기 로드하는 것은 원하지 않을 수 있다. 이렇게 하면 레벨에서 실제로 사용되지 않는 `GameplayCueNotify`까지 포함하여 해당 오브젝트가 참조하는 모든 사운드와 파티클이 메모리에 올라간다. Paragon 같은 대형 게임에서는 수백 메가바이트에 달하는 불필요한 에셋이 메모리를 차지하고, 시작 시 렉이나 게임 프리즈를 유발할 수 있다.

이에 대한 대안으로, 시작 시 모든 `GameplayCue`를 비동기 로드하는 대신 게임 내에서 실제로 트리거될 때만 비동기 로드하는 방식이 있다. 이 방식은 불필요한 메모리 사용과 모든 `GameplayCue`를 비동기 로드하는 과정에서 발생할 수 있는 게임 하드 프리즈를 방지하는 대신, 플레이 중 특정 `GameplayCue`가 처음 트리거될 때 약간의 딜레이가 생길 수 있다. SSD에서는 이 잠재적 딜레이가 거의 없다. HDD에서는 테스트해보지 않았다. UE 에디터에서 이 옵션을 사용하면, 에디터가 파티클 시스템을 컴파일해야 하는 경우 GameplayCue를 처음 로드할 때 약간의 끊김이나 프리즈가 발생할 수 있다. 빌드에서는 파티클 시스템이 이미 컴파일되어 있으므로 문제가 없다.

먼저 `UGameplayCueManager`를 서브클래싱하고, `DefaultGame.ini`에서 `AbilitySystemGlobals` 클래스가 해당 서브클래스를 사용하도록 설정해야 한다.

```
[/Script/GameplayAbilities.AbilitySystemGlobals]
GlobalGameplayCueManagerClass="/Script/ParagonAssets.PBGameplayCueManager"
```

`UGameplayCueManager` 서브클래스에서 `ShouldAsyncLoadRuntimeObjectLibraries()`를 오버라이드한다.

```c++
virtual bool ShouldAsyncLoadRuntimeObjectLibraries() const override
{
	return false;
}
```

<a name="concepts-gc-prevention"></a>
#### 4.8.6 GameplayCue 발동 차단

때로는 `GameplayCue`가 발동되지 않도록 해야 할 때가 있다. 예를 들어 공격을 막았을 때, 데미지 `GameplayEffect`에 연결된 히트 임팩트를 재생하지 않거나 대신 다른 것을 재생하고 싶을 수 있다. 이는 `GameplayEffectExecutionCalculations` 내에서 `OutExecutionOutput.MarkGameplayCuesHandledManually()`를 호출하고, 그 다음 `Target` 또는 `Source`의 ASC에 수동으로 원하는 `GameplayCue` 이벤트를 전달함으로써 처리할 수 있다.

특정 ASC에서 어떤 `GameplayCue`도 발동되지 않도록 완전히 억제하려면 `AbilitySystemComponent->bSuppressGameplayCues = true`로 설정하면 된다.

---

