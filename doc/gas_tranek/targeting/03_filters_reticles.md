# Target Filter & Reticle

> **GASDoc**: 4.11.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-target-data-filters"></a>
#### TargetData 필터를 커스텀하려면 어떻게 서브클래싱하는가?

`Make GameplayTargetDataFilter`와 `Make Filter Handle` 노드를 모두 사용하면 플레이어의 `Pawn`을 필터링하거나 특정 클래스만 선택할 수 있다. 더 고급 필터링이 필요하다면 `FGameplayTargetDataFilter`를 서브클래싱하고 `FilterPassesForActor` 함수를 오버라이드한다.

```c++
USTRUCT(BlueprintType)
struct GASDOCUMENTATION_API FGDNameTargetDataFilter : public FGameplayTargetDataFilter
{
	GENERATED_BODY()

	/** Returns true if the actor passes the filter and will be targeted */
	virtual bool FilterPassesForActor(const AActor* ActorToBeFiltered) const override;
};
```

그러나 이것은 `FGameplayTargetDataFilterHandle`이 필요하기 때문에 `Wait Target Data` 노드에 직접 연결되지 않는다. 서브클래스를 받아들이는 새로운 커스텀 `Make Filter Handle`을 만들어야 한다:

```c++
FGameplayTargetDataFilterHandle UGDTargetDataFilterBlueprintLibrary::MakeGDNameFilterHandle(FGDNameTargetDataFilter Filter, AActor* FilterActor)
{
	FGameplayTargetDataFilter* NewFilter = new FGDNameTargetDataFilter(Filter);
	NewFilter->InitializeFilterContext(FilterActor);

	FGameplayTargetDataFilterHandle FilterHandle;
	FilterHandle.Filter = TSharedPtr<FGameplayTargetDataFilter>(NewFilter);
	return FilterHandle;
}
```

<a name="concepts-targeting-reticles"></a>
#### GameplayAbilityWorldReticle은 언제 스폰·파괴되며 타게팅 중 어떻게 시각화에 활용하는가?

[`AGameplayAbilityWorldReticles`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/AGameplayAbilityWorldReticle/index.html)(`Reticle`)는 `Instant`가 아닌 확인 타입의 `TargetActor`로 타게팅할 때 **누구를 타게팅하고 있는지** 시각화한다. `TargetActor`는 모든 `Reticle`의 스폰 및 파괴 수명을 관리한다. `Reticle`은 `AActor`이므로 시각적 표현을 위해 어떤 종류의 시각 컴포넌트도 사용할 수 있다. [GASShooter](https://github.com/tranek/GASShooter)에서 볼 수 있는 일반적인 구현은 `WidgetComponent`를 사용하여 화면 공간에 UMG 위젯을 표시하는 것이다(항상 플레이어의 카메라를 향한다). `Reticle`은 자신이 어떤 `AActor` 위에 있는지 알지 못하지만, 커스텀 `TargetActor`에서 그 기능을 서브클래싱하여 추가할 수 있다. `TargetActor`는 일반적으로 매 `Tick()`마다 `Reticle`의 위치를 타겟의 위치로 업데이트한다.

GASShooter는 로켓 런처의 보조 어빌리티 유도 로켓의 락온 타겟을 표시하기 위해 `Reticle`을 사용한다. 적 위의 빨간 지시자가 `Reticle`이다. 유사한 흰색 이미지는 로켓 런처의 조준선이다.

`Reticle`에는 디자이너가 Blueprint에서 구현할 수 있는 여러 `BlueprintImplementableEvent`가 있다(Blueprint에서 개발하도록 의도됨):

```c++
/** Called whenever bIsTargetValid changes value. */
UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnValidTargetChanged(bool bNewValue);

/** Called whenever bIsTargetAnActor changes value. */
UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnTargetingAnActor(bool bNewValue);

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnParametersInitialized();

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void SetReticleMaterialParamFloat(FName ParamName, float value);

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void SetReticleMaterialParamVector(FName ParamName, FVector value);
```

`Reticle`은 선택적으로 `TargetActor`가 제공하는 [`FWorldReticleParameters`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/Abilities/FWorldReticleParameters/index.html)를 구성에 사용할 수 있다. 기본 구조체는 `FVector AOEScale`이라는 변수 하나만 제공한다. 기술적으로는 이 구조체를 서브클래싱할 수 있지만, `TargetActor`는 기본 구조체만 허용한다. 기본 `TargetActor`에서 이를 서브클래싱하지 못하도록 한 것은 다소 근시안적인 설계처럼 보인다. 그러나 커스텀 `TargetActor`를 만들면 직접 커스텀 Reticle 파라미터 구조체를 제공하고 스폰 시 `AGameplayAbilityWorldReticles`의 서브클래스에 수동으로 전달할 수 있다.

`Reticle`은 기본적으로 복제되지 않지만, 다른 플레이어에게 로컬 플레이어가 누구를 타게팅하는지 보여주는 것이 게임에 의미가 있다면 복제하도록 만들 수 있다.

`Reticle`은 기본 `TargetActor`를 사용하면 현재 유효한 타겟에만 표시된다. 예를 들어 `AGameplayAbilityTargetActor_SingleLineTrace`를 사용하여 타겟을 추적하는 경우, `Reticle`은 적이 트레이스 경로 안에 직접 있을 때만 나타난다. 시선을 돌리면 적은 더 이상 유효한 타겟이 아니고 `Reticle`은 사라진다. 마지막으로 유효했던 타겟에 `Reticle`이 남아 있게 하고 싶다면, `TargetActor`를 커스텀하여 마지막으로 유효했던 타겟을 기억하고 `Reticle`을 그 위에 유지하도록 해야 한다. 이를 "persistent target"이라고 부르는데, `TargetActor`가 확인 또는 취소를 받거나, `TargetActor`가 트레이스/오버랩에서 새로운 유효 타겟을 찾거나, 타겟이 더 이상 유효하지 않을 때(파괴될 때)까지 유지된다. GASShooter는 로켓 런처의 보조 어빌리티 유도 로켓 타게팅에 persistent target을 사용한다.

---

