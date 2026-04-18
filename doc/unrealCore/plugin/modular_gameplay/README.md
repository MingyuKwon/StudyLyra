# ModularGameplay 플러그인

> 플러그인 경로: `Engine/Plugins/Runtime/ModularGameplay/`

런타임에 Actor에 컴포넌트를 동적으로 주입하고, 여러 컴포넌트의 초기화 순서를 GameplayTag 기반 상태 머신으로 조율하는 UE5 공식 플러그인.

---

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_component_classes.md](01_component_classes.md) | UGameFrameworkComponent 계층 전체 — UPawnComponent, UControllerComponent, UPlayerStateComponent, UGameStateComponent |
| [02_component_manager.md](02_component_manager.md) | UGameFrameworkComponentManager — 컴포넌트 동적 주입 시스템 |
| [03_init_state.md](03_init_state.md) | InitState 시스템 — IGameFrameworkInitStateInterface + Manager InitState 파트 |
| [04_lyra_usage.md](04_lyra_usage.md) | Lyra 구현체 목록 및 초기화 흐름 |

---

## 왜 필요한가 — 설계 의도

### 문제: Actor 클래스가 너무 많은 것을 알아야 한다

일반적인 방식으로 컴포넌트를 추가하면 Actor 생성자 안에 직접 적어야 한다.

```cpp
// 기존 방식 — Actor가 컴포넌트를 "직접 소유"
ALyraCharacter::ALyraCharacter()
{
    HealthComponent     = CreateDefaultSubobject<ULyraHealthComponent>("Health");
    EquipmentComponent  = CreateDefaultSubobject<ULyraEquipmentManagerComponent>("Equipment");
    AbilityComponent    = CreateDefaultSubobject<ULyraAbilitySystemComponent>("ASC");
    // ... 기능이 늘어날수록 생성자가 커진다
}
```

이 방식의 문제:
- `ALyraCharacter`가 모든 기능 컴포넌트를 **컴파일 타임에 알아야** 한다
- 새 기능(GameFeature)을 추가할 때마다 **`ALyraCharacter` 소스를 열어야** 한다
- GameFeature 플러그인 비활성화 시 컴포넌트를 **조건부로 제거하는 코드**를 따로 짜야 한다

### 해결: 외부에서 컴포넌트를 주입한다

ModularGameplay는 방향을 뒤집는다.  
Actor는 "나는 컴포넌트를 받을 수 있다"고만 선언하고, **누가 뭘 붙일지는 외부(GameFeature)가 결정**한다.

```
기존 방식:
  ALyraCharacter → (직접 생성) → HealthComponent
                → (직접 생성) → EquipmentComponent

ModularGameplay 방식:
  ALyraCharacter  →  AddReceiver(this)  →  "나 받을 준비 됨"
                                           ↑
  GameFeature (ShooterCore) → AddComponentRequest(ALyraCharacter, HealthComponent)
  GameFeature (ShooterCore) → AddComponentRequest(ALyraCharacter, EquipmentComponent)
```

Actor 코드는 바뀌지 않는다. **GameFeature 플러그인만 추가/제거하면** 기능이 붙고 떨어진다.

---

### 핵심 차이 — 3가지 관점

| | 기존 방식 | ModularGameplay |
|--|----------|-----------------|
| **누가 컴포넌트를 만드나** | Actor 자신 (생성자) | 외부 시스템 (GameFeature) |
| **새 기능 추가 시** | Actor 소스 수정 필요 | Actor 건드리지 않음 |
| **플러그인 비활성화 시** | 수동 조건부 제거 | Handle 소멸 → 자동 제거 (RAII) |

---

### GameFeature 플러그인과의 연동

실제로 `AddComponentRequest()`를 호출하는 것은 `UGameFeatureAction_AddComponents`다.

```cpp
// GameFeatures 플러그인 활성화 시
void UGameFeatureAction_AddComponents::OnGameFeatureActivating(...)
{
    for (const FGameFeatureComponentEntry& Entry : ComponentList)
    {
        // ShooterCore가 "ALyraCharacter에 ULyraEquipmentManagerComponent 붙여라" 요청
        TSharedPtr<FComponentRequestHandle> Handle =
            Manager->AddComponentRequest(Entry.ActorClass, Entry.ComponentClass);
        
        ActiveRequests.Add(Handle);  // Handle을 보관 — 비활성화 시 소멸 → 자동 제거
    }
}

// GameFeatures 플러그인 비활성화 시
void UGameFeatureAction_AddComponents::OnGameFeatureDeactivating(...)
{
    ActiveRequests.Empty();  // Handle 소멸 → 자동으로 컴포넌트 제거
}
```

이 구조 덕분에 ShooterCore GameFeature 플러그인을 **런타임에 켜고 끄면**  
`ALyraCharacter`의 장비 시스템이 자동으로 붙었다 떨어진다.

---

### Actor의 opt-in 선언이 필요한 이유

`AddReceiver(this)` 없이는 Manager가 해당 Actor에 컴포넌트를 붙이지 않는다.  
이는 의도된 설계다:

- **모든 Actor에 무조건 적용**하면 성능 문제 (`ReceiverClass != AActor` 강제)
- Actor 개발자가 **"나는 이 시스템을 지원한다"고 명시적으로 선언**해야
- 선언하는 위치: `BeginPlay` 또는 `OnRegister`

```cpp
// ALyraCharacter::BeginPlay()
UGameFrameworkComponentManager::AddGameFrameworkComponentReceiver(this);
```

---

### 요약

- **"동적으로 컴포넌트 추가"** 맞지만, 목적은 그게 아니라 **"Actor를 건드리지 않고 외부에서 기능 주입"**이다
- GameFeature 플러그인이 켜질 때 컴포넌트가 붙고, 꺼질 때 자동으로 떨어진다
- Actor는 수신자 등록(`AddReceiver`)만 하면 된다 — 뭐가 붙는지 모른다

---

## 핵심 클래스 한눈에 보기

```
UActorComponent
  └─ UGameFrameworkComponent                 ← 게임 프레임워크 Actor용 컴포넌트 베이스
        ├─ UPawnComponent                    → APawn용
        ├─ UControllerComponent              → AController용
        ├─ UPlayerStateComponent             → APlayerState용
        └─ UGameStateComponent               → AGameStateBase용

UGameInstanceSubsystem
  └─ UGameFrameworkComponentManager          ← 컴포넌트 주입 + InitState 조율 (GameInstance당 1개)

UInterface
  └─ IGameFrameworkInitStateInterface        ← Feature 초기화 상태 머신 인터페이스
```
