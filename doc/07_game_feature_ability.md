# GameFeature 기반 Ability 추가

## 개념

Lyra의 GameFeature 플러그인(ShooterCore 등)은 활성화될 때 특정 Actor에 동적으로 Ability를 부여할 수 있다.
이를 통해 게임모드별로 필요한 Ability를 코드 변경 없이 플러그인 단위로 관리할 수 있다.

## 핵심 클래스

| 클래스 | 역할 |
|--------|------|
| `GameFeatureAction_AddAbilities` | GameFeature 활성화 시 지정 Actor에 AbilitySet 부여 |
| `ULyraGameFeaturePolicy` | GameFeature 로딩 정책 관리 |

## 동작 흐름

```
Experience 로딩 완료
  └─ LyraExperienceManagerComponent가 GameFeature 플러그인 활성화 요청

GameFeature 플러그인 활성화
  └─ GameFeatureAction_AddAbilities::OnGameFeatureActivating()
        └─ 지정된 Actor 클래스를 월드에서 찾아 AbilitySet 부여
              └─ ULyraAbilitySet::GiveToAbilitySystem()

GameFeature 플러그인 비활성화
  └─ GameFeatureAction_AddAbilities::OnGameFeatureDeactivating()
        └─ FLyraAbilitySet_GrantedHandles::TakeFromAbilitySystem()
```

## Experience 시스템과의 관계

```
ULyraExperienceDefinition (DataAsset)
  ├─ GameFeaturesToEnable[]   ← 활성화할 플러그인 목록
  └─ ActionSets[]
        └─ ULyraExperienceActionSet
              └─ Actions[]    ← GameFeatureAction_AddAbilities 등
```

게임모드마다 다른 Experience를 지정함으로써 같은 Pawn에 전혀 다른 Ability 세트를 부여할 수 있다.
