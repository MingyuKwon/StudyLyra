# GameplayTag 기초

> **GASDoc**: 4.2 · [원문 참조](../cache/GASDocument_Readme.md)

---

### GameplayTag란 무엇이며 기존 bool/enum 방식 대신 사용해야 하는 이유는?

`FGameplayTag`는 `Parent.Child.Grandchild...` 형태의 계층적 이름으로, `GameplayTagManager`에 등록된다.

bool/enum 대신 GameplayTag를 쓰는 이유는 **계층 쿼리**와 **코드 결합도** 때문이다. `HasTag("State.Debuff")` 하나로 `State.Debuff.Stun`, `State.Debuff.Slow` 등 하위 태그를 전부 포함해 검사할 수 있다. bool이나 enum이라면 각각 따로 체크해야 한다. 또한 태그 이름은 문자열이라 시스템 간 결합이 없고, 에디터에서 관리되므로 코드 수정 없이 디자이너가 추가·변경할 수 있다.

태그를 부여할 때는 보통 ASC에 추가한다. `UAbilitySystemComponent`는 `IGameplayTagAssetInterface`를 구현해 태그 접근 함수를 제공한다.

#### FGameplayTagContainer가 TArray\<FGameplayTag\>보다 효율적인 이유는?

`FGameplayTagContainer`에는 내부 최적화가 내장되어 있다. 프로젝트 설정에서 `Fast Replication`을 켜면 복제 시 태그를 효율적으로 패킹한다. 서버와 클라이언트의 태그 목록이 동일해야 하지만 일반적으로 문제가 없으므로 켜는 것이 권장된다.

#### GE를 통해 부여된 태그와 LooseGameplayTag의 복제 동작은 어떻게 다른가?

GE를 통해 부여된 태그는 Replication Mode에 따라 자동 복제된다. 반면 `AddLooseGameplayTag()`는 기본적으로 복제되지 않는다. 복제가 필요하면 `TagRepState` 인자를 명시해야 한다.

```cpp
ASC->AddLooseGameplayTag(Tag, 1, EGameplayTagReplicationState::AllClients);
```

샘플 프로젝트에서 `State.Dead`는 LooseGameplayTag로 관리한다. 체력이 0이 되는 순간 소유 클라이언트가 즉시 반응해야 하기 때문이다. GE를 거치면 복제 지연이 생기므로 직접 추가하는 방식을 택했다. 리스폰 시에는 `TagMapCount`를 0으로 수동 초기화한다.

#### C++에서 GameplayTag를 참조하는 방법은?

```cpp
FGameplayTag::RequestGameplayTag(FName("Your.GameplayTag.Name"))
```

부모·자식 태그 탐색 등 고급 조작이 필요하면 `UGameplayTagManager::Get()`을 통해 접근한다. GameplayTagManager는 태그를 관계 노드 트리로 저장하므로 문자열 비교보다 빠르다.

#### Blueprint에서 GameplayTag를 특정 카테고리로 필터링하는 방법은?

`UPROPERTY`에 `Meta = (Categories = "GameplayCue")`를 지정하면 해당 카테고리 하위 태그만 표시된다. 함수 파라미터 필터링은 `UFUNCTION`에 `Meta = (GameplayTagFilter = "GameplayCue")`를 사용한다.

`FGameplayCueTag` 구조체를 쓰면 `GameplayCue` 하위 태그가 자동 필터링된다.

---

### GameplayTag는 어떻게 등록하고, 이름 변경 시 주의할 점은?

태그는 `DefaultGameplayTags.ini`에 미리 정의하거나, Project Settings의 GameplayTag 에디터에서 관리한다. 에디터에서 생성, 이름 변경, 레퍼런스 검색, 삭제가 가능하다.

이름을 변경하면 리다이렉트가 생성된다. 리다이렉트가 쌓이면 관리가 복잡해지므로, 가능하면 새 태그를 만들고 레퍼런스를 수동으로 교체한 뒤 기존 태그를 삭제하는 것이 권장된다. 단, C++ 레퍼런스는 Reference Viewer에 표시되지 않으니 주의해야 한다.

---

### UGameplayTagsManager는 언제 초기화되며, 동적 태그를 추가하는 세 가지 방법의 차이는?

`UGameplayTagsManager`는 전역 싱글톤으로, `Get()` 첫 호출 시 lazy 초기화된다.

```
모듈 로드 → FGameplayTagsModule::StartupModule()
  → UGameplayTagsManager::Get() 첫 호출 → InitializeManager()
      → ini/DataTable 로드, 태그 트리 빌드
  → PostEngineInit 시 DoneAddingNativeTags() → 이후 태그 추가 잠금
```

| 방법 | 가능 시점 | 비고 |
|---|---|---|
| `AddNativeGameplayTag()` | PostEngineInit 이전까지만 | 잠금 후 `ensure`로 막힘 |
| `FNativeGameplayTag` | 모듈 생존 기간 동안 자유롭게 | 생성자에서 자동 등록, 소멸자에서 자동 해제 |
| INI / DataTable | 에디터에서만 | 런타임 고정 |

`FNativeGameplayTag`가 권장되는 이유는 모듈 수명과 태그 수명이 자동으로 연동되기 때문이다. Lyra의 GameFeature 플러그인들이 각자의 태그를 플러그인 로드/언로드와 함께 관리하는 것이 이 메커니즘이다.

```cpp
UE_DEFINE_GAMEPLAY_TAG(TAG_Ability_Jump, "Ability.Jump");
// 모듈 로드 → Manager에 등록, 모듈 언로드 → 자동 해제
```

---

### FGameplayTagCountContainer가 카운트로 태그를 관리하는 이유와 디버깅 시 주의점은?

태그를 단순 bool이 아닌 카운트로 관리하는 이유는 **중복 부여를 올바르게 처리하기 위해서다.** GE 두 개가 같은 태그를 부여하면 `TagMapCount = 2`가 되고, GE 하나가 제거되면 `1`이 된다. 카운트가 0이 되어야 비로소 태그가 "없는 것"으로 취급된다.

디버깅 시 `TagMapCount`가 0인 태그가 `TagMap`에 남아 있는 경우를 볼 수 있다. `HasTag()` 류 함수는 `TagMapCount > 0`일 때만 true를 반환하므로 논리적으로는 문제없지만, LooseGameplayTag의 Add/Remove 짝이 맞지 않아 생기는 경우가 많다. `TagMapCount`를 직접 건드리지 말고 `AddLooseGameplayTag()` / `RemoveLooseGameplayTag()`만 사용해야 한다.

---

### LooseGameplayTag는 왜 기본적으로 복제되지 않으며, 복제가 필요할 때 어떻게 해야 하는가?

`AddLooseGameplayTag()`의 기본값이 복제 없음인 이유는 **호출자가 복제 범위를 직접 결정하게 하기 위해서다.** GE는 Replication Mode를 보고 복제 채널을 자동 선택하지만, LooseGameplayTag는 GE 없이 수동으로 태그를 관리하는 탈출구이므로 복제 책임도 호출자에게 있다.

복제가 필요하면 `TagRepState` 인자를 명시하거나 전용 헬퍼를 사용한다.

```cpp
// 전체 클라이언트에 복제
ASC->AddLooseGameplayTag(Tag, 1, EGameplayTagReplicationState::AllClients);

// Minimal 모드 전용 (MinimalReplicationTags 채널)
ASC->AddMinimalReplicationGameplayTag(Tag);
```

GE 태그는 Replication Mode에 따라 자동으로 복제 채널이 결정된다.

| Replication Mode | GE 태그 복제 경로 |
|---|---|
| Full / Mixed | `ActiveGameplayEffects` 자체가 복제됨 |
| Minimal | 태그만 `MinimalReplicationTags`에 담아 복제 (`COND_SkipOwner`) |
