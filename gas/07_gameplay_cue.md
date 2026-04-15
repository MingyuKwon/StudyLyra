# GameplayCue

> 참고: [GAS Doc 캐시](gas_doc_cache.md) | 소스: `LyraGameplayCueManager.h/cpp`

---

## 역할

GameplayCue(GC)는 **비게임플레이 작업 전담** 시스템이다.

- 사운드, 파티클, 카메라 흔들기, 데칼 등 시각/청각 효과
- 게임플레이 로직(데미지, 체력 등)과 완전히 분리
- 별도의 복제 경로로 Simulated Proxy에도 전달

GC는 GAS의 "표현 레이어"다. 게임플레이 결과를 바꾸면 안 되고, 보여주기만 해야 한다.

---

## 태그 네이밍 규칙

GameplayCue의 태그는 반드시 `"GameplayCue."` 로 시작해야 한다.

```
GameplayCue.Character.Death
GameplayCue.Weapon.Shoot.Impact
GameplayCue.Ability.Jump.Land
```

태그가 `"GameplayCue."` 로 시작하면 GAS가 자동으로 CueManager를 통해 처리한다.

---

## 두 종류의 GameplayCueNotify

| 클래스 | 트리거 이벤트 | GE 타입 | 인스턴스 생성 |
|---|---|---|---|
| `UGameplayCueNotify_Static` | `Executed` | Instant/Periodic GE | CDO 직접 실행 (인스턴스 없음) |
| `UGameplayCueNotify_Actor` | `OnActive` / `WhileActive` / `OnRemove` | Duration/Infinite GE | 월드에 Actor 생성 |

### 이벤트 4가지

| 이벤트 | 설명 | 신뢰성 |
|---|---|---|
| `OnActive` | GC 활성화 시 (늦게 참여한 플레이어는 놓침) | Autonomous: 신뢰성 있음, Simulated: Unreliable |
| `WhileActive` | GC 활성 중 (늦게 참여해도 수신됨, Tick 아님) | 신뢰성 있음 |
| `OnRemove` | GC 제거 시 | 신뢰성 있음 |
| `Executed` | Instant/Periodic GE 실행 시 | **Unreliable** — 유실 가능 |

> **신뢰성이 중요한 경우**: GE를 통해 GC를 적용하고, `WhileActive`에서 FX 추가, `OnRemove`에서 제거하는 패턴 사용.

---

## 트리거 방식

### 1. GE를 통한 트리거 (권장)

GE의 `GameplayCues` 항목에 태그를 추가한다.

- GE Duration/Infinite → `OnActive` + `WhileActive` + `OnRemove` 호출
- GE Instant/Periodic → `Executed` 호출

### 2. 코드에서 직접 트리거

```cpp
// Multicast RPC — 모든 클라이언트에 전달
ASC->ExecuteGameplayCue(Tag, Params);          // Instant
ASC->AddGameplayCue(Tag, Params);              // Duration 시작
ASC->RemoveGameplayCue(Tag);                   // Duration 종료

// 로컬 전용 — Multicast RPC 없음, 로컬만
ASC->ExecuteGameplayCueLocal(Tag, Params);
ASC->AddGameplayCueLocal(Tag, Params);
ASC->RemoveGameplayCueLocal(Tag, Params);
```

> **로컬 전용**은 발사체 충돌, 근접 히트, AnimNotify 같은 "클라이언트가 이미 아는" 이벤트에 적합.
> Multicast RPC 비용 없이 로컬에서 즉시 재생.

---

## 네트워크 처리

```
Instant GE Execute
    → Unreliable NetMulticast (유실 가능)

Duration/Infinite GE Add
    → Autonomous Proxy: 신뢰성 있음 (RPC)
    → Simulated Proxy: WhileActive/OnRemove는 신뢰성, OnActive는 Unreliable
```

`GameplayTag` / `GameplayCue`는 ASC의 Replication Mode와 무관하게 항상 NetMulticast로 전달된다.

---

## LyraGameplayCueManager

> 소스: `LyraGameplayCueManager.h/cpp`  
> 부모: `UGameplayCueManager`

기본 엔진 GameplayCueManager는 게임 시작 시 전체 경로를 스캔해 메모리에 올린다.
Lyra는 이를 커스터마이즈해 **지연 로딩(Delay Load)**을 구현한다.

### 로드 모드 (ELyraEditorLoadMode)

```cpp
enum class ELyraEditorLoadMode
{
    LoadUpfront,                        // 에디터: 전부 미리 로드 (PIE 빠름)
    PreloadAsCuesAreReferenced_GameOnly, // 게임 전용: 참조될 때 비동기 로드
    PreloadAsCuesAreReferenced          // 에디터+게임: 참조될 때 비동기 로드
};

// 현재 기본값
static ELyraEditorLoadMode LoadMode = ELyraEditorLoadMode::LoadUpfront;
```

### ShouldDelayLoadGameplayCues()

```cpp
bool ULyraGameplayCueManager::ShouldDelayLoadGameplayCues() const
{
    // 전용 서버가 아닌 경우 지연 로드 활성화
    const bool bClientDelayLoadGameplayCues = true;
    return !IsRunningDedicatedServer() && bClientDelayLoadGameplayCues;
}
```

전용 서버는 클라이언트 전용 비주얼 에셋을 로드할 필요가 없으므로,
클라이언트에서만 지연 로딩이 활성화된다.

### 지연 로딩 흐름

```
콘텐츠에서 GameplayCue 태그 로드됨
    │
    ▼
UGameplayTagsManager::OnGameplayTagLoadedDelegate
    │ OnGameplayTagLoaded() 호출
    ▼
LoadedGameplayTagsToProcess 큐에 추가
    │ GameThread에 비동기 태스크 디스패치
    ▼
ProcessLoadedTags()
    │ CueSet에서 태그 확인 → CueNotify 경로 획득
    ▼
ProcessTagToPreload()
    │ 이미 메모리에 있으면 → RegisterPreloadedCue()
    │ 없으면 → StreamableManager.RequestAsyncLoad()
    ▼
OnPreloadCueComplete() → RegisterPreloadedCue()
```

### 두 종류의 Preloaded Cue 관리

```cpp
TSet<UClass*> AlwaysLoadedCues;    // 항상 메모리에 유지 (코드 참조 or 명시적 지정)
TSet<UClass*> PreloadedCues;       // 콘텐츠 참조로 로드됨 (레퍼런서 소멸 시 제거)
TMap<FObjectKey, TSet<FObjectKey>> PreloadedCueReferencers;  // 참조자 추적
```

맵 로드 후(`PostLoadMap`) 참조자가 없는 Cue는 자동 제거 → 메모리 절약.

### 진단 명령

```
Lyra.DumpGameplayCues           // 현재 로드된 Cue 목록 + 참조자 출력
Lyra.DumpGameplayCues Refs      // 참조자 상세 포함
```

---

## 억제 / 수동 처리

```cpp
// ExecCalc에서 GameplayCue를 수동으로 제어할 때
OutExecutionOutput.MarkGameplayCuesHandledManually();

// ASC 전체 GC 비활성화 (특수 상황용)
AbilitySystemComponent->bSuppressGameplayCues = true;
```
