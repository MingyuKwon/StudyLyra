# GAS 디버그 명령어

> 출처: `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemComponent.cpp`  
>        `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemDebugHUD.cpp`  
>        `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/AbilitySystemCheatManagerExtension.cpp`

---

## showdebug abilitysystem — 기본 디버그 HUD

```
showdebug abilitysystem
```

화면에 GAS 상태를 오버레이로 출력한다. 카테고리를 순환하며 다른 정보를 볼 수 있다.

| 카테고리 | 출력 내용 |
|----------|-----------|
| Abilities | 활성/비활성 GA 목록, 쿨다운 상태 |
| Attributes | AttributeSet 값 전체 |
| GameplayEffects | 현재 적용 중인 GE 목록 |
| Tags | ASC에 부여된 GameplayTag 전체 |

---

## AbilitySystem.Debug.* — 카테고리 제어

```cpp
// AbilitySystemComponent.cpp:2454
FAutoConsoleCommandWithWorld AbilitySystemDebugNextCategoryCmd(
    TEXT("AbilitySystem.Debug.NextCategory"),
    TEXT("Switches to the next ShowDebug AbilitySystem category"),
    FConsoleCommandWithWorldDelegate::CreateStatic(CycleDebugCategory)
);

FAutoConsoleCommandWithWorldAndArgs AbilitySystemDebugSetCategoryCmd(
    TEXT("AbilitySystem.Debug.SetCategory"),
    ...
);
```

| 명령어 | 동작 |
|--------|------|
| `AbilitySystem.Debug.NextCategory` | 다음 카테고리로 순환 |
| `AbilitySystem.Debug.SetCategory Abilities` | 특정 카테고리로 이동 |

---

## AbilitySystem.Debug* — 시각 디버그 명령어

```cpp
// AbilitySystemDebugHUD.cpp
TAutoConsoleVariable<float> AbilitySystemDebugDrawMaxDistance(
    TEXT("AbilitySystem.DebugDrawMaxDistance"), ...);

FAutoConsoleCommandWithWorldAndArgs AbilitySystemDebugAbilityTagsCmd(
    TEXT("AbilitySystem.DebugAbilityTags"),
    TEXT("Usage: AbilitySystem.DebugAbilityTags [TagName]...\n"
         "Toggles Drawing Ability Tags on Actors with ASC"),
    ...);

FAutoConsoleCommandWithWorldAndArgs AbilitySystemDebugAttributeCmd(
    TEXT("AbilitySystem.DebugAttribute"),
    TEXT("Usage: AbilitySystem.DebugAttribute [AttributeName]...\n"
         "Toggles Drawing the given attributes on Actors with ASC"),
    ...);
```

| 명령어 | 동작 |
|--------|------|
| `AbilitySystem.DebugAbilityTags [TagName]` | 지정 Tag를 가진 Actor에 태그 표시 (생략 시 전체) |
| `AbilitySystem.DebugAttribute [AttrName]` | 지정 Attribute를 Actor 위에 표시 |
| `AbilitySystem.DebugBasicHUD` | 기본 HUD 토글 |
| `AbilitySystem.DebugBlockedAbilityTags` | 차단된 Ability 태그 표시 |
| `AbilitySystem.DebugIncludeModifiers` | Attribute 표시 시 Modifier 포함 여부 토글 |
| `AbilitySystem.DebugDrawMaxDistance <float>` | 디버그 그리기 최대 거리 설정 |

---

## CheatManager Exec — 치트 명령어

`AbilitySystemCheatManagerExtension`이 `UCheatManager`에 붙어서 Exec 명령어를 처리한다.

```cpp
// AbilitySystemCheatManagerExtension.cpp
const bool bSuccess = CheatManager->ProcessConsoleExec(*Cmd, OutputDevice, PCPawn);
```

---

## 디버그 타깃 선택 원리

`showdebug abilitysystem` 출력 대상은 `FASCDebugTargetInfo`가 결정한다.

```cpp
// AbilitySystemComponent.cpp:2434
for (TObjectIterator<UAbilitySystemComponent> It; It; ++It)
{
    if (ASC->GetWorld() == Info->TargetWorld.Get())
    {
        Info->LastDebugTarget = ASC;
        if (ASC->AbilityActorInfo != nullptr && ASC->AbilityActorInfo->IsLocallyControlledPlayer())
            break;  // 로컬 플레이어 우선
    }
}
```

World 내 모든 ASC를 순회해 로컬 플레이어 소유를 우선 선택한다.

---

## 유용한 GAS 관련 CVar 모음

| CVar | 타입 | 용도 |
|------|------|------|
| `AbilitySystem.DebugDrawMaxDistance` | float | 디버그 드로우 최대 거리 |
| `AbilitySystem.DebugMoveToActorForce` | (CVar) | MoveToActor RootMotion 디버그 |
| `AbilitySystem.DebugBasicHUD` | (CCmd) | 기본 HUD 표시 토글 |
