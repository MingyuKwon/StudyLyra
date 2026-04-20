# TargetData — 타겟팅 결과 패킷

> 소스: `GameplayAbilityTargetTypes.h`, `AbilitySystemComponent_Abilities.cpp`  
> Lyra: `LyraGameplayAbilityTargetData_SingleTargetHit.h/cpp`

---

## 정체

`FGameplayAbilityTargetData`는 **"이 어빌리티가 무엇을/어디를 겨냥했는가"를 담는 폴리모픽 구조체**다.  
UObject가 아닌 `USTRUCT`이지만 가상 함수로 다형성을 갖고, NetSerialize로 직렬화·복제된다.

엔진 주석:
```
Some example producers:
  - 근접 공격 히트 콜리전 오버랩 결과
  - 마우스 클릭 → 레이트레이스 → 크로스헤어 앞 액터
  - AOE 반경 내 모든 액터

Some example consumers:
  - TargetData 안의 모든 액터에 GE 적용
  - 가장 가까운 액터 찾기
  - TargetData 위치에 액터 스폰
```

### 기본 인터페이스

```cpp
struct FGameplayAbilityTargetData
{
    virtual TArray<TWeakObjectPtr<AActor>> GetActors() const;
    virtual const FHitResult* GetHitResult() const;
    virtual FVector GetEndPoint() const;
    virtual FTransform GetOrigin() const;
    virtual bool HasHitResult() const { return false; }
    virtual bool HasEndPoint() const { return false; }

    // GE를 TargetData 안의 모든 타겟에 적용하는 헬퍼
    TArray<FActiveGameplayEffectHandle> ApplyGameplayEffectSpec(FGameplayEffectSpec& Spec, ...);
};
```

### Handle — 복수 타겟 배열

```cpp
struct FGameplayAbilityTargetDataHandle
{
    // TInlineAllocator<1>: 단일 타겟이 대부분 → 힙 할당 최소화
    TArray<TSharedPtr<FGameplayAbilityTargetData>, TInlineAllocator<1>> Data;
};
```

---

## ASC가 따로 보관하는 이유 — 클라-서버 비동기 타이밍

```
[클라이언트]                            [서버]
WaitTargetData 활성화 (예측)
타겟 선택 (레이캐스트)
TargetData 생성
  │
  └── CallServerSetReplicatedTargetData() ─RPC─▶  ServerSetReplicatedTargetData_Implementation()
                                                      │
  GA는 이미 다음 단계 실행 중                          ├── AbilityTargetDataMap에 저장
                                                      └── TargetSetDelegate.Broadcast()
                                                               └── 서버측 WaitTargetData 수신
```

서버에서 RPC가 도착했을 때 GA 인스턴스가 이미 다른 실행 단계에 있을 수 있다.  
직접 전달이 불가능하므로 ASC가 캐시로 보관했다가 대기 중인 태스크에 델리게이트로 전달한다.

### 저장 구조

```cpp
// AbilitySystemComponent.h
FGameplayAbilityReplicatedDataContainer AbilityTargetDataMap;
// 키: (FGameplayAbilitySpecHandle, FPredictionKey) 쌍
```

```cpp
// GameplayAbilityTypes.h
struct FAbilityReplicatedDataCache
{
    FGameplayAbilityTargetDataHandle TargetData;       // 실제 타겟 데이터
    FGameplayTag ApplicationTag;                       // 부가 태그
    bool bTargetConfirmed;                             // 확정 여부
    bool bTargetCancelled;                             // 취소 여부
    FAbilityTargetDataSetDelegate TargetSetDelegate;   // 확정 시 콜백
    FSimpleMulticastDelegate TargetCancelledDelegate;  // 취소 시 콜백
    FPredictionKey PredictionKey;
};
```

키에 PredictionKey가 포함되는 이유: 같은 GA가 여러 번 활성화될 때 각 인스턴스를 구분하기 위해서다.

### WaitTargetData가 처리하는 두 경로

```cpp
// 서버 RPC가 먼저 도착한 경우 (캐시에 이미 있음)
CallReplicatedTargetDataDelegatesIfSet()
  → TargetSetDelegate 즉시 발동

// 서버 RPC가 아직 안 온 경우 (캐시 없음)
AbilityTargetDataSetDelegate()에 바인딩해서 대기
  └── RPC 도착 시 ServerSetReplicatedTargetData_Implementation에서 Broadcast
```

### Lyra 접근 — GetAbilityTargetData

```cpp
// LyraAbilitySystemComponent.cpp:520
void ULyraAbilitySystemComponent::GetAbilityTargetData(
    const FGameplayAbilitySpecHandle AbilityHandle,
    FGameplayAbilityActivationInfo ActivationInfo,
    FGameplayAbilityTargetDataHandle& OutTargetDataHandle)
{
    TSharedPtr<FAbilityReplicatedDataCache> ReplicatedData =
        AbilityTargetDataMap.Find(
            FGameplayAbilitySpecHandleAndPredictionKey(
                AbilityHandle,
                ActivationInfo.GetActivationPredictionKey()));

    if (ReplicatedData.IsValid())
        OutTargetDataHandle = ReplicatedData->TargetData;
}
```

---

## Lyra 커스텀 구현 — FLyraGameplayAbilityTargetData_SingleTargetHit

```cpp
// AbilitySystem/LyraGameplayAbilityTargetData_SingleTargetHit.h
struct FLyraGameplayAbilityTargetData_SingleTargetHit
    : public FGameplayAbilityTargetData_SingleHit  // 엔진 기본 (HitResult 보유)
{
    int32 CartridgeID = -1;
    // NetSerialize 오버라이드로 CartridgeID도 직렬화
};
```

`CartridgeID`의 역할: 산탄총처럼 한 번 발사로 여러 펠릿이 날아갈 때, 서버가 "이 히트들은 같은 발사에서 나온 것"임을 식별하기 위한 ID다.

---

## 내장 엔진 서브클래스 목록

| 클래스 | 담는 정보 |
|--------|----------|
| `FGameplayAbilityTargetData_ActorArray` | 액터 배열 |
| `FGameplayAbilityTargetData_SingleTargetHit` | `FHitResult` 1개 |
| `FGameplayAbilityTargetData_LocationInfo` | 위치/방향 (Transform 2개: Origin + End) |
| `FLyraGameplayAbilityTargetData_SingleTargetHit` | HitResult + CartridgeID |
