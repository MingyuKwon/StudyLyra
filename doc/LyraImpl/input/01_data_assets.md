# 데이터 에셋 — LyraInputConfig & PawnData

> 출처: `Input/LyraInputConfig.h`, `Character/LyraPawnData.h`

---

## ULyraInputConfig

`UDataAsset`을 상속한 **읽기 전용 설정 에셋**. InputAction을 GameplayTag에 매핑한다.

```cpp
UCLASS(BlueprintType, Const)
class ULyraInputConfig : public UDataAsset
{
    // 이동/시점 등 C++ 콜백으로 직접 처리하는 입력
    TArray<FLyraInputAction> NativeInputActions;

    // GA 활성화에 사용되는 입력 (자동으로 ASC에 연결됨)
    TArray<FLyraInputAction> AbilityInputActions;
};
```

### FLyraInputAction — 매핑 단위

```cpp
USTRUCT(BlueprintType)
struct FLyraInputAction
{
    TObjectPtr<const UInputAction> InputAction;  // Enhanced Input 액션 에셋
    FGameplayTag InputTag;                        // 연결할 GameplayTag
};
```

### NativeInputActions vs AbilityInputActions

| 구분 | NativeInputActions | AbilityInputActions |
|------|-------------------|---------------------|
| 처리 방식 | C++ 콜백 직접 바인딩 | ASC를 통한 GA 활성화 |
| 바인딩 함수 | `BindNativeAction()` | `BindAbilityActions()` |
| 처리 시점 | Enhanced Input 이벤트 발생 시 | 매 틱 `ProcessAbilityInput()` |
| 예시 | Move, Look, Crouch, AutoRun | 공격, 스킬, 점프 |

---

## ULyraPawnData — InputConfig 참조 경로

```cpp
// LyraPawnData.h
UCLASS()
class ULyraPawnData : public UPrimaryDataAsset
{
    TObjectPtr<ULyraInputConfig> InputConfig;  // ← 이 에셋이 사용됨
    // ...
};
```

초기화 흐름에서 `HeroComponent`가 `PawnExtensionComponent`를 통해 `PawnData`를 가져오고, 그 안의 `InputConfig`를 사용해 바인딩을 설정한다.

```
ULyraPawnExtensionComponent::GetPawnData<ULyraPawnData>()
    └─ PawnData->InputConfig  ←  LyraInputConfig 에셋
```

---

## GameplayTag와 AbilitySpec 연결 원리

`AbilityInputActions`의 Tag와 GA 쪽 Tag가 어떻게 연결되는지:

1. **GA 등록 시** (`ULyraAbilitySet::GiveToAbilitySystem`): `AbilitySpec`에 InputTag가 `DynamicSpecSourceTags`에 추가됨
2. **입력 발생 시** (`AbilityInputTagPressed`): ActivatableAbilities를 순회해 `HasTagExact(InputTag)`로 해당 Spec을 찾음
3. **처리** (`ProcessAbilityInput`): 찾은 Spec의 Handle을 `InputPressedSpecHandles`에 추가해 다음 틱에 처리

Tag가 키이고 AbilitySpec이 값인 간접 매핑 구조다.
