# Lyra 구현체 및 초기화 흐름

> 출처:  
> `Source/LyraGame/Character/LyraHealthComponent.h`  
> `Source/LyraGame/Character/LyraPawnExtensionComponent.h`  
> `Source/LyraGame/Character/LyraHeroComponent.h`  
> `Source/LyraGame/Equipment/LyraEquipmentManagerComponent.h`  
> `Source/LyraGame/Cosmetics/LyraPawnComponent_CharacterParts.h`

---

## Lyra 구현체 목록

`UGameFrameworkComponent` / `UPawnComponent`를 상속받은 Lyra의 모든 컴포넌트.

```
UGameFrameworkComponent
  ├─ ULyraHealthComponent                           (Character/)
  └─ UPawnComponent
        ├─ ULyraPawnExtensionComponent              (Character/) + IGameFrameworkInitStateInterface
        ├─ ULyraHeroComponent                       (Character/) + IGameFrameworkInitStateInterface
        ├─ ULyraEquipmentManagerComponent           (Equipment/)
        └─ ULyraPawnComponent_CharacterParts        (Cosmetics/)
```

---

## ULyraHealthComponent

**파일**: `Character/LyraHealthComponent.h`  
**베이스**: `UGameFrameworkComponent` (Pawn이 아닌 Actor에도 붙을 수 있어 PawnComponent 미사용)

체력 관련 로직을 Pawn에서 분리한 컴포넌트. `ULyraHealthSet`의 델리게이트를 구독해 외부에 체력 변화를 전달한다.

**핵심 역할**:
- `InitializeWithAbilitySystem(ASC)` — `ULyraHealthSet`을 꺼내 델리게이트 바인딩
- `GetHealth()` / `GetMaxHealth()` / `GetHealthNormalized()` — 체력 조회 API
- `StartDeath()` / `FinishDeath()` — 사망 시퀀스 2단계 관리
- `DamageSelfDestruct()` — 낙사 등 강제 사망 처리

**사망 상태** (`ELyraDeathState`, Replicated):
```
NotDead → DeathStarted → DeathFinished
```

**외부 노출 델리게이트**:
| 델리게이트 | 파라미터 | 설명 |
|---|---|---|
| `OnHealthChanged` | HealthComp, OldVal, NewVal, Instigator | 체력 변화 |
| `OnMaxHealthChanged` | 동일 | 최대 체력 변화 |
| `OnDeathStarted` | OwningActor | 사망 시작 |
| `OnDeathFinished` | OwningActor | 사망 완료 |

> `ULyraHealthSet`의 델리게이트(서버 전용, 6파라미터)를 받아 Blueprint에서 쓰기 좋은 형태로 재가공해서 노출하는 어댑터 역할이다.

---

## ULyraPawnExtensionComponent

**파일**: `Character/LyraPawnExtensionComponent.h`  
**베이스**: `UPawnComponent` + `IGameFrameworkInitStateInterface`  
**Feature 이름**: `"PawnExtension"`

모든 Pawn 컴포넌트들의 **초기화 순서 조율자**. 다른 Feature들이 `DataAvailable`에 모두 도달해야만 `DataInitialized`로 전이하며, 그 시점에 ASC Avatar 설정을 수행한다.

**핵심 역할**:
- `SetPawnData(PawnData)` — PawnData 설정, `DataAvailable` 전이 조건
- `InitializeAbilitySystem(ASC, OwnerActor)` — `InitAbilityActorInfo()` 호출, ASC Avatar 설정
- `UninitializeAbilitySystem()` — 리스폰/빙의 해제 시 Avatar 해제
- `HandleControllerChanged()` / `HandlePlayerStateReplicated()` — 상태 변화 시 `CheckDefaultInitialization()` 재호출
- `OnAbilitySystemInitialized_RegisterAndCall()` — ASC 초기화 완료 구독 (HeroComponent 등이 사용)

**InitState 전이 조건**:
- `DataAvailable`: PawnData 있음 + Controller 보유
- `DataInitialized`: `HaveAllFeaturesReachedInitState(DataAvailable)` == true
- `GameplayReady`: `InitializeAbilitySystem()` 완료

---

## ULyraHeroComponent

**파일**: `Character/LyraHeroComponent.h`  
**베이스**: `UPawnComponent` + `IGameFrameworkInitStateInterface`  
**Feature 이름**: `"Hero"`

**플레이어 입력과 카메라**를 담당하는 컴포넌트. PawnExtensionComponent가 `DataInitialized`에 도달해야 활성화된다.

**핵심 역할**:
- `InitializePlayerInput(InputComponent)` — IMC 등록 + Native/Ability 입력 바인딩
- `SetAbilityCameraMode()` / `ClearAbilityCameraMode()` — GA가 카메라 모드를 재정의할 때 사용
- `AddAdditionalInputConfig()` / `RemoveAdditionalInputConfig()` — 모드별 추가 입력 설정
- `IsReadyToBindInputs()` — 입력 바인딩 준비 완료 여부
- `NAME_BindInputsNow` 이벤트 발송 — 외부 시스템이 추가 바인딩을 걸 수 있게 알림

---

## ULyraEquipmentManagerComponent

**파일**: `Equipment/LyraEquipmentManagerComponent.h`  
**베이스**: `UPawnComponent`

Pawn이 장착한 장비 목록을 관리한다. `FLyraEquipmentList`(FFastArraySerializer)로 장비 목록을 복제한다.

**핵심 역할**:
- `EquipItem(EquipmentDefinition)` → `ULyraEquipmentInstance*` — 장비 장착, AbilitySet 부여 (Authority only)
- `UnequipItem(Instance)` — 장비 해제, AbilitySet 제거 (Authority only)
- `GetFirstInstanceOfType<T>()` — 특정 타입 장비 인스턴스 조회
- `GetEquipmentInstancesOfType()` — 특정 타입 전체 목록 조회

**복제 구조**:
```
FLyraEquipmentList (FFastArraySerializer)
  └─ TArray<FLyraAppliedEquipmentEntry>
        ├─ EquipmentDefinition  (복제됨)
        ├─ Instance             (복제됨)
        └─ GrantedHandles       (NotReplicated — 서버 전용, AbilitySet 제거용)
```

`ReplicateSubobjects()`를 오버라이드해 `ULyraEquipmentInstance` 서브오브젝트도 함께 복제한다.

---

## ULyraPawnComponent_CharacterParts

**파일**: `Cosmetics/LyraPawnComponent_CharacterParts.h`  
**베이스**: `UPawnComponent`

Pawn에 붙는 **코스메틱 파츠(헬멧, 의상 등) 관리** 컴포넌트. 게임플레이 로직과 무관한 외형 전담.

**핵심 역할**:
- `AddCharacterPart(Part)` → `FLyraCharacterPartHandle` — 파츠 추가, 클라이언트에 ChildActor 스폰 (Authority only)
- `RemoveCharacterPart(Handle)` / `RemoveAllCharacterParts()` — 파츠 제거
- `GetCombinedTags(Prefix)` — 장착된 모든 파츠의 GameplayTag 합집합 반환 (애니메이션 선택 등에 활용)
- `BodyMeshes` (`FLyraAnimBodyStyleSelectionSet`) — 파츠 태그 기반으로 골격 메시를 선택하는 규칙

**복제 구조**:
```
FLyraCharacterPartList (FFastArraySerializer, Transient)
  └─ TArray<FLyraAppliedCharacterPartEntry>
        ├─ Part (복제됨)
        ├─ PartHandle (NotReplicated — 서버 전용 핸들 인덱스)
        └─ SpawnedComponent (NotReplicated — 클라이언트 전용 ChildActorComponent)
```

> `EquipmentManagerComponent`와 구조가 유사하다 (FFastArraySerializer + 서버/클라이언트 전용 필드 분리). 차이는 장비는 AbilitySet을 부여하지만 파츠는 외형(ChildActor)만 스폰한다.

---

## 전체 초기화 흐름

```
ALyraCharacter::BeginPlay()
  │
  ├─ PawnExtensionComponent::OnRegister()
  │     RegisterInitStateFeature("PawnExtension")
  │     BindOnActorInitStateChanged(NAME_None, ...)  ← 모든 Feature 변경 감지
  │
  ├─ HeroComponent::OnRegister()
  │     RegisterInitStateFeature("Hero")
  │     BindOnActorInitStateChanged("PawnExtension", DataInitialized, ...)
  │
  ├─ PawnExtensionComponent::BeginPlay()
  │     CheckDefaultInitialization()
  │       ContinueInitStateChain([Spawned, DataAvailable, DataInitialized, GameplayReady])
  │         Spawned → DataAvailable: PawnData 있음 + Controller 있음 → 전이
  │           ChangeFeatureInitState → ProcessFeatureStateChange
  │             → HeroComponent::OnActorInitStateChanged (PawnExtension = DataAvailable)
  │               → Hero: DataAvailable 전이 시도
  │             → PawnExtension: CheckDefaultInitializationForImplementers()
  │         DataAvailable → DataInitialized:
  │           HaveAllFeaturesReachedInitState(DataAvailable) == true → 전이
  │             HandleChangeInitState → InitializeAbilitySystem()  ← ASC Avatar 설정
  │             → HeroComponent::OnActorInitStateChanged (PawnExtension = DataInitialized)
  │               → Hero: DataInitialized 전이
  │                   HandleChangeInitState → InitializePlayerInput()
  │                     SendExtensionEvent(NAME_BindInputsNow)
  │         DataInitialized → GameplayReady → 전이
  │
  └─ HeroComponent::BeginPlay()
        CheckDefaultInitialization()  ← PawnExtension이 이미 앞서 있으면 빠르게 따라잡음
```

**핵심 설계**: PawnExtension과 Hero는 서로의 존재를 모른다. Manager를 중재자로만 사용해 각자의 `CanChangeInitState` 조건을 확인하고 전이한다.
