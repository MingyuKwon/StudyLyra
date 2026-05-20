# GAS 소개 & 셋업

> **GASDoc**: 1~3 · [원문 참조](cache/GASDocument_Readme.md)

---

<a name="intro"></a>
## GAS 플러그인은 무엇을 제공하며 어떤 프로젝트에서 사용하는가?

Epic Games가 개발한 플러그인으로 Paragon, Fortnite에서 실전 검증됐다. 싱글·멀티플레이어 게임 모두에서 아래 기능을 제공한다.

| 기능 | 설명 |
|---|---|
| GameplayAbilities | 레벨 기반 어빌리티, 비용·쿨다운 지원 |
| Attributes | 액터가 소유하는 수치형 Attribute 조작 |
| GameplayEffects | 액터에 상태 효과 적용 |
| GameplayTags | 액터에 태그 부여 |
| GameplayCues | 시각·사운드 이펙트 스폰 |
| 네트워크 복제 | 위 모든 항목의 자동 복제 |

멀티플레이어에서 클라이언트 사이드 예측을 지원하는 항목: 어빌리티 활성화, 애니메이션 몽타주, Attribute 변경, GameplayTag, GameplayCue, RootMotionSource 이동.

**GAS는 반드시 C++에서 설정해야 한다.** GameplayAbilities와 GameplayEffects는 블루프린트로 제작 가능하다.

현재 알려진 한계:
- GE 레이턴시 보정 불가 — 쿨다운이 짧은 어빌리티에서 고핑 플레이어가 불리하다.
- GE 제거 예측 불가 — 반대 효과의 GE를 추가하는 방식으로 우회하지만 완전하지 않다.

<a name="sp"></a>
## GASDocumentation 샘플 프로젝트는 어떤 기능을 시연하는가?

GAS 기초를 실제 코드로 보여주는 멀티플레이어 3인칭 슈터 프로젝트다. PlayerState에 ASC를 배치하는 방식(플레이어·AI 영웅)과 Character에 ASC를 배치하는 방식(AI 미니언)을 함께 시연한다.

주요 시연 개념: 복제되는 Attribute/애니메이션 몽타주, GE 적용·제거, GameplayEffectExecutionCalculations, 스턴·사망·리스폰, 서버 투사체 스폰, 속도 예측, 스태미나·마나 소모, 패시브 어빌리티, 중첩 GE, 액터 타겟팅, 정적·액터 GameplayCue.

영웅 어빌리티 목록:

| 어빌리티 | 입력 | 예측 | 구현 | 설명 |
|---|---|---|---|---|
| Jump | Space Bar | 예 | C++ | 점프 |
| Gun | LMB | 아니오 | C++ | 투사체 발사 (애니메이션만 예측) |
| Aim Down Sights | RMB | 예 | Blueprint | 감속 + 줌인 |
| Sprint | LShift | 예 | Blueprint | 스태미나 소모하며 가속 |
| Forward Dash | Q | 예 | Blueprint | 스태미나 소모하며 돌진 |
| Passive Armor Stacks | Passive | 아니오 | Blueprint | 4초마다 방어구 스택 +1 (최대 4), 피격 시 -1 |
| Meteor | R | 아니오 | Blueprint | 타겟 위치에 운석 낙하 (타겟팅은 예측, 스폰은 비예측) |

블루프린트 에셋 명명 접두사: `GA_` (GameplayAbility), `GC_` (GameplayCue), `GE_` (GameplayEffect). 로직이 블루프린트로 작성된 GA는 `_BP` 접미사를 사용한다.

<a name="setup"></a>
## 새 프로젝트에서 GAS를 활성화하려면 어떤 단계를 거쳐야 하는가?

1. 에디터에서 GameplayAbilitySystem 플러그인 활성화
2. `YourProjectName.Build.cs`의 `PrivateDependencyModuleNames`에 `"GameplayAbilities", "GameplayTags", "GameplayTasks"` 추가
3. Visual Studio 프로젝트 파일 재생성
4. (4.24~5.2 한정) `UAbilitySystemGlobals::Get().InitGlobalData()`를 `UAssetManager::StartInitialLoading()`에서 호출 — 5.3부터는 자동 호출됨

이후 Character 또는 PlayerState에 ASC와 AttributeSet을 추가하면 된다.

---
