# Collision 성능 최적화

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h`  
> `Engine/Source/Runtime/PhysicsCore/`  
> Unreal Engine 공식 문서 — Collision Best Practices

---

## 핵심 원칙

물리 엔진은 내부적으로 두 개의 트리를 관리한다.

| 트리 | 담당 | 갱신 비용 |
|------|------|-----------|
| **Query Tree** (BVH) | LineTrace·Sweep·Overlap | 오브젝트 이동 시 재삽입 |
| **Physics Tree** | 강체 시뮬레이션 | 매 Physics 스텝 |

오브젝트가 많고 자주 움직일수록 두 트리의 갱신 비용이 커진다.  
불필요한 트리 참여를 줄이는 것이 Collision 성능 최적화의 핵심이다.

---

## Simple vs Complex Collision

모든 Mesh 컴포넌트는 두 종류의 충돌 형상을 가질 수 있다.

| 종류 | 설명 | 비용 |
|------|------|------|
| **Simple** | 에디터에서 설정한 단순 도형 (Box, Sphere, Capsule, 컨벡스 헐) | 저비용 |
| **Complex** | 실제 폴리곤 메시 (삼각형 단위) | 고비용 |

```cpp
// 컴포넌트별 Simple/Complex 사용 방식 설정
MeshComp->SetCollisionComplexity(ECollisionTraceFlag::CTF_UseSimpleAsComplex);
// CTF_UseDefault           — 메시 에셋 설정 따름
// CTF_UseSimpleAsComplex   — Simple을 Complex 대신 사용
// CTF_UseComplexAsSimple   — Complex를 Simple 대신 사용 (주의: 매우 비쌈)
// CTF_UseSimpleAndComplex  — 둘 다 유지
```

**원칙**: 게임플레이 판정에는 항상 Simple Collision을 쓴다.  
Complex는 정밀 사격 판정처럼 꼭 필요한 경우에만 사용한다.

---

## CollisionEnabled로 트리 참여 최소화

이동하는 오브젝트가 Physics Tree에 참여하면 매 프레임 트리 갱신 비용이 발생한다.

```
QueryAndPhysics로 이동하는 오브젝트 1000개
  → 매 프레임 Query Tree + Physics Tree 양쪽 갱신
  → 성능 부담 2배

QueryOnly로 변경
  → 매 프레임 Query Tree만 갱신
  → Physics 갱신 비용 제거
```

물리 시뮬레이션이 불필요한 이동 오브젝트는 `QueryOnly`로 설정한다.

---

## 채널 설계로 쿼리 범위 줄이기

LineTrace·Overlap 쿼리는 채널 응답이 Ignore인 오브젝트를 건너뛴다.  
커스텀 채널로 불필요한 오브젝트를 필터링하면 쿼리 비용이 줄어든다.

```cpp
// 나쁜 예: Visibility 채널로 모든 오브젝트 대상 트레이스
GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Visibility);
// → 씬의 모든 Block/Overlap 오브젝트를 검사

// 좋은 예: 전용 Weapon 채널로만 검사
// (WorldStatic·Pawn만 Block, 나머지 Ignore 설정)
GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_GameTraceChannel1 /* Weapon */);
// → Weapon 채널에 응답하는 오브젝트만 검사
```

채널 설계 전략:
- 장식용 메시·이펙트는 모든 Trace 채널에 Ignore 설정
- 총기 사격 판정 채널과 일반 가시성 채널을 분리
- Trigger 볼륨은 Pawn 채널에만 Overlap, 나머지 Ignore

---

## 비동기 트레이스 (Async Trace)

일반 LineTrace는 **동기** 방식이다 — 결과가 나올 때까지 게임 스레드가 기다린다.  
복잡한 트레이스를 매 프레임 여러 번 실행하면 프레임 타임을 잡아먹는다.

비동기 트레이스는 요청을 큐에 넣고 다음 프레임에 결과를 받는다.

```cpp
// 비동기 트레이스 요청
FTraceHandle Handle = GetWorld()->AsyncLineTraceByChannel(
    EAsyncTraceType::Single,
    Start, End,
    ECC_Visibility,
    FCollisionQueryParams::DefaultQueryParam,
    FCollisionResponseParams::DefaultResponseParam,
    &TraceDelegate    // 완료 시 호출될 델리게이트
);

// 델리게이트에서 결과 처리
void AMyActor::OnTraceComplete(const FTraceHandle& Handle, FTraceDatum& Data)
{
    if (Data.OutHits.Num() > 0)
    {
        // 히트 처리
    }
}
```

1프레임 지연이 발생하므로 즉각 반응이 필요한 판정(탄환 히트 등)에는 부적합하다.  
시야 체크, AI 감지 등 약간의 지연이 허용되는 쿼리에 적합하다.

---

## Object Type 필터링

LineTrace보다 Overlap 검사가 필요할 때, Object Type을 필터로 쓰면 범위를 줄인다.

```cpp
// 특정 Object Type만 Overlap 검사
TArray<FOverlapResult> Overlaps;
FCollisionObjectQueryParams ObjectParams;
ObjectParams.AddObjectTypesToQuery(ECC_Pawn);   // Pawn만 검사
ObjectParams.AddObjectTypesToQuery(ECC_Vehicle);

GetWorld()->OverlapMultiByObjectType(
    Overlaps,
    Center,
    FQuat::Identity,
    ObjectParams,
    FCollisionShape::MakeSphere(500.f)
);
```

채널 기반 쿼리보다 Object Type 필터링이 더 직관적이고 빠른 경우가 많다.

---

## Physics Sleep

물리 시뮬레이션 중인 오브젝트가 충분히 정지하면 엔진이 자동으로 **Sleep** 상태로 전환한다.  
Sleep 상태의 오브젝트는 Physics Tree 갱신에서 제외된다.

```cpp
// 수동으로 Sleep 설정
MeshComp->SetAllBodiesSleepState(true);  // 강제 Sleep
MeshComp->SetAllBodiesSleepState(false); // Wake up

// Sleep 임계값 설정 (낮을수록 빨리 잠듦)
UPhysicsSettings::Get()->SleepLinearVelocityThreshold  = 0.1f;
UPhysicsSettings::Get()->SleepAngularVelocityThreshold = 0.05f;
```

떨어지고 정지한 물체들이 계속 Physics 갱신을 받지 않도록 Sleep 임계값을 적절히 설정하는 것이 중요하다.

---

## 요약 — 체크리스트

| 항목 | 권장 |
|------|------|
| 물리 불필요한 이동 오브젝트 | `QueryOnly` |
| 완전히 판정 불필요한 오브젝트 | `NoCollision` |
| 메시 충돌 형상 | Simple Collision 우선, Complex는 예외적으로 |
| 트레이스 채널 | 전용 채널 분리, 불필요 오브젝트 Ignore |
| 매 프레임 다수 트레이스 | 비동기 트레이스 검토 |
| 물리 오브젝트 정지 후 | Sleep 자동 전환 확인 |

---

## 내 노트

