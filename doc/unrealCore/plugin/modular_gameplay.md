# ModularGameplay 플러그인

> 출처:  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponent.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/PawnComponent.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkInitStateInterface.h`  
> `C:/UE_5.7/Engine/Plugins/Runtime/ModularGameplay/Source/ModularGameplay/Public/Components/GameFrameworkComponentManager.h`  
> Lyra 활용: `Character/LyraPawnExtensionComponent.h`, `Character/LyraHeroComponent.h`

---

## 한 줄 요약

ModularGameplay는 런타임에 Actor에 컴포넌트를 동적으로 주입하고, 여러 컴포넌트의 초기화 순서를 GameplayTag 기반 상태 머신으로 조율하는 UE5 공식 플러그인이다.

---

## 클래스 계층

```
UActorComponent
  └─ UGameFrameworkComponent          (ModularGameplay 플러그인 제공)
        └─ UPawnComponent
```

둘 다 얇은 래퍼다. 실질적인 기능은 `UGameFrameworkComponentManager`와 `IGameFrameworkInitStateInterface`에 있다.

---

## UGameFrameworkComponent

**파일**: `GameFrameworkComponent.h`  
**역할**: 게임 프레임워크 Actor(PlayerState, GameState 등)에 붙는 컴포넌트들의 공통 베이스.

`UActorComponent`에서 추가된 것:

| 메서드 | 설명 |
|--------|------|
| `GetGameInstance<T>()` | Owner Actor를 통해 GameInstance에 접근 |
| `GetGameInstanceChecked<T>()` | null 불허 버전 (check() 포함) |
| `HasAuthority()` | Owner의 Role이 `ROLE_Authority`인지 확인 |
| `GetWorldTimerManager()` | 월드 타이머 매니저 반환 |

같은 헤더에 `TComponentIterator<T>` / `TConstComponentIterator<T>` 유틸리티도 정의돼 있다.  
`IsRegistered()` 조건을 걸며 Actor의 등록된 컴포넌트를 순회한다.

---

## UPawnComponent

**파일**: `PawnComponent.h`  
**역할**: Pawn에 붙는 컴포넌트 전용 베이스. Pawn 소유 구조에 맞는 타입 안전 접근자 추가.

`UGameFrameworkComponent`에서 추가된 것 (모두 template 함수):

| 메서드 | 반환 | 설명 |
|--------|------|------|
| `GetPawn<T>()` | `T*` | Owner를 Pawn으로 캐스팅 |
| `GetPawnChecked<T>()` | `T*` | null 불허 버전 |
| `GetPlayerState<T>()` | `T*` | Pawn의 PlayerState 접근. 클라이언트에서 복제 전에는 null 가능 |
| `GetController<T>()` | `T*` | Pawn의 Controller 접근. 클라이언트에서는 보통 null |

모두 `TPointerIsConvertibleFromTo<T, BaseClass>::Value`를 `static_assert`로 강제해 컴파일 타임 타입 안전성을 보장한다.

> **왜 상속받는가?**  
> `UActorComponent::GetOwner()`는 `AActor*`를 반환한다. Pawn 컴포넌트에서 매번 `Cast<APawn>(GetOwner())`를 작성하는 반복을 없애기 위한 얇은 편의 레이어다.

---

## IGameFrameworkInitStateInterface

**파일**: `GameFrameworkInitStateInterface.h`  
**역할**: 컴포넌트가 자신의 초기화 진행 상태를 `UGameFrameworkComponentManager`에 등록하고, 다른 Feature의 상태 변경을 구독하는 인터페이스.

### 핵심 메서드

```
[등록/해제]
RegisterInitStateFeature()          ← OnRegister()에서 호출, Manager에 Feature 등록
UnregisterInitStateFeature()        ← EndPlay()에서 호출, 등록 해제

[상태 전이]
CanChangeInitState(Manager, Current, Desired) → bool   ← 전이 가능 여부 커스텀 로직
HandleChangeInitState(Manager, Current, Desired)        ← 전이 직전 실행할 로직
TryToChangeInitState(DesiredState) → bool              ← Can 체크 → Handle 실행 → Manager 통보
ContinueInitStateChain(ChainArray) → FGameplayTag      ← 순서대로 연속 전이 시도, 도달한 최종 상태 반환

[조회]
GetFeatureName() → FName           ← 이 Feature의 이름
GetInitState() → FGameplayTag      ← 현재 상태
HasReachedInitState(DesiredState)  ← 해당 상태 이상에 도달했는지

[구독]
OnActorInitStateChanged(Params)    ← 같은 Actor의 다른 Feature 상태 변경 시 콜백
BindOnActorInitStateChanged(FeatureName, RequiredState, bCallIfReached)
CheckDefaultInitialization()       ← override해서 기본 초기화 경로 진행 (ContinueInitStateChain 활용)
CheckDefaultInitializationForImplementers()  ← 같은 Actor의 모든 구현체에게 CheckDefault 호출
```

---

## UGameFrameworkComponentManager

**파일**: `GameFrameworkComponentManager.h`  
**상속**: `UGameInstanceSubsystem` → GameInstance 당 하나, 자동 생성/소멸

**두 가지 완전히 독립된 역할**을 한 클래스가 담당한다.

---

### 역할 1: 컴포넌트 동적 주입 시스템

GameFeature나 외부 시스템이 특정 Actor 클래스에 컴포넌트를 런타임으로 추가/제거할 수 있다.

```
[요청 등록]
AddComponentRequest(ActorClass, ComponentClass) → TSharedPtr<FComponentRequestHandle>

[Actor가 수신자로 등록]
AddReceiver(Actor) / RemoveReceiver(Actor)
  ─ Actor가 BeginPlay에서 직접 호출해 "나 이제 컴포넌트 받을 준비 됨" 선언
  ─ Lyra: ULyraPawnExtensionComponent::OnRegister() → GameFrameworkComponentManager::AddGameFrameworkComponentReceiver()

[요청 제거]
FComponentRequestHandle 소멸 → 자동으로 해당 컴포넌트 제거 (RAII)
```

요청은 레퍼런스 카운트된다. 같은 (ActorClass, ComponentClass) 요청이 여러 번 들어와도 컴포넌트는 하나만 생기고, 마지막 Handle이 소멸될 때 제거된다.

#### 확장 이벤트 시스템

```
AddExtensionHandler(ActorClass, Delegate)  ← 특정 Actor 클래스에 이벤트 핸들러 등록
SendExtensionEvent(Actor, EventName)       ← 이벤트 발송

// 내장 이벤트 이름 (FName)
NAME_ReceiverAdded      ← AddReceiver 직후
NAME_ReceiverRemoved    ← RemoveReceiver 시
NAME_ExtensionAdded     ← 핸들러 등록 시
NAME_ExtensionRemoved   ← 핸들러 제거 시
NAME_GameActorReady     ← 게임 정의: "Actor가 확장 받을 준비 완료" (게임에서 직접 발송)
```

---

### 역할 2: InitState 조율 시스템

같은 Actor 위에 있는 여러 Feature(컴포넌트)들이 서로의 초기화 진행 상태를 감지하며 순서 있게 초기화할 수 있다.

```
[전역 상태 순서 등록]
RegisterInitState(NewState, bAddBefore, ExistingState)
  ─ InitStateOrder 배열에 GameplayTag로 된 상태를 순서대로 삽입

[상태 변경]
ChangeFeatureInitState(Actor, FeatureName, Implementer, FeatureState)
  ─ StateChangeQueue에 넣어 재귀 콜백 방지
  ─ 완료 후 구독 중인 delegate 전부 호출

[상태 조회]
GetInitStateForFeature(Actor, FeatureName) → FGameplayTag
HasFeatureReachedInitState(Actor, FeatureName, RequiredState) → bool
HaveAllFeaturesReachedInitState(Actor, RequiredState) → bool   ← "모두 도달했냐" 체크
GetImplementerForFeature(Actor, FeatureName) → UObject*

[구독]
RegisterAndCallForActorInitState(Actor, FeatureName, RequiredState, Delegate)
RegisterAndCallForClassInitState(ActorClass, FeatureName, RequiredState, Delegate)
```

---

## Lyra에서의 활용

두 컴포넌트 모두 `UPawnComponent + IGameFrameworkInitStateInterface` 이중 상속.

```
ALyraCharacter
  ├─ ULyraPawnExtensionComponent   Feature 이름: "PawnExtension"
  └─ ULyraHeroComponent            Feature 이름: "Hero"
```

### 초기화 상태 4단계 (GameplayTag)

```
InitState_Spawned
  → InitState_DataAvailable    (PawnData 준비됨, Controller 보유)
  → InitState_DataInitialized  (같은 Actor의 모든 Feature가 DataAvailable 도달)
  → InitState_GameplayReady    (AbilitySystem 초기화 완료)
```

### ULyraPawnExtensionComponent의 역할

```
OnRegister()
  └─ RegisterInitStateFeature()           ← Manager에 "PawnExtension" Feature 등록
     AddGameFrameworkComponentReceiver()  ← 컴포넌트 주입 수신자로 등록

OnActorInitStateChanged(Params)
  └─ "Hero 포함 다른 Feature가 DataAvailable에 도달했나?"
     HaveAllFeaturesReachedInitState(DataAvailable) → true
       └─ TryToChangeInitState(DataInitialized)

HandleChangeInitState(...→ DataInitialized)
  └─ InitializeAbilitySystem()            ← ASC Avatar 설정 (핵심)

CheckDefaultInitialization()
  └─ ContinueInitStateChain([Spawned, DataAvailable, DataInitialized, GameplayReady])
```

### ULyraHeroComponent의 역할

```
OnRegister()
  └─ RegisterInitStateFeature()     ← Manager에 "Hero" Feature 등록

OnActorInitStateChanged(Params)
  └─ "PawnExtension이 DataInitialized에 도달했나?"
     → TryToChangeInitState(DataInitialized)

HandleChangeInitState(...→ DataInitialized)
  └─ InitializePlayerInput()        ← IMC 등록 + 입력 바인딩
     SendExtensionEvent(NAME_BindInputsNow)  ← 추가 입력 바인딩 구독자에게 통보
```

### 전체 초기화 흐름 요약

```
ALyraCharacter::BeginPlay()
  │
  ├─ PawnExtensionComponent::OnRegister() → RegisterInitStateFeature("PawnExtension")
  ├─ HeroComponent::OnRegister()          → RegisterInitStateFeature("Hero")
  │
  ├─ PawnExtensionComponent::BeginPlay()
  │     CheckDefaultInitialization()
  │       → ContinueInitStateChain → DataAvailable 도달
  │         → OnActorInitStateChanged 전파 → Hero가 감지
  │           → Hero도 DataAvailable 도달
  │             → PawnExtension: HaveAllFeaturesReached(DataAvailable) == true
  │               → DataInitialized 전이
  │                 → InitializeAbilitySystem()   ← ASC Avatar 설정
  │                   → GameplayReady 전이
  │
  └─ HeroComponent::BeginPlay()
        OnActorInitStateChanged: PawnExtension == DataInitialized
          → Hero: DataInitialized 전이
            → InitializePlayerInput()
              → SendExtensionEvent(NAME_BindInputsNow)
```

---

## 설계 의도

| 문제 | 해결 |
|------|------|
| GameFeature 플러그인이 코어 Actor를 몰라도 컴포넌트를 붙이고 싶다 | `AddComponentRequest` — Actor 클래스 이름만으로 요청 |
| 여러 컴포넌트가 서로를 직접 참조하지 않고 초기화 순서를 맞추고 싶다 | InitState 시스템 — GameplayTag 상태 + 구독 패턴 |
| 컴포넌트 추가/제거를 명시적 관리 없이 안전하게 하고 싶다 | `FComponentRequestHandle` RAII — Handle 소멸 시 자동 제거 |
| Pawn 컴포넌트에서 매번 `Cast<APawn>(GetOwner())` 반복을 없애고 싶다 | `UPawnComponent::GetPawn<T>()` 헬퍼 |
