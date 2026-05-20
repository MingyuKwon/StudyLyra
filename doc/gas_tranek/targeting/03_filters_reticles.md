# Target Filter & Reticle

> **GASDoc**: 4.11.3~4 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-target-data-filters"></a>
#### TargetData 필터를 커스텀하려면 어떻게 서브클래싱하는가?

기본 필터는 `Make GameplayTargetDataFilter`와 `Make Filter Handle` 노드로 플레이어 Pawn 필터링이나 특정 클래스 선택이 가능하다. 더 세밀한 필터링이 필요하면 `FGameplayTargetDataFilter`를 서브클래싱하고 `FilterPassesForActor()`를 오버라이드한다:

```c++
USTRUCT(BlueprintType)
struct GASDOCUMENTATION_API FGDNameTargetDataFilter : public FGameplayTargetDataFilter
{
    GENERATED_BODY()

    virtual bool FilterPassesForActor(const AActor* ActorToBeFiltered) const override;
};
```

서브클래스는 `FGameplayTargetDataFilterHandle`이 필요하므로 `Wait Target Data` 노드에 직접 연결되지 않는다. 서브클래스를 받아들이는 커스텀 `Make Filter Handle` 함수를 따로 만들어야 한다:

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

`AGameplayAbilityWorldReticle`(`Reticle`)은 `Instant`가 아닌 확인 타입의 TargetActor로 타게팅할 때 현재 타겟을 시각화하는 Actor다. TargetActor가 Reticle의 스폰·파괴 수명을 관리하며, 매 `Tick()`마다 Reticle 위치를 타겟 위치로 업데이트한다.

일반적인 구현은 `WidgetComponent`를 사용해 화면 공간에 UMG 위젯을 표시하는 방식이다. Blueprint에서 구현할 수 있는 `BlueprintImplementableEvent`들이 제공된다:

```c++
UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnValidTargetChanged(bool bNewValue);    // 유효 타겟 여부 변경 시

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnTargetingAnActor(bool bNewValue);      // Actor 타게팅 여부 변경 시

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void OnParametersInitialized();

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void SetReticleMaterialParamFloat(FName ParamName, float value);

UFUNCTION(BlueprintImplementableEvent, Category = Reticle)
void SetReticleMaterialParamVector(FName ParamName, FVector value);
```

Reticle은 기본적으로 현재 유효한 타겟에만 표시된다. 시선을 돌려 타겟이 트레이스 범위를 벗어나면 Reticle이 사라진다. 마지막으로 유효했던 타겟에 Reticle을 유지하는 "persistent target" 기능이 필요하면 TargetActor를 커스텀해야 한다.

Reticle은 기본적으로 복제되지 않는다. 다른 플레이어에게 타게팅 대상을 보여줄 필요가 있다면 복제하도록 만들 수 있다.

`FWorldReticleParameters`는 구성 파라미터 구조체로 기본적으로 `FVector AOEScale` 하나만 제공한다. 기술적으로 서브클래싱이 가능하지만, 기본 TargetActor는 기본 구조체만 허용한다. 커스텀 TargetActor를 만들면 커스텀 Reticle 파라미터 구조체를 스폰 시 직접 전달할 수 있다.

---
