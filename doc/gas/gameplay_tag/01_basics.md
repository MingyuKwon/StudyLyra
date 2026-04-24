# GameplayTag 기초

> **GASDoc**: 4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gt"></a>
### 4.2 GameplayTag

[`FGameplayTag`](https://docs.unrealengine.com/en-US/API/Runtime/GameplayTags/FGameplayTag/index.html)는 `Parent.Child.Grandchild...` 형태의 계층적 이름으로, `GameplayTagManager`에 등록된다. 이 태그는 객체의 상태를 분류하고 기술하는 데 매우 유용하다. 예를 들어 캐릭터가 스턴 상태라면 스턴 지속 시간 동안 `State.Debuff.Stun` GameplayTag를 부여할 수 있다.

기존에 불리언이나 열거형으로 처리하던 것들을 GameplayTag로 대체하고, 특정 GameplayTag의 보유 여부로 불리언 논리를 수행하게 될 것이다.

태그를 객체에 부여할 때는 ASC가 있는 경우 보통 ASC에 추가하여 GAS가 태그와 상호작용할 수 있게 한다. `UAbilitySystemComponent`는 `IGameplayTagAssetInterface`를 구현하여 소유한 GameplayTag에 접근하는 함수를 제공한다.

#### FGameplayTagContainer

여러 GameplayTag는 `FGameplayTagContainer`에 저장할 수 있다. `TArray<FGameplayTag>`보다 `GameplayTagContainer`를 사용하는 것이 바람직한데, GameplayTagContainer에는 효율을 높이는 최적화가 내장되어 있기 때문이다. 태그는 표준 `FName`이지만, 프로젝트 설정에서 `Fast Replication`을 활성화하면 복제 시 `FGameplayTagContainer` 안에 효율적으로 패킹된다. Fast Replication을 사용하려면 서버와 클라이언트의 GameplayTag 목록이 동일해야 하는데, 일반적으로 문제가 되지 않으므로 이 옵션을 활성화하는 것이 좋다. `GameplayTagContainer`는 순회를 위해 `TArray<FGameplayTag>`를 반환하는 것도 지원한다.

#### FGameplayTagCountContainer와 TagMapCount

`FGameplayTagCountContainer`에 저장된 GameplayTag는 해당 GameplayTag의 인스턴스 수를 저장하는 `TagMap`을 가진다. `FGameplayTagCountContainer`에 GameplayTag가 들어 있더라도 `TagMapCount`가 0일 수 있다. ASC에 GameplayTag가 남아 있는 상태를 디버깅할 때 이런 상황을 마주칠 수 있다. `HasTag()`나 `HasMatchingTag()` 같은 함수들은 `TagMapCount`를 확인하여, GameplayTag가 없거나 `TagMapCount`가 0이면 false를 반환한다.

#### 태그 등록 및 에디터

GameplayTag는 `DefaultGameplayTags.ini`에 미리 정의해야 한다. 언리얼 엔진 에디터는 프로젝트 설정에서 `DefaultGameplayTags.ini`를 직접 수정하지 않고도 개발자가 GameplayTag를 관리할 수 있는 인터페이스를 제공한다. GameplayTag 에디터에서 GameplayTag를 생성, 이름 변경, 레퍼런스 검색, 삭제할 수 있다.

![GameplayTag Editor in Project Settings](https://github.com/tranek/GASDocumentation/raw/master/Images/gameplaytageditor.png)

GameplayTag 레퍼런스를 검색하면 에디터의 친숙한 `Reference Viewer` 그래프가 열려 해당 GameplayTag를 참조하는 모든 에셋을 보여준다. 단, GameplayTag를 참조하는 C++ 클래스는 표시되지 않는다.

GameplayTag 이름을 변경하면 리다이렉트가 생성되어, 기존 GameplayTag를 참조하는 에셋이 새 GameplayTag로 리다이렉트될 수 있다. 가능하면 새 GameplayTag를 만들고, 모든 레퍼런스를 수동으로 새 GameplayTag로 업데이트한 뒤, 기존 GameplayTag를 삭제하는 방식을 권장한다. 이렇게 하면 리다이렉트 생성을 피할 수 있다.

`Fast Replication` 외에도, GameplayTag 에디터에는 흔히 복제되는 GameplayTag를 등록하여 추가 최적화하는 옵션이 있다.

#### 복제 방식 — GE 경유 vs LooseGameplayTag

GameplayTag는 GameplayEffect를 통해 추가된 경우 복제된다. ASC에는 복제되지 않으며 수동으로 관리해야 하는 `LooseGameplayTag`를 추가하는 기능도 있다. 샘플 프로젝트에서는 `State.Dead`에 `LooseGameplayTag`를 사용하여, 체력이 0이 됐을 때 소유 클라이언트가 즉시 반응할 수 있게 한다. 리스폰 시에는 `TagMapCount`를 수동으로 0으로 초기화한다. `LooseGameplayTag`를 다룰 때만 `TagMapCount`를 수동으로 조정해야 한다. `TagMapCount`를 직접 조작하기보다는 `UAbilitySystemComponent::AddLooseGameplayTag()`와 `UAbilitySystemComponent::RemoveLooseGameplayTag()` 함수를 사용하는 것이 바람직하다.

#### C++에서 태그 참조

```c++
FGameplayTag::RequestGameplayTag(FName("Your.GameplayTag.Name"))
```

부모나 자식 GameplayTag를 가져오는 등 고급 GameplayTag 조작이 필요하다면 `GameplayTagManager`가 제공하는 함수들을 활용한다. `GameplayTagManager`에 접근하려면 `GameplayTagManager.h`를 인클루드하고 `UGameplayTagManager::Get().FunctionName`으로 호출한다. GameplayTagManager는 GameplayTag를 관계 노드(부모, 자식 등)로 저장하여 지속적인 문자열 조작 및 비교보다 빠르게 처리한다.

#### Blueprint 필터링

GameplayTag와 GameplayTagContainer에는 선택적 `UPROPERTY` 지정자 `Meta = (Categories = "GameplayCue")`를 사용할 수 있다. 이를 지정하면 블루프린트에서 `GameplayCue` 부모 태그를 가진 GameplayTag만 표시되도록 필터링된다. 해당 GameplayTag 또는 GameplayTagContainer 변수가 GameplayCue에만 사용된다는 것을 알고 있을 때 유용하다.

또한 `FGameplayCueTag`라는 별도 구조체가 있어 `FGameplayTag`를 감싸며, 블루프린트에서 `GameplayCue` 부모 태그를 가진 태그만 자동으로 필터링한다.

함수의 GameplayTag 파라미터를 필터링하려면 `UFUNCTION` 지정자에 `Meta = (GameplayTagFilter = "GameplayCue")`를 사용한다. 함수의 `GameplayTagContainer` 파라미터는 필터링할 수 없다. 엔진을 수정하여 이를 가능하게 하려면, `Engine\Plugins\Editor\GameplayTagsEditor\Source\GameplayTagsEditor\Private\SGameplayTagGraphPin.cpp`의 `SGameplayTagGraphPin::ParseDefaultValueData()`가 `FilterString = UGameplayTagsManager::Get().GetCategoriesMetaFromField(PinStructType);`를 호출하고 `SGameplayTagGraphPin::GetListContent()`에서 `FilterString`을 `SGameplayTagWidget`에 전달하는 방식을 참고한다. `Engine\Plugins\Editor\GameplayTagsEditor\Source\GameplayTagsEditor\Private\SGameplayTagContainerGraphPin.cpp`의 GameplayTagContainer 버전 함수들은 메타 필드 프로퍼티를 확인하지 않고 필터를 그대로 전달한다.

샘플 프로젝트는 GameplayTag를 광범위하게 사용한다.

---

## 내 분석

### UGameplayTagsManager — 싱글톤, 초기화 시점, 동적 태그

`UGameplayTagsManager`는 전역 싱글톤(`static UGameplayTagsManager* SingletonManager`)이다.
`Get()` 첫 호출 시 null이면 `InitializeManager()`를 실행하는 lazy 초기화 패턴을 쓴다.

**초기화 흐름:**

```
모듈 로드 (엔진 초기화 초반)
  → FGameplayTagsModule::StartupModule()
      → UGameplayTagsManager::Get()           // 첫 호출 → InitializeManager()
          → NewObject<> + AddToRoot()          // GC 면제
          → LoadGameplayTagTables()            // ini, DataTable 로드
          → ConstructGameplayTagTree()         // 태그 트리 빌드
          → OnPostEngineInit에 DoneAddingNativeTags() 바인딩

엔진 초기화 완료 (PostEngineInit)
  → DoneAddingNativeTags()                     // 이후 태그 추가 잠금
```

**동적 태그 추가/제거 — 세 가지 방법의 차이:**

| 방법 | 가능 시점 | 비고 |
|---|---|---|
| `AddNativeGameplayTag()` (레거시) | PostEngineInit 이전까지만 | `bDoneAddingNativeTags`가 true가 되면 `ensure`로 막힘 |
| `FNativeGameplayTag` (권장) | 모듈 생존 기간 동안 자유롭게 | 생성자에서 자동 등록, 소멸자에서 자동 해제 |
| INI / DataTable | 에디터에서만 | 런타임 고정 |

`FNativeGameplayTag`가 권장인 이유는 **모듈 수명과 태그 수명이 자동으로 연동**되기 때문이다.
`UE_DEFINE_GAMEPLAY_TAG` 매크로로 cpp에 static 변수로 선언하면 모듈 로드 시 등록되고, 모듈 언로드 시 소멸자에서 자동 해제된다.

```cpp
// SomeModule.cpp
UE_DEFINE_GAMEPLAY_TAG(TAG_Ability_Jump, "Ability.Jump");
// 모듈 로드 → Manager에 등록
// 모듈 언로드 → 자동 해제
```

Lyra의 GameFeature 플러그인들이 각자의 태그를 플러그인 로드/언로드와 함께 관리하는 것이 이 메커니즘이다.

### FGameplayTagCountContainer — TagMapCount가 0인데 태그가 남는 이유

`FGameplayTagCountContainer`는 태그를 단순 보유 여부가 아니라 **카운트**로 관리한다.
GE가 같은 태그를 두 번 부여하면 `TagMapCount = 2`가 되고, GE 하나가 제거되면 `1`이 된다.

`HasTag()` 류 함수들은 `TagMapCount > 0`인 경우에만 true를 반환한다.
`TagMapCount`가 0인 태그가 `TagMap`에 남아 있어도 논리적으로는 "없는 것"으로 취급된다.

`LooseGameplayTag`를 쓸 때 `Add` / `Remove` 짝을 맞추지 않으면 이 상태가 된다.
`TagMapCount`를 직접 건드리지 말고 `AddLooseGameplayTag()` / `RemoveLooseGameplayTag()`를 써야 한다.

### LooseGameplayTag vs GE 태그 — 왜 복제 동작이 다른가

`AddLooseGameplayTag()`는 기본값이 **복제 안 함**이다.

```cpp
inline void AddLooseGameplayTag(
    const FGameplayTag& GameplayTag,
    int32 Count = 1,
    EGameplayTagReplicationState TagRepState = EGameplayTagReplicationState::None  // ← 기본값
)
// 주석: "It is up to the calling GameCode to make sure these tags are added on clients/server where necessary"
```

`TagRepState = None`이면 로컬 `GameplayTagCountContainer`에만 추가되고 복제 컨테이너(`ReplicatedLooseTags`)에는 들어가지 않는다.

**GE는 복제가 내장된 이유:**

| Replication Mode | GE 태그 복제 경로 |
|---|---|
| Full / Mixed | `ActiveGameplayEffects` 자체가 복제됨 → 클라이언트가 GE 받아 태그 직접 적용 |
| Minimal | GE는 복제 안 됨 → 태그만 `MinimalReplicationTags`에 담아 복제 (`COND_SkipOwner`) |

GE 시스템은 Replication Mode를 보고 어떤 복제 채널을 쓸지 자동으로 결정한다.
GE를 통한 태그 부여는 복제가 묶음으로 처리되는 반면, LooseGameplayTag는 GE 없이 수동으로 태그를 관리하는 탈출구라서 복제 책임도 호출자에게 있다.

**LooseGameplayTag를 복제하려면** `TagRepState` 인자를 명시하거나 전용 헬퍼를 쓴다.

```cpp
// ReplicatedLooseTags 채널로 복제
ASC->AddLooseGameplayTag(Tag, 1, EGameplayTagReplicationState::AllClients);

// Minimal 모드 전용 헬퍼 (MinimalReplicationTags 채널)
ASC->AddMinimalReplicationGameplayTag(Tag);
```
