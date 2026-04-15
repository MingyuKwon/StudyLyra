---
name: GAS Documentation Cache
description: GASDocumentation(tranek) 전체 내용 요약 캐시. 세션 간 GAS 개념 재학습 없이 참조용. Part1~5 소화 완료.
type: project
---

# GAS Documentation 캐시

> 출처: https://github.com/tranek/GASDocumentation (한국어 번역본 기준, kkadalg.tistory.com)
> 이 파일만 읽으면 GAS doc 전체를 다시 읽지 않아도 된다.
> lyra_gas_analysis.md 와 함께 사용: 이 파일 = 범용 GAS 엔진 개념, lyra_gas_analysis.md = Lyra 소스 직접 확인 내용

---

## 1. ASC (Ability System Component)

- **위치 원칙**: 리스폰 불필요 Actor → Owner=Avatar 동일. 리스폰 필요 → Owner=PlayerState, Avatar=Pawn (PlayerState는 항상 replicated)
- **초기화**: `InitAbilityActorInfo(Owner, Avatar)` — 서버: BeginPlay/Possess, 클라이언트: OnRep_PlayerState
- **Replication Mode**:
  - `Full`: 모든 GE → 모든 클라이언트. 싱글플레이어만.
  - `Mixed`: GE → Owner만 복제. 플레이어 제어 캐릭터용.
  - `Minimal`: GE 복제 안 함. AI 제어 캐릭터용.
  - GameplayTag / GameplayCue는 모드와 무관하게 항상 NetMulticast.
- **같은 Owner에 ASC 여러 개**: 비추천. IAbilitySystemInterface에서 어느 ASC를 반환할지 애매함.

---

## 2. GameplayTag

- `FGameplayTag` (단일) / `FGameplayTagContainer` (집합)
- 계층구조: `A.B.C`는 `A.B`의 자식. HasTag("A.B")는 "A.B.C"를 포함하지 않음. HasTag with Exact=false 이면 부모도 매칭.
- `UFUNCTION` 파라미터로 쓸 때: `FGameplayTagContainer` 사용 권장 (단일 태그도 컨테이너로).
- 런타임 추가/제거: `AddLooseGameplayTag` / `RemoveLooseGameplayTag` (복제 안 됨 → 서버+클라이언트 모두 호출 or `AddReplicatedLooseGameplayTag`).
- GE 부여 태그: GE Duration/Infinite → ASC에 태그 자동 추가, GE 제거 시 자동 제거.

---

## 3. Attribute

- `FGameplayAttributeData`: BaseValue + CurrentValue 두 개 저장.
- `FGameplayAttribute`: 특정 AttributeSet의 FGameplayAttributeData 프로퍼티를 가리키는 핸들(포인터).
- **Instant GE** → BaseValue 영구 변경 → CurrentValue = BaseValue (Aggregator 없을 때)
- **Duration/Infinite GE** → Aggregator에 Modifier 등록 → CurrentValue = 재계산값. BaseValue 불변.
- Clamp: `PreAttributeChange`에서 NewValue 수정 가능하지만 Aggregator 내부 Modifier 값은 변하지 않음 → MaxHealth 감소 시 `PostAttributeChange`에서 Health를 Override GE로 강제 조정해야 함.
- Meta Attribute: replicate 안 함, Pre/PostGameplayEffectExecute에서 소비하고 0으로 초기화. GE 적용 후 실제 attribute에 반영하는 패턴.

### ATTRIBUTE_ACCESSORS 매크로 생성 함수
```
GetXxx()   → Xxx.GetCurrentValue()
SetXxx(v)  → ASC->SetNumericAttributeBase(attr, v)   // Aggregator 경유
InitXxx(v) → Xxx.SetBaseValue(v); Xxx.SetCurrentValue(v)  // 직접, 초기화 전용
```

---

## 4. AttributeSet

- 설계: 한 AttributeSet에 너무 많은 Attribute 넣지 말 것. 기능별로 분리 (HealthSet, CombatSet 등).
- **자동 등록**: `CreateDefaultSubobject` → Owner의 서브오브젝트 → `InitializeComponent()`가 `GetObjectsWithOuter(Owner)` 스캔 → `SpawnedAttributes.AddUnique()`.
- **수동 등록**: `NewObject<UAttributeSet>(ASC->GetOwner(), Class)` + `ASC->AddAttributeSetSubobject()`. 제거: `RemoveSpawnedAttribute()`.
- ASC는 같은 AttributeSet 클래스 인스턴스를 하나만 기대함.
- 블루프린트 Actor 복제 버그: AttributeSet 포인터 nullptr될 수 있음 → `PostInitializeComponents()`에서 `AbilitySystemComponent->AddSet<UXxxAttributeSet>()` 으로 우회.

### 콜백 순서
```
PreGameplayEffectExecute(Data) → false 반환 시 GE 취소 가능
PreAttributeBaseChange(Attr, NewValue&) → Instant GE / SetXxx 호출 시 Clamp
PreAttributeChange(Attr, NewValue&) → Duration GE Aggregator 재계산 시 Clamp
[실제 값 반영]
PostGameplayEffectExecute(Data) → Meta 소비, 이벤트 발행
PostAttributeChange(Attr, OldValue, NewValue) → 파생값 수동 조정
```

### OnAttributeAggregatorCreated
- 첫 Duration/Infinite GE 적용 시 Aggregator 생성 → 이 콜백 호출
- `FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods` 설정 시:
  - 네거티브 Modifier 중 가장 큰 것만 적용, 포지티브는 모두 적용
  - Paragon 둔화 스택처럼 "중첩 안 되고 가장 강한 것만 적용" 구현에 사용

### GAMEPLAYATTRIBUTE_REPNOTIFY
```cpp
GAMEPLAYATTRIBUTE_REPNOTIFY(UMyAttributeSet, Health, OldHealth)
// 내부: SetBaseAttributeValueFromReplication() 호출
// → 예측된 클라이언트 값을 서버 값으로 되감음(rewind)
```
- `REPNOTIFY_Always` 필수: 로컬 예측값과 서버값이 같아도 OnRep 강제 호출해야 예측 롤백 동작.

---

## 5. GameplayEffect (GE)

### 5.1 Duration 타입
| 타입 | 동작 |
|---|---|
| Instant | 즉시 적용, BaseValue 영구 변경 |
| Duration | 지정 시간 후 자동 제거 |
| Infinite | 수동 제거할 때까지 유지 |

- **Periodic**: Duration/Infinite GE에 Period 설정 → 주기적으로 Instant처럼 적용.
- **Ongoing Tag Requirements**: Required/Ignored Tags 충족 안 하면 GE 일시 비활성화(Inhibit).

### 5.2 Apply / Remove
```cpp
// Apply
FActiveGameplayEffectHandle Handle = ASC->ApplyGameplayEffectSpecToSelf(*Spec, PredictionKey);
// 콜백: OnActiveGameplayEffectAddedDelegateToSelf

// Remove
int32 Removed = ASC->RemoveActiveEffects(RemoveQuery, StackCount);
// 콜백: OnAnyGameplayEffectRemovedDelegate
```

### 5.3 Modifier (4가지 Op)
- `Additive`: += Magnitude
- `Multiplicitive`(오탈자): *= Magnitude — 실제 계산은 **덧셈 기반** `1 + (m1-1) + (m2-1) + ...`
- `Division`: /= Magnitude
- `Override`: 마지막 Override 값으로 덮어씀

### 5.4 Stacking
- `Aggregate by Source`: 소스별로 스택 분리
- `Aggregate by Target`: 타겟 기준으로 단일 스택

### 5.5 GE Tags 7가지
| 태그 유형 | 동작 |
|---|---|
| Asset Tags | GE 자체를 설명하는 태그 |
| Granted Tags | GE 활성화 중 ASC에 부여 |
| Ongoing Required Tags | 이 태그 없으면 GE Inhibit |
| Ongoing Ignored Tags | 이 태그 있으면 GE Inhibit |
| Application Required Tags | 이 태그 없으면 GE 적용 불가 |
| Application Ignored Tags | 이 태그 있으면 GE 적용 불가 |
| Remove GEs with Tags | GE 적용 시 이 태그를 가진 기존 GE 제거 |

### 5.6 Immunity
- ASC에 `AddGameplayTagImmunity(Query)` 또는 `IgnoreEffectsWithTags` 설정
- `PreGameplayEffectExecute`에서 false 반환으로도 차단 가능

### 5.7 GESpec + SetByCaller
```cpp
FGameplayEffectSpecHandle Spec = ASC->MakeOutgoingSpec(GEClass, Level, Context);
Spec.Data->SetByCallerTagMagnitudes.Add(Tag, Value);  // Tag 기반
Spec.Data->SetByCallerNameMagnitudes.Add(Name, Value); // Name 기반
```
- Modifier의 Magnitude 타입을 SetByCaller로 설정하면 런타임에 값 주입 가능.

### 5.8 MMC (ModifierMagnitudeCalculation)
- `CalculateBaseMagnitude_Implementation()` 오버라이드
- 여러 Attribute Capture 가능 (Source/Target, Snapshot/Non-snapshot)
- **Snapshot**: GE Spec 생성 시점 값. **Non-snapshot**: 매 계산 시 현재 값.
- Duration/Infinite GE → backing attribute 변경 시 자동 재계산 (non-snapshot일 때)
- 예측 가능 (ExecCalc과 달리)

### 5.9 ExecCalc (GameplayEffectExecutionCalculation)
- `Execute_Implementation()` 오버라이드
- **서버 전용** (`#if WITH_SERVER_CODE`), 예측 불가
- 여러 Attribute 읽기 + 여러 Attribute 쓰기 가능
- 4가지 데이터 전달: SetByCaller / Backing Attribute / Temp Variable / EffectContext

### 5.10 Cost GE
- Instant GE로 Attribute에서 Cost만큼 차감
- 재사용: `GetCostGameplayEffect()` 오버라이드 또는 MMC로 여러 Ability가 같은 GE 공유

### 5.11 Cooldown GE
- Duration GE + Granted Tag 패턴
- 재사용: `GetCooldownTags()` + `ApplyCooldown()` 오버라이드, SetByCaller로 시간 주입
- 남은 시간 조회: `GetCooldownTimeRemainingAndDuration()`
- **예측 불가**: GE 제거 예측이 불가능하기 때문 → 높은 지연 클라이언트 불이익 있음
- Fortnite는 자체 쿨다운 관리 (GE 미사용)

### 5.12 Dynamic GE 런타임 생성
- **Instant GE만** 런타임에 `NewObject<UGameplayEffect>` 로 생성 가능
- Duration/Infinite는 CDO 기반이라 런타임 생성 불안정

### 5.13 GameplayEffectContainer (ActionRPG 패턴)
- GESpec + TargetData + 간단 타겟팅을 묶은 구조체
- Projectile에 GESpec 넘겨서 나중에 충돌 시 적용하는 패턴에 유용

---

## 6. GameplayAbility (GA)

### 6.1 기본
- `ActivateAbility()` 오버라이드 필수. `EndAbility()`에 정리 로직.
- 소유 클라이언트 또는 서버에서만 실행. Simulated Proxy는 실행 안 함.
- `AbilityTask`로 비동기 작업 처리 (시간 경과, 델리게이트 대기).

### 6.2 옵션 (비추천)
- `Replication Policy`: 사용 말 것 (향후 제거 예정)
- `Server Respects Remote Ability Cancellation`: 비활성화 권장 (높은 지연 시 문제)
- `Replicate Input Directly`: 사용 말 것 (Generic Replicated Event 사용)

### 6.3 Input 바인딩
- Enum으로 InputID 정의 → `BindAbilityActivationToInputComponent()`
- ASC가 PlayerState에 있으면 race condition 가능 → `SetupPlayerInputComponent()` + `OnRep_PlayerState()` 양쪽에서 바인딩 시도, bool로 중복 방지.
- 자동 활성화 없이 AbilityTask 입력만 받으려면: `AbilityLocalInputPressed()` 오버라이드 + `bActivateOnInput` bool 추가.

### 6.4 부여 (Grant)
```cpp
ASC->GiveAbility(FGameplayAbilitySpec(AbilityClass, Level, InputID, SourceObject));
// 서버에서만. → 자동으로 소유 클라이언트에 Spec 복제됨.
```

### 6.5 활성화 4가지 방법
```cpp
TryActivateAbilitiesByTag(TagContainer)
TryActivateAbilityByClass(Class)
TryActivateAbility(SpecHandle)
TriggerAbilityFromGameplayEvent(Handle, ActorInfo, Tag, Payload, ASC)
```
- 이벤트 활성화: GA에 Trigger 설정(Tag + GameplayEvent 옵션) 필요. `SendGameplayEventToActor()` 사용.

### 6.6 로컬 예측 활성화 순서
```
클라이언트: TryActivateAbility → InternalTryActivateAbility → CanActivateAbility
  → CallServerTryActivateAbility(PredictionKey) → CallActivateAbility → PreActivate → ActivateAbility

서버: ServerTryActivateAbility → InternalTryActivateAbility → CanActivateAbility
  → 성공: ClientActivateAbilitySucceed → CallActivateAbility → PreActivate → ActivateAbility
  → 실패: ClientActivateAbilityFailed → 클라이언트 GA 즉시 종료 + 예측 롤백
```

### 6.7 패시브 GA
- `OnAvatarSet()` 오버라이드 → `TryActivateAbility(Spec.Handle, false)`
- Net Execution Policy: Server Only 권장

### 6.8 취소
```cpp
CancelAbility(Ability)            // CDO 기준
CancelAbilityHandle(Handle)       // Spec Handle 기준
CancelAbilities(WithTags, WithoutTags, Ignore)
CancelAllAbilities(Ignore)
```

### 6.9 Instancing Policy
| Policy | 설명 | 주의 |
|---|---|---|
| Instanced Per Actor | ASC당 1개 인스턴스 재사용 | 가장 일반적. 변수 수동 리셋 필요 |
| Instanced Per Execution | 활성화마다 새 인스턴스 | 성능 나쁨 |
| Non-Instanced | CDO에서 직접 실행 | 상태 저장 불가, AbilityTask 델리게이트 바인딩 불가. 가장 빠름 |

### 6.10 Net Execution Policy
| Policy | 설명 |
|---|---|
| Local Only | 소유 클라이언트에서만 |
| Local Predicted | 클라이언트 먼저 → 서버에서 검증 |
| Server Only | 서버에서만 (패시브 GA 기본) |
| Server Initiated | 서버 먼저 → 소유 클라이언트 |

### 6.11 GA 태그 9가지
| 태그 컨테이너 | 동작 |
|---|---|
| Ability Tags | 이 GA를 설명하는 태그 |
| Cancel Abilities with Tag | 이 GA 활성화 시 해당 태그 GA 취소 |
| Block Abilities with Tag | 이 GA 활성화 중 해당 태그 GA 차단 |
| Activation Owned Tags | 활성화 중 소유자에게 부여 (복제 안 됨) |
| Activation Required Tags | 소유자가 모두 가져야 활성화 가능 |
| Activation Blocked Tags | 소유자가 가지면 활성화 불가 |
| Source Required Tags | 소스가 모두 가져야 (이벤트 트리거 시만) |
| Source Blocked Tags | 소스가 가지면 불가 (이벤트 트리거 시만) |
| Target Required Tags | 타겟이 모두 가져야 (이벤트 트리거 시만) |

### 6.12 GameplayAbilitySpec
- GA 부여 후 ASC에 존재. GA 클래스 + 레벨 + InputID + SourceObject + 런타임 상태.
- 서버 → 소유 클라이언트로 복제. Simulated Proxy는 받지 않음.

### 6.13 데이터 전달 4가지
| 방법 | 복제 | 입력 바인딩 |
|---|---|---|
| Event Payload | 로컬 예측 GA면 클→서 복제 | 불가 |
| WaitGameplayEvent AbilityTask | AbilityTask가 복제 안 함 → Local Only/Server Only만 | 가능 |
| TargetData | 클↔서 전달 | 가능 |
| OwnerActor/AvatarActor 변수 | 리플리케이트 변수 | 가능, 동기화 타이밍 주의 |

### 6.14 Ability Batching
- 한 프레임 내 Activate + TargetData + End → 3 RPC → 1 RPC로 압축
- `ShouldDoServerAbilityRPCBatch()` override → true 반환
- `FScopedServerAbilityRPCBatcher` 범위 안에서 `TryActivateAbility()` 호출
- C++에서 `FGameplayAbilitySpecHandle`로만 활성화 가능

### 6.15 Net Security Policy
| Policy | 설명 |
|---|---|
| ClientOrServer | 제한 없음 |
| ServerOnlyExecution | 클라이언트 실행 요청 무시 |
| ServerOnlyTermination | 클라이언트 취소/종료 요청 무시 |
| ServerOnly | 서버가 완전히 제어 |

### 6.16 레벨업 2가지 방법
1. Ungrant → Regrant at new level (활성 GA 종료됨)
2. SpecHandle로 찾아서 Spec.Level++ → MarkArrayDirty (활성 GA 종료 안 됨)

---

## 7. AbilityTask (AT)

- GA는 한 프레임에서만 실행 → 비동기 작업은 AbilityTask 사용
- 전역 동시 실행 한도: **1000개** (생성자에서 설정)
- 소유 클라이언트 또는 서버에서만 실행 (GA를 실행하는 쪽)
- Simulated 클라이언트에서도 실행하려면: `bSimulatedTask = true` + `InitSimulatedTask()` 오버라이드 + 변수 복제 (RootMotionSource AT들이 이 방식)

### 구조
- 정적 팩토리 함수 (인스턴스 생성)
- 완료 시 발행할 델리게이트들
- `Activate()`: 주요 작업 시작, 외부 델리게이트 바인딩
- `OnDestroy()`: 바인딩 해제 등 정리
- C++에서 사용: `Task->ReadyForActivation()` 수동 호출 필요
- Blueprint: K2Node_LatentGameplayTaskCall이 자동으로 ReadyForActivation 호출

### Tick 지원
- 생성자에서 `bTickingTask = true` + `TickTask(float DeltaTime)` 오버라이드

---

## 8. GameplayCue (GC)

### 8.1 기본
- 비게임플레이 작업 (사운드, 파티클, 카메라 흔들기) 전용
- GameplayTag는 반드시 **"GameplayCue."** 로 시작
- 이벤트: Execute(Instant/Periodic GE), Add(Duration/Infinite GE 적용), Remove(GE 제거)

### 8.2 두 종류
| 클래스 | 이벤트 | GE 타입 | 인스턴스 |
|---|---|---|---|
| GameplayCueNotify_Static | Execute | Instant/Periodic | CDO (인스턴스 없음) |
| GameplayCueNotify_Actor | Add/Remove | Duration/Infinite | 인스턴스 생성 |

### 8.3 로컬 GC (ASC 서브클래스에 추가)
```cpp
ExecuteGameplayCueLocal(Tag, Params)  // Multicast RPC 안 함, 로컬만
AddGameplayCueLocal(Tag, Params)
RemoveGameplayCueLocal(Tag, Params)
```
- 발사체 충돌, 근접 충돌, 몽타주 AnimNotify에 적합

### 8.4 신뢰성
- Execute: Unreliable Multicast → 유실 가능
- GE를 통해 추가된 GC:
  - Autonomous Proxy: OnActive/WhileActive/OnRemove 신뢰성 있음
  - Simulated Proxy: WhileActive/OnRemove 신뢰성 있음, OnActive는 Unreliable
- **신뢰성 필요 시**: GE를 통해 적용 + WhileActive에서 FX 추가, OnRemove에서 제거

### 8.5 Manager
- 기본: 게임 디렉토리 전체 스캔, 게임 시작 시 메모리 로드
- 최적화: `ShouldAsyncLoadRuntimeObjectLibraries()` → false 반환 → 트리거 시 지연 로드
- 경로 제한: DefaultGame.ini `GameplayCueNotifyPaths` 설정

### 8.6 이벤트 4가지
| 이벤트 | 설명 |
|---|---|
| OnActive | GC 활성화될 때 (늦게 참여한 플레이어 놓침) |
| WhileActive | GC 활성 중 (늦게 참여해도 보임, Tick 아님) |
| Removed | GC 제거될 때 |
| Executed | Instant/Periodic GE 실행될 때 |

### 8.7 억제 / 수동 처리
- `ExecCalc`에서 `OutExecutionOutput.MarkGameplayCuesHandledManually()` → 수동으로 GC 전송
- `AbilitySystemComponent->bSuppressGameplayCues = true` → ASC 전체 GC 비활성화

---

## 9. AbilitySystemGlobals

- DefaultGame.ini:
  ```ini
  [/Script/GameplayAbilities.AbilitySystemGlobals]
  AbilitySystemGlobalsClassName="/Script/MyGame.MyAbilitySystemGlobals"
  GlobalGameplayCueManagerClass="/Script/MyGame.MyGameplayCueManager"
  GameplayCueNotifyPaths="/Game/GAS"
  ```
- **InitGlobalData()**: UE 4.24~5.2에서 TargetData 사용 전 필수 호출 (UE 5.3+는 자동). `UAssetManager::StartInitialLoading()`에서 호출 권장.
- `InitGameplayCueParameters()` 3개 가상 함수 오버라이드 → FGameplayCueParameters 자동 채우기 커스터마이즈

---

## 10. Prediction (예측)

### 10.1 예측 가능 / 불가
**가능**: Ability 활성화, 트리거 이벤트, GE 적용, Attribute 수정(ExecCalc 제외), GameplayTag 수정, GameplayCue, 몽타주, 이동
**불가**: GE 제거, GE 주기적 효과, ExecCalc

### 10.2 Prediction Key 동작
1. 클라이언트: Activation Prediction Key 생성
2. `CallServerTryActivateAbility(PredictionKey)` 전송
3. 클라이언트: 유효 키 범위 내 GE에 키 태그
4. 서버: 수신한 키로 GE에 태그 → 클라이언트로 복제
5. 클라이언트: 서버에서 같은 키의 GE 받으면 → 예측 GE 제거 (정확한 예측)
6. 클라이언트: Replicated Key stale 처리 → stale 키 GE 모두 제거 (서버 복제본 유지)

### 10.3 Scoped Prediction Window
- AbilityTask 콜백에서는 이미 예측 키 만료됨
- `WaitNetSync (OnlyServerWait)` AbilityTask로 새 Scoped Prediction Key 생성
  - 클라이언트: 새 키 생성 → 서버 RPC
  - 서버: 클라이언트 키 받을 때까지 대기
- 입력 관련 AT들은 자동으로 새 예측 창 생성

### 10.4 Actor 생성 예측
- GAS 기본 미지원. `SpawnActor AT`는 서버 전용.
- 장식용: `IsNetRelevantFor()` 오버라이드로 Owner에겐 로컬 버전, 타인에겐 서버 복제 버전 표시
- 게임플레이 영향 있는 경우 (발사체 등): 더미 클라이언트 Actor + 서버 복제 Actor 동기화 필요 (고급)

### 10.5 알려진 한계
- Cooldown 예측 불가 → 높은 지연 플레이어 불이익 (Fortnite는 자체 관리)
- GE 제거 예측 불가 → 우회: 반대 효과 GE를 예측 적용 후 둘 다 제거
- Dave Ratti: V2 계획 (GE 제거 예측, 지연 보정, Network Prediction Plugin 통합 등)

---

## 11. Targeting

### 11.1 TargetData
- `FGameplayAbilityTargetData`: 네트워크 전달용 타겟 데이터 베이스 구조체
- 서브클래싱 시 `GetScriptStruct()` + `NetSerialize()` + `TStructOpsTypeTraits::WithNetSerializer=true` 필수
- `FGameplayAbilityTargetDataHandle`: TArray<FGameplayAbilityTargetData*> 래퍼 (다형성 지원)
- 꺼낼 때 타입 체크: `Data->GetScriptStruct() == FMyTargetData::StaticStruct()` 확인 후 `static_cast`

### 11.2 TargetActor
- `WaitTargetData AbilityTask`가 TargetActor 생성/파괴 관리
- Tick에서 트레이스/오버랩 수행 (Instant 타입은 제외)
- `ShouldProduceTargetDataOnServer`: false → 클라이언트가 TargetData RPC로 전송, true → 서버에서 직접 생성

### 11.3 EGameplayTargetingConfirmation
| 타입 | 설명 |
|---|---|
| Instant | 즉시 생성 |
| UserConfirmed | Confirm 입력 대기 |
| Custom | `ConfirmTaskByInstanceName()` 호출 시 |
| CustomMulti | Custom이지만 AbilityTask 종료 안 함 |

### 11.4 GameplayEffect Container Targeting
- CDO에서 실행 → Actor 생성/파괴 없음 → 성능 우수
- 클라이언트+서버 양쪽에서 즉시 실행
- 플레이어 입력 없음, 취소 불가, 클→서 데이터 전송 불가

---

## 12. 일반 구현 패턴

### 12.1 스턴
- Duration/Infinite GE + Stun GameplayTag 부여
- Tag 추가 시: `ASC->CancelAbilities()` 호출
- GA의 `Activation Blocked Tags`에 Stun 태그 설정
- `CharacterMovementComponent::GetMaxSpeed()` 오버라이드 → Stun 태그 있으면 0 반환

### 12.2 스프린트
- GA에서 CMC에 플래그 전달 → CMC에서 예측적으로 이동 속도 처리
- WaitNetSync로 Scoped Prediction Window 생성 → 스태미나 비용 예측 가능

### 12.3 생명력 흡수 (Lifesteal)
- ExecCalc 내에서 처리
- GESpec에 `Effect.Damage.CanLifesteal` 태그 확인
- 있으면: 동적 Instant GE 생성 → 소스 ASC에 적용

```cpp
UGameplayEffect* GELifesteal = NewObject<UGameplayEffect>(GetTransientPackage(), TEXT("Lifesteal"));
GELifesteal->DurationPolicy = EGameplayEffectDurationType::Instant;
// Modifier 추가 후:
SourceASC->ApplyGameplayEffectToSelf(GELifesteal, 1.0f, SourceASC->MakeEffectContext());
```

### 12.4 크리티컬 히트
- ExecCalc 내에서 처리 (서버 전용이라 난수 동기화 불필요)
- `Effect.CanCrit` 태그 + 크리티컬 확률/데미지 Attribute Capture

### 12.5 중첩 없는 최대값만 적용 (Paragon 둔화)
- `OnAttributeAggregatorCreated` + `FAggregatorEvaluateMetaDataLibrary::MostNegativeMod_AllPositiveMods` 사용

### 12.6 클라이언트-서버 동일 난수
- Activation Prediction Key를 Random Seed로 사용 (매 게임 동일 시퀀스)
- 또는 이벤트 페이로드로 시드 전달 (더 무작위지만 해킹 취약)

### 12.7 일시정지 중 TargetData
- `SetGlobalTimeDilation(0)` 대신 `slomo 0` 사용

---

## 13. 디버깅

### 13.1 showdebug abilitysystem
콘솔 명령: `showdebug abilitysystem`
- 페이지 1: 모든 Attribute 현재값
- 페이지 2: Duration/Infinite GE 목록, 스택, 태그, Modifier
- 페이지 3: 부여된 GA 목록, 활성화 상태, 차단 여부, AT 상태
- 페이지 전환: `AbilitySystem.Debug.NextCategory`
- 타겟 전환: `PageUp/Down` 또는 `NextDebugTarget/PreviousDebugTarget`

### 13.2 Gameplay Debugger
- `'` (아포스트로피) 키 → 숫자패드 3으로 Ability 카테고리
- 다른 캐릭터 Tags/GE/GA 확인 가능 (Attribute CurrentValue는 안 보임)

### 13.3 GAS 로그 카테고리
```
log LogAbilitySystem VeryVerbose    // 상세 로그 켜기
log LogAbilitySystem Display        // 기본값으로 복원
```
주요 카테고리: `LogAbilitySystem`, `LogAbilitySystemComponent`, `LogGameplayCueDetails`, `LogGameplayEffectDetails`, `LogGameplayEffects`, `LogGameplayTags`

---

## 14. 최적화

### 14.1 Replication Mode 설정
- 플레이어 ASC: `Mixed`
- AI ASC: `Minimal`
- 싱글 플레이: `Full`

### 14.2 Attribute Proxy Replication (Fortnite 패턴)
- 시뮬레이션된 플레이어 제어 프록시: ASC 복제 비활성화
- Pawn에 최소 Attribute 프록시 구조체 → 복제 → 클라이언트에서 ASC로 역 푸시
- 장점: Pawn 관련성 활용 + 데이터 최소화
- 대규모 멀티플레이어 (100명+)에서 유효

### 14.3 ASC 지연 Loading
- 피해 입힐 수 있는 환경 오브젝트 등: 처음 피해를 받을 때 ASC 생성

### 14.4 GC 배치
- `FScopedGameplayCueSendContext` → `FlushPendingCues()` 지연
- `AbilitySystem.AlwaysConvertGESpecToGCParams 1` → GESpec 대신 경량 FGameplayCueParameters 전송

---

## 15. 문제 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| `Can't activate LocalOnly ability when not local` | 클라이언트에서 ASC 미초기화 | 클라이언트에서 `InitAbilityActorInfo` 호출 확인 |
| ScriptStructCache 오류 | `InitGlobalData()` 미호출 | `UAssetManager::StartInitialLoading()`에서 `UAbilitySystemGlobals::Get().InitGlobalData()` 호출 |
| 애니메이션 몽타주 클라이언트 미복제 | `PlayMontage` 노드 사용 | `PlayMontageAndWait` AbilityTask 사용 (ASC 통해 자동 복제) |
| Blueprint 복제 Actor에서 AttributeSet nullptr | UE 버그 | `PostInitializeComponents()`에서 `ASC->AddSet<UMyAttributeSet>()` 사용 |
| `MarkPropertyDirty` 링크 오류 | `WITH_PUSH_MODEL` 충돌 | Build.cs `PublicDependencyModuleNames`에 `"NetCore"` 추가 |
| Enum 이름 경고 (UE5.1+) | `FString` 대신 `FTopLevelAssetPath` 필요 | `FTopLevelAssetPath(FName("/Script/Module"), FName("EEnumName"))` 사용 |

---

## 16. Dave Ratti Q&A 핵심 요약

- **멀티플레이 권장 Replication Mode**: 플레이어=Mixed, AI=Minimal
- **ASC 위치**: 리스폰 필요 → PlayerState에. 리스폰 불필요 → Actor 자체에.
- **같은 Owner에 ASC 여러 개**: 가능하지만 `IAbilitySystemInterface` 반환 대상 애매 → 비추천
- **GE 제거 예측 불가**: 우회책으로 반대 효과 GE 예측 적용. 근본 해결은 향후 V2 과제.
- **높은 지연 쿨다운 불이익**: Fortnite는 GE 미사용 자체 관리로 해결.
- **WaitNetSync 치팅 취약점**: 클라이언트가 서버 신호를 지연시켜 타이밍 조작 가능. Paragon은 최대 대기 시간 타임아웃으로 대응.
- **GAS V2 우선순위**: CMC 연동 개선, GE 제거 예측, 지연 보정, RPC 배치 일반화, ReplicationPolicy/InstancingPolicy 제거, FGameplayAbilitySpec을 서브클래싱 가능 UObject로 교체.

---

## 17. 약어 표

| 약어 | 전체 이름 |
|---|---|
| ASC | AbilitySystemComponent |
| AT | AbilityTask |
| CMC | CharacterMovementComponent |
| GA | GameplayAbility |
| GAS | GameplayAbilitySystem |
| GC | GameplayCue |
| GE | GameplayEffect |
| ExecCalc | GameplayEffectExecutionCalculation |
| GT | GameplayTag |
| MMC | ModifierMagnitudeCalculation |
