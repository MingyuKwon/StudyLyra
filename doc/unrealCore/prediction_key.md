# FPredictionKey — GAS 클라이언트 사이드 예측

> 출처: `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Public/GameplayPrediction.h`  
>        `C:/UE_5.7/Engine/Plugins/Runtime/GameplayAbilities/Source/GameplayAbilities/Private/GameplayPrediction.cpp`

---

## 정체

예측 행동에 붙이는 `int16` 티켓이다.

```cpp
struct FPredictionKey
{
    int16    Current = 0;              // 고유 ID. 0이면 무효
    int16    Base    = 0;              // 부모 키 (의존성 체인용, 복제 안 됨)
    bool     bIsServerInitiated = false;

    // 서버 전용 — 어느 Net Connection이 이 키를 보냈는지 기억
    FObjectKey PredictiveConnectionObjectKey;
};
```

`Current`가 실제 ID다. `Base`는 연쇄 활성화 의존성에 쓰인다.

---

## 기본 흐름

```
[클라이언트]
  TryActivateAbility()
    → FPredictionKey Key#5 생성
    → ServerTryActivateAbility(Key#5) 전송 (서버에 알림)
    → ActivateAbility() 진입 ────────── 예측 윈도우 시작
        GE 예측 적용 → FActiveGameplayEffect::PredictionKey = Key#5 태그
    ← ActivateAbility() 리턴 ────────── 예측 윈도우 종료

[서버]
  ServerTryActivateAbility(Key#5) 수신
    → 허용 or 거부 결정
    → 허용 시: 같은 Key#5 사용해서 GE 생성 → ReplicatedPredictionKeyMap에 Key#5 추가
    → 거부 시: ClientActivateAbilityFailed(Key#5) RPC
```

---

## 예측 윈도우 수명

`ActivateAbility()` 콜스택이 예측 윈도우다. 리턴 후에는 Key#5로 새 예측 불가.

```
ActivateAbility()  ──── 윈도우 시작
  GE 적용 → Key#5 태그됨
  AbilityTask 시작 → 비동기 대기...
ActivateAbility() 리턴 ──── 윈도우 종료

// 이후 타이머, 라틴 노드, 콜백에서는 Key#5 더 이상 유효하지 않음
// 새로운 예측이 필요하면 FScopedPredictionWindow로 새 키 발급
```

헤더 주석: *"Once ActivateAbility ends, your prediction key is no longer valid. Timers or latent nodes in Blueprint invalidate your prediction window."*

---

## 종료 — 두 가지 경로

### 거부 (Reject) → 즉시 롤백

```
서버: ClientActivateAbilityFailed(Key#5) RPC
  → FPredictionKeyDelegates::BroadcastRejectedDelegate(Key#5)
  → Key#5 태그된 GE 전부 제거
```

`NewRejectedDelegate()`로 롤백 동작을 등록해두는 방식.  
GE가 예측 적용될 때 자동으로 "이 키가 거부되면 나를 제거해줘" 델리게이트를 등록한다.

### 확인 (CatchUp) → 예측본 정리

```
서버: ReplicatedPredictionKeyMap에 Key#5 추가 → FastArray 복제
  → 클라이언트 수신: FReplicatedPredictionKeyItem::OnRep
  → CatchUpTo(Key#5)
  → FPredictionKeyDelegates::BroadcastCaughtUpDelegate(Key#5)
  → 예측 GE 제거 (서버에서 복제된 GE로 대체됨)
```

서버 GE가 복제돼 내려올 때, 클라이언트는 같은 Key#5 태그를 확인하고 **OnAdded 재호출을 막는다** (Redo 문제 방지).  
그 뒤 CatchUp이 일어나면 예측본만 조용히 제거한다.

---

## NetSerialize 특수 동작

`FPredictionKey`를 프로퍼티 복제로 실어 보낼 때, **키를 발급한 클라이언트에게만** 실제 값이 전달된다.

```
ClientA → Key#5 발급 → 서버에 전달
서버: GE에 Key#5 태그 → 프로퍼티 복제

  → ClientA 수신: Current = 5  (유효)
  → ClientB 수신: Current = 0  (항상 무효)
```

`PredictiveConnectionObjectKey`가 "이 키를 보낸 연결"을 서버에서 기억한다.  
NetSerialize 시 현재 Connection과 비교해서 다르면 0으로 써서 보낸다.

이 덕분에 GE 복제 패킷에 예측 키가 실려도 다른 클라이언트는 해당 키를 볼 수 없다.

---

## FScopedPredictionWindow — 어빌리티 내부 추가 예측

어빌리티 실행 도중(타이머, 입력 이벤트 등)에 새 예측이 필요할 때 사용한다.

```cpp
// 클라이언트
FScopedPredictionWindow ScopedPrediction(ASC, true);
// → 새 Key#6 생성 (Base = Key#5)
// → 이 스코프 안에서 발생하는 GE는 Key#6 태그

ASC->ServerInputRelease(ScopedPrediction.ScopedPredictionKey);
// → 서버도 같은 Key#6으로 FScopedPredictionWindow 열어서 동기 실행
```

소멸자에서 `ASC->ScopedPredictionKey` 복원.  
Lyra 히트스캔에서 `StartRangedWeaponTargeting()`이 이 방식을 사용한다.

---

## 의존성 체인 (Base 필드)

GA_A → GA_B → GA_C 순서로 연쇄 활성화되는 경우.

```
GA_A 활성화 → Key#5
  GA_B 활성화 → Key#6 (Base = 5)
    GA_C 활성화 → Key#7 (Base = 5)

FPredictionKeyDelegates::AddDependency(Key#6, Key#5)
FPredictionKeyDelegates::AddDependency(Key#7, Key#5)

→ Key#5 거부 시: Key#6, Key#7 연쇄 거부
```

**한계**: 이 의존성은 클라이언트 내부에만 존재한다. 서버는 체인을 모른다.  
우회책: GA_A 성공 시 부여하는 GameplayTag를 GA_B의 활성화 조건으로 설정하면, 서버도 GA_A 거부 시 자연스럽게 GA_B를 거부한다.

---

## GE 예측 처리 전체 그림

```
[클라이언트]
  GE 예측 적용 (Key#5 태그)
  GE: Infinite Duration으로 처리 (Instant도 마찬가지)
    → 어트리뷰트: 절대값이 아닌 델타로 예측 (서버값 - 예측값)
    → OnRep 항상 호출: REPNOTIFY_Always 필요

[서버가 GE 복제 내려보냄]
  → 클라이언트: Key#5 태그 확인 → "내가 예측한 것" → OnAdded 재호출 안 함

[ReplicatedPredictionKeyMap Key#5 CatchUp]
  → 예측 GE 제거 → OnRemoved 재호출 안 함 (정상 제거와 구분)
  → 어트리뷰트 RepNotify로 서버 기준값 재집계
```

---

## 예측하지 못하는 것

헤더 주석 명시:

| 항목 | 이유 |
|------|------|
| GE 제거 | 상태가 없어서 롤백 불가 |
| GE Periodic(DoT 틱) | 틱마다 예측이 복잡 |
| Execution(계산식 GE) | Attribute Modifier만 예측 가능 |
| Meta Attribute (Damage 등) | Instant 효과의 백엔드에서만 동작, Duration GE 불가 |
| % 기반 Modifier 체인 | 서버가 집계 체인이 아닌 최종값만 복제 |
