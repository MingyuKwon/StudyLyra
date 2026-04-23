# GAS 소개 & 셋업

> **GASDoc**: 1~3 · [원문 참조](cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="intro"></a>
## 1. GameplayAbilitySystem 플러그인 소개

[공식 문서](https://docs.unrealengine.com/en-US/Gameplay/GameplayAbilitySystem/index.html)에서 인용:
> Gameplay Ability System은 RPG나 MOBA 타이틀에서 볼 수 있는 어빌리티와 Attribute를 구축하기 위한 고유연성 프레임워크입니다. 게임 캐릭터가 사용할 액티브/패시브 어빌리티를 만들고, 이러한 액션의 결과로 다양한 Attribute를 올리거나 내리는 상태 효과를 구현하며, "쿨다운" 타이머나 자원 비용으로 액션 사용을 제한하고, 레벨별로 어빌리티와 효과의 수치를 조정하고, 파티클이나 사운드 이펙트를 활성화하는 등 다양한 작업을 할 수 있습니다. 간단히 말해, 이 시스템은 점프처럼 단순한 것부터 현대 RPG/MOBA의 복잡한 캐릭터 어빌리티 세트에 이르기까지, 게임 내 어빌리티를 설계하고 구현하며 효율적으로 네트워킹하는 데 도움을 줄 수 있습니다.

GameplayAbilitySystem 플러그인은 Epic Games가 개발하여 언리얼 엔진과 함께 제공된다. Paragon, Fortnite 등 AAA 상업 게임에서 실전 검증을 마쳤다.

이 플러그인은 싱글·멀티플레이어 게임 모두에서 다음 기능을 즉시 사용할 수 있게 해준다:
* 선택적 비용 및 쿨다운을 지원하는 레벨 기반 캐릭터 어빌리티 또는 스킬 구현 ([GameplayAbilities](#concepts-ga))
* 액터가 소유한 수치형 `Attribute` 조작 ([Attributes](#concepts-a))
* 액터에 상태 효과 적용 ([GameplayEffects](#concepts-ge))
* 액터에 `GameplayTag` 적용 ([GameplayTags](#concepts-gt))
* 시각 또는 사운드 이펙트 스폰 ([GameplayCues](#concepts-gc))
* 위에서 언급한 모든 것의 네트워크 복제

멀티플레이어 게임에서 GAS는 다음 항목에 대한 [클라이언트 사이드 예측](#concepts-p)을 지원한다:
* 어빌리티 활성화
* 애니메이션 몽타주 재생
* `Attribute` 변경
* `GameplayTag` 적용
* `GameplayCue` 스폰
* `CharacterMovementComponent`에 연결된 `RootMotionSource` 함수를 통한 이동

**GAS는 반드시 C++에서 설정해야 한다.** `GameplayAbilities`와 `GameplayEffects`는 디자이너가 블루프린트로 제작할 수 있다.

GAS의 현재 알려진 문제점:
* `GameplayEffect` 레이턴시 보정 불가 (어빌리티 쿨다운을 예측할 수 없어, 쿨다운이 짧은 어빌리티의 경우 레이턴시가 높은 플레이어가 낮은 플레이어보다 발사 속도가 느려진다).
* `GameplayEffect` 제거를 예측할 수 없다. 반대 효과를 가진 `GameplayEffect`를 추가하는 방식으로 사실상 제거하는 예측은 가능하지만, 항상 적절하거나 실현 가능하지는 않으며 여전히 문제로 남아 있다.
* 보일러플레이트 템플릿, 멀티플레이어 예제, 문서 부족. 이 문서가 그 부분에 도움이 되길 바란다!

**[⬆ Back to Top](#table-of-contents)**

<a name="sp"></a>
## 2. 샘플 프로젝트

이 문서와 함께 멀티플레이어 3인칭 슈터 샘플 프로젝트가 제공된다. GameplayAbilitySystem 플러그인을 처음 접하지만 언리얼 엔진 자체는 익숙한 사람을 대상으로 한다. C++, 블루프린트, UMG, 리플리케이션, 그 외 UE 중급 주제에 대한 사전 지식을 갖추고 있다고 가정한다. 이 프로젝트는 플레이어/AI 제어 영웅용으로 `PlayerState` 클래스에, AI 제어 미니언용으로 `Character` 클래스에 `AbilitySystemComponent`(`ASC`)를 배치하는 기본 3인칭 슈터 멀티플레이어 프로젝트 설정 방법을 예시로 보여준다.

이 프로젝트의 목표는 GAS 기초를 보여주고 잘 주석 처리된 코드로 자주 요청되는 어빌리티들을 시연하면서도 단순하게 유지하는 것이다. 입문자를 대상으로 하기 때문에 [투사체 예측](#concepts-p-spawn)과 같은 고급 주제는 다루지 않는다.

시연하는 개념들:
* `PlayerState` vs `Character`에 배치하는 `ASC`
* 복제되는 `Attribute`
* 복제되는 애니메이션 몽타주
* `GameplayTag`
* `GameplayAbilities` 내부 및 외부에서 `GameplayEffect` 적용 및 제거
* 방어구로 감소시킨 데미지를 캐릭터 체력에 반영
* `GameplayEffectExecutionCalculations`
* 스턴 효과
* 사망과 리스폰
* 서버에서 어빌리티로 액터(투사체) 스폰
* 조준 사격(Aim Down Sights)과 달리기에서 로컬 플레이어 속도를 예측적으로 변경
* 달리기 시 스태미나 지속 소모
* 마나를 소모하여 어빌리티 시전
* 패시브 어빌리티
* 중첩(Stacking) `GameplayEffect`
* 액터 타겟팅
* 블루프린트로 제작된 `GameplayAbility`
* C++로 제작된 `GameplayAbility`
* `Actor` 단위로 인스턴싱된 `GameplayAbility`
* 비인스턴싱 `GameplayAbility` (점프)
* 정적 `GameplayCue` (총기 투사체 충돌 파티클 이펙트)
* 액터 `GameplayCue` (달리기 및 스턴 파티클 이펙트)

영웅 클래스가 보유한 어빌리티:

| 어빌리티 | 입력 바인딩 | 예측 | C++ / Blueprint | 설명 |
| -------- | ----------- | ---- | --------------- | ---- |
| Jump | Space Bar | 예 | C++ | 영웅을 점프시킨다. |
| Gun | Left Mouse Button | 아니오 | C++ | 영웅의 총에서 투사체를 발사한다. 애니메이션은 예측되지만 투사체는 예측되지 않는다. |
| Aim Down Sights | Right Mouse Button | 예 | Blueprint | 버튼을 누르고 있는 동안 영웅이 더 느리게 걷고 카메라가 줌인되어 총으로 더 정밀하게 조준할 수 있다. |
| Sprint | Left Shift | 예 | Blueprint | 버튼을 누르고 있는 동안 영웅이 스태미나를 소모하며 더 빠르게 달린다. |
| Forward Dash | Q | 예 | Blueprint | 스태미나를 소모하며 전방으로 돌진한다. |
| Passive Armor Stacks | Passive | 아니오 | Blueprint | 4초마다 방어구 스택을 최대 4스택까지 획득한다. 피해를 받으면 방어구 스택 하나가 제거된다. |
| Meteor | R | 아니오 | Blueprint | 플레이어가 위치를 타겟으로 지정하여 적에게 운석을 떨어뜨려 피해와 스턴을 가한다. 타겟팅은 예측되지만 운석 스폰은 예측되지 않는다. |

`GameplayAbility`를 C++로 만드는지 블루프린트로 만드는지는 중요하지 않다. 여기서는 두 언어에서 각각 어떻게 구현하는지 예시를 보여주기 위해 혼합하여 사용했다.

미니언에는 미리 정의된 `GameplayAbility`가 없다. 빨간 미니언은 체력 재생이 더 높고, 파란 미니언은 초기 체력이 더 높다.

`GameplayAbility` 명명 규칙으로, `GameplayAbility`의 로직이 블루프린트로 제작되었을 때는 `_BP` 접미사를 사용한다. 접미사가 없으면 로직이 C++로 제작된 것이다.

**블루프린트 에셋 명명 접두사**

| 접두사 | 에셋 타입 |
| ------ | --------- |
| GA_ | GameplayAbility |
| GC_ | GameplayCue |
| GE_ | GameplayEffect |

**[⬆ Back to Top](#table-of-contents)**

<a name="setup"></a>
## 3. GAS를 사용하는 프로젝트 설정

GAS를 사용하는 프로젝트를 설정하는 기본 단계:
1. 에디터에서 GameplayAbilitySystem 플러그인 활성화
1. `YourProjectName.Build.cs`를 편집하여 `PrivateDependencyModuleNames`에 `"GameplayAbilities", "GameplayTags", "GameplayTasks"` 추가
1. Visual Studio 프로젝트 파일 새로 고침/재생성
1. 4.24부터 5.2까지는 [`TargetData`](#concepts-targeting-data)를 사용하기 위해 `UAbilitySystemGlobals::Get().InitGlobalData()`를 반드시 호출해야 한다. 샘플 프로젝트는 `UAssetManager::StartInitialLoading()`에서 이를 호출한다. 5.3부터는 자동으로 호출된다. 자세한 내용은 [`InitGlobalData()`](#concepts-asg-initglobaldata)를 참조.

GAS를 활성화하기 위해 해야 할 일은 이것이 전부다. 이제 `Character` 또는 `PlayerState`에 [`ASC`](#concepts-asc)와 [`AttributeSet`](#concepts-as)을 추가하고 [`GameplayAbility`](#concepts-ga)와 [`GameplayEffect`](#concepts-ge)를 만들기 시작하면 된다!

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
