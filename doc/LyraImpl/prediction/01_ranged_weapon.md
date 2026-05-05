# 발사 Prediction 흐름 — LyraGameplayAbility_RangedWeapon

> 출처: `Source/LyraGame/Weapons/LyraGameplayAbility_RangedWeapon.cpp`

---

## 전체 흐름

```
ActivateAbility()
  └─ AbilityTargetDataSetDelegate에 OnTargetDataReadyCallback 등록

(Blueprint에서) StartRangedWeaponTargeting() 호출
  └─ FScopedPredictionWindow 생성
  └─ PerformLocalTargeting() → 클라이언트 로컬 라인 트레이스
  └─ FGameplayAbilityTargetDataHandle 생성 (히트마다 SingleTargetHit 추가)
  └─ WeaponStateComponent->AddUnconfirmedServerSideHitMarkers() → 미확인 히트마커 등록
  └─ OnTargetDataReadyCallback() 즉시 호출

OnTargetDataReadyCallback()
  ├─ [클라이언트] CallServerSetReplicatedTargetData RPC → 서버에 TargetData 전송
  ├─ [서버] 히트 검증 → ClientConfirmTargetData RPC → 클라이언트 히트마커 확정
  ├─ CommitAbility() → 쿨다운/비용 처리
  ├─ WeaponData->AddSpread() → 연사 시 탄퍼짐 증가
  └─ OnRangedWeaponTargetDataReady() → BP 이벤트 (GE 적용 등)

EndAbility()
  └─ delegate 제거
  └─ ConsumeClientReplicatedTargetData() → 캐시 정리
```

---

## 1단계 — ActivateAbility

```cpp
OnTargetDataReadyCallbackDelegateHandle =
    MyAbilityComponent->AbilityTargetDataSetDelegate(
        CurrentSpecHandle,
        CurrentActivationInfo.GetActivationPredictionKey()  // 이 활성화의 PredictionKey
    ).AddUObject(this, &ThisClass::OnTargetDataReadyCallback);
```

TargetData가 준비됐을 때 호출할 콜백을 **PredictionKey를 키로** ASC에 등록한다.  
클라이언트와 서버 양쪽에서 각자 등록한다.

---

## 2단계 — StartRangedWeaponTargeting (클라이언트)

```cpp
FScopedPredictionWindow ScopedPrediction(MyAbilityComponent,
    CurrentActivationInfo.GetActivationPredictionKey());

TArray<FHitResult> FoundHits;
PerformLocalTargeting(/*out*/ FoundHits);   // 클라이언트가 직접 라인 트레이스

FGameplayAbilityTargetDataHandle TargetData;
TargetData.UniqueId = WeaponStateComponent->GetUnconfirmedServerSideHitMarkerCount();
                      // ↑ 히트마커 배치를 나중에 찾기 위한 ID

const int32 CartridgeID = FMath::Rand();   // 같은 연사의 탄들을 묶는 ID

for (const FHitResult& FoundHit : FoundHits)
{
    FLyraGameplayAbilityTargetData_SingleTargetHit* NewTargetData = new ...;
    NewTargetData->HitResult = FoundHit;
    NewTargetData->CartridgeID = CartridgeID;
    TargetData.Add(NewTargetData);
}

WeaponStateComponent->AddUnconfirmedServerSideHitMarkers(TargetData, FoundHits);
OnTargetDataReadyCallback(TargetData, FGameplayTag());  // 즉시 콜백 진입
```

`StartRangedWeaponTargeting`은 **Blueprint에서 호출**한다.  
WaitTargetData AbilityTask 없이 클라이언트가 즉시 트레이스하고 콜백까지 직접 호출한다.

---

## 3단계 — OnTargetDataReadyCallback (핵심)

### 클라이언트 경로

```cpp
const bool bShouldNotifyServer =
    CurrentActorInfo->IsLocallyControlled() && !CurrentActorInfo->IsNetAuthority();

if (bShouldNotifyServer)
{
    MyAbilityComponent->CallServerSetReplicatedTargetData(
        CurrentSpecHandle,
        CurrentActivationInfo.GetActivationPredictionKey(),
        LocalTargetDataHandle,       // 히트 결과 전체
        ApplicationTag,
        MyAbilityComponent->ScopedPredictionKey);
}
```

로컬 클라이언트라면 TargetData를 서버에 전송한다.

### 서버 경로 (TargetData 수신 후)

```cpp
#if WITH_SERVER_CODE
if (Controller->GetLocalRole() == ROLE_Authority)
{
    TArray<uint8> HitReplaces;
    for (uint8 i = 0; i < LocalTargetDataHandle.Num(); ++i)
    {
        if (SingleTargetHit->bHitReplaced)  // 서버가 히트를 교체(거부)한 경우
            HitReplaces.Add(i);
    }
    // 클라이언트에게 어떤 히트가 유효했는지 알림
    WeaponStateComponent->ClientConfirmTargetData(
        LocalTargetDataHandle.UniqueId, bIsTargetDataValid, HitReplaces);
}
#endif
```

`HitReplaces`: 서버가 거부한 히트의 인덱스 배열.  
비어있으면 전부 유효, 들어있으면 해당 인덱스 히트는 무효.

### 공통 경로 (클라/서버 모두)

```cpp
if (bIsTargetDataValid && CommitAbility(...))
{
    WeaponData->AddSpread();                     // 탄퍼짐 누적
    OnRangedWeaponTargetDataReady(LocalTargetDataHandle);  // BP → GE 적용
}
```

---

## 4단계 — EndAbility

```cpp
MyAbilityComponent->AbilityTargetDataSetDelegate(...).Remove(OnTargetDataReadyCallbackDelegateHandle);
MyAbilityComponent->ConsumeClientReplicatedTargetData(...);
```

등록했던 콜백을 제거하고, ASC 캐시(`AbilityTargetDataMap`)에서 TargetData를 삭제한다.

---

## 왜 WaitTargetData Task를 쓰지 않는가

일반적인 GAS 발사 패턴은 `WaitTargetData` AbilityTask로 타겟팅을 기다린다.  
Lyra 히트스캔은 **타겟팅 대기가 필요 없다** — 발사 즉시 트레이스가 완료되기 때문이다.

대신 콜백을 직접 호출하는 단순한 흐름을 선택했다.  
프로젝타일 무기(`bProjectileWeapon`)라면 다른 경로가 필요하겠지만, 현재 코드에서는 미구현 상태.
