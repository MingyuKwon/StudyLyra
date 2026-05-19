# ASC 복제 컨테이너 전체 정리

> 소스: `/c/Program Files/Epic Games/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/AbilitySystemComponent.h`

GAS에서 복제되는 모든 정보는 `UAbilitySystemComponent` 멤버 변수에 보관된다.
컨테이너 7개 + AttributeSet 값 개별 복제로 구성된다.

---

## 컨테이너 전체 목록

```cpp
// 표준 복제 — UPROPERTY(Replicated), 서버→클라

UPROPERTY(ReplicatedUsing=OnRep_ActivateAbilities)
FGameplayAbilitySpecContainer ActivatableAbilities;     // 부여된 GA 스펙 목록

UPROPERTY(Replicated)
FActiveGameplayEffectsContainer ActiveGameplayEffects;  // 활성 GE 전체

UPROPERTY(Replicated, ReplicatedUsing=OnRep_SpawnedAttributes)
TArray<UAttributeSet*> SpawnedAttributes;               // AttributeSet 목록

UPROPERTY(Replicated)
FMinimalReplicationTagCountMap ReplicatedLooseTags;     // Loose GameplayTag (Full/Mixed 모드)

UPROPERTY(Replicated)
FMinimalReplicationTagCountMap MinimalReplicationTags;  // GE 유래 태그 (Minimal 모드 전용)

UPROPERTY(Replicated, Transient)
FReplicatedPredictionKeyMap ReplicatedPredictionKeyMap; // Prediction Key 확인 상태

// RPC로 채워짐 — UPROPERTY(Replicated) 없음, 클라→서버

FGameplayAbilityReplicatedDataContainer AbilityTargetDataMap; // TargetData + GenericEvents
```

---

## 한 눈에 비교

| 컨테이너 | 담는 것 | 복제 방식 | 방향 |
|---|---|---|---|
| `ActivatableAbilities` | 부여된 GA 스펙 | `UPROPERTY(Replicated)` | 서버→클라 |
| `ActiveGameplayEffects` | 활성 GE 전체 | `UPROPERTY(Replicated)` | 서버→클라 |
| `SpawnedAttributes` | AttributeSet 목록 | `UPROPERTY(Replicated)` | 서버→클라 |
| `ReplicatedLooseTags` | Loose GameplayTag | `UPROPERTY(Replicated)` | 서버→클라 |
| `MinimalReplicationTags` | GE 유래 태그 (Minimal) | `UPROPERTY(Replicated)` | 서버→클라 |
| `ReplicatedPredictionKeyMap` | Prediction Key 상태 | `UPROPERTY(Replicated)` | 서버→클라 |
| **`AbilityTargetDataMap`** | **TargetData + GenericEvents** | **RPC** | **양방향** |

> **참고**  
> Attribute 값 자체는 이 표에 없다.
> AttributeSet의 각 프로퍼티(`UPROPERTY(ReplicatedUsing=OnRep_Health)` 등)가 개별적으로 복제된다.
> `ActiveGameplayEffects`가 값을 수정하면 그 결과가 AttributeSet 멤버 변수에 반영되고, 해당 프로퍼티가 다시 클라이언트로 복제되는 구조다.

---

## AbilityTargetDataMap만 RPC를 쓰는 이유

나머지 6개는 **서버가 권위를 갖고 클라에 뿌리는** 단방향 데이터다.
`AbilityTargetDataMap`은 다르다. 안에 담긴 두 종류의 데이터가 방향이 서로 다르다.

### TargetData — 클라→서버 단방향

클라이언트가 로컬에서 레이캐스트·타게팅을 먼저 수행하고, 그 결과를 서버에 올려 검증받는다.

```
[클라이언트]
  로컬 레이캐스트 → TargetData 생성
  CallServerSetReplicatedTargetData() ──RPC──▶ [서버]
                                                AbilityTargetDataMap에 저장
                                                AbilityTargetDataSetDelegate.Broadcast()
                                                → GE Apply
```

### GenericReplicatedEvent — 양방향

신호 슬롯마다 방향이 다르다. 서버→클라 방향도 존재한다.

```
클라→서버:  ServerSetReplicatedEvent() RPC → 서버에서 InvokeReplicatedEvent()
서버→클라:  ClientSetReplicatedEvent() RPC → 클라에서 InvokeReplicatedEvent()
```

| 슬롯 | 방향 |
|---|---|
| `InputPressed` / `InputReleased` | 클라→서버 |
| `GenericConfirm` / `GenericCancel` | 클라→서버 |
| `GenericSignalFromClient` | 클라→서버 |
| `GenericSignalFromServer` | **서버→클라** |
| `GameCustom1~6` | 게임 코드가 결정 |

표준 복제 시스템(`UPROPERTY(Replicated)`)은 항상 서버→클라 단방향이라 이 양방향 패턴을 표현할 수 없다. 그래서 RPC를 직접 쓴다.

`AbilityTargetDataMap`의 내부 구조는 GA 인스턴스 단위(`Handle + PredictionKey`)로 키를 나누며,
이름이 "TargetDataMap"인 이유는 원래 `WaitTargetData`용으로 설계됐다가 나중에 GenericEvents가 합류했기 때문이다.

---

`AbilityTargetDataMap`이 `UPROPERTY(Replicated)`가 없다는 사실이 중요하다.
"GAS에서 동기화되는 정보"를 찾을 때 나머지 6개는 헤더에서 `Replicated` 키워드로 바로 찾을 수 있지만,
TargetData는 RPC 경로를 타기 때문에 헤더만 보면 복제 여부가 보이지 않는다.

6개 표준 복제 컨테이너는 모두 서버→클라 단방향이다.
`AbilityTargetDataMap`만 RPC를 쓰는데, 그 안의 TargetData는 클라→서버, GenericEvent는 양방향으로 방향이 서로 다르다.
`UPROPERTY(Replicated)`는 서버→클라만 표현할 수 있어서, 클라→서버나 양방향이 필요한 이 데이터는 RPC를 직접 써야 한다.
