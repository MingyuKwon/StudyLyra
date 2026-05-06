# Collision 개념

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h`  
> `Engine/Source/Runtime/Engine/Classes/Engine/CollisionProfile.h`

언리얼의 Collision 시스템은 두 레이어로 나뉜다.

| 레이어 | 역할 | 질문 |
|--------|------|------|
| **Query** | 공간 질의 — LineTrace, Sweep, Overlap | "여기 뭐가 있나?" |
| **Physics** | 물리 시뮬레이션 — 강체 충돌, 제약 | "충돌하면 어떻게 튕기나?" |

두 레이어는 독립적으로 활성화할 수 있다. → [02_collision_enabled.md](02_collision_enabled.md)

---

## 응답 3종류 — Block / Overlap / Ignore

두 컴포넌트가 만났을 때의 반응을 각 채널별로 설정한다.

| 응답 | 물리 반응 | 이벤트 | 설명 |
|------|-----------|--------|------|
| **Block** | 막힘 (통과 불가) | `OnHit` | 실제로 부딪혀서 막힘 |
| **Overlap** | 통과함 | `OnBeginOverlap` / `OnEndOverlap` | 통과하면서 이벤트만 발생 |
| **Ignore** | 통과함 | 없음 | 완전히 무시 |

**두 컴포넌트의 응답이 모두 Block이어야 Block으로 처리된다.**  
한쪽이라도 Ignore면 Ignore, 둘 다 Overlap이면 Overlap.

```
[캐릭터 Capsule]    Block  →  WorldStatic
[바닥 Floor]        Block  ←  Pawn
결과: Block (막힘, OnHit 발생)

[트리거 Box]        Overlap →  Pawn
[캐릭터 Capsule]    Overlap ←  WorldDynamic
결과: Overlap (통과, OnBeginOverlap 발생)

[총알 Projectile]   Block  →  Pawn
[파티클 Effect]     Ignore ←  Projectile
결과: Ignore (무시)
```

---

## Object Channel (Object Type)

**"나는 무엇인가"** — 컴포넌트가 자신을 어떤 타입으로 분류할지 선언한다.

엔진 기본 제공 Object Channel:

| 채널 | 용도 |
|------|------|
| `WorldStatic` | 움직이지 않는 지형, 건물 |
| `WorldDynamic` | 움직이는 일반 오브젝트 |
| `Pawn` | 캐릭터, 플레이어 |
| `PhysicsBody` | 물리 시뮬레이션 오브젝트 |
| `Vehicle` | 탈것 |
| `Destructible` | 파괴 가능 오브젝트 |

게임별 커스텀 채널은 프로젝트 세팅 → Collision에서 추가한다 (`ECC_GameTraceChannel1` ~ `18`).

```cpp
// 컴포넌트의 Object Type 설정
CapsuleComponent->SetCollisionObjectType(ECC_Pawn);
```

---

## Trace Channel

**"무엇을 찾을 것인가"** — LineTrace, Sweep 쿼리에서 어떤 오브젝트를 감지할지 지정한다.

엔진 기본 Trace Channel:

| 채널 | 용도 |
|------|------|
| `Visibility` | 일반 가시성 체크 (카메라 차단 여부 등) |
| `Camera` | 카메라 전용 |

Object Channel과 Trace Channel은 같은 `ECollisionChannel` enum이지만  
Object Channel은 컴포넌트 타입 선언에, Trace Channel은 쿼리 필터에 사용한다.

```cpp
// Visibility 채널로 LineTrace
FHitResult Hit;
bool bHit = GetWorld()->LineTraceSingleByChannel(
    Hit,
    StartLocation,
    EndLocation,
    ECC_Visibility     // 이 채널에 Block 응답인 컴포넌트만 감지
);
```

---

## Response Matrix — 응답이 결정되는 규칙

두 컴포넌트가 만날 때 최종 응답은 둘의 응답 중 **더 허용적인 쪽**을 따른다.

```
Block  + Block  = Block     (둘 다 막아야 막힘)
Block  + Overlap = Overlap  (한쪽이 통과 허용하면 통과)
Block  + Ignore = Ignore    (한쪽이 무시하면 무시)
Overlap + Ignore = Ignore
```

즉 우선순위: `Ignore > Overlap > Block`

---

## Preset (Collision Profile)

Object Type과 모든 채널에 대한 Response를 묶어 이름을 붙인 것.  
에디터의 Collision 섹션 드롭다운이 이것이다.

엔진 기본 Preset 예시:

| Preset | Object Type | 주요 응답 |
|--------|-------------|-----------|
| `BlockAll` | WorldStatic | 모든 채널 Block |
| `OverlapAll` | WorldDynamic | 모든 채널 Overlap |
| `NoCollision` | WorldDynamic | 모든 채널 Ignore |
| `Pawn` | Pawn | WorldStatic·WorldDynamic Block, 나머지 Ignore |
| `Trigger` | WorldDynamic | Pawn Overlap, 나머지 Ignore |
| `Projectile` | WorldDynamic | Pawn·WorldStatic Block, 나머지 Ignore |

```cpp
// C++에서 Preset 적용
MeshComponent->SetCollisionProfileName(TEXT("BlockAll"));

// 또는 개별 설정
MeshComponent->SetCollisionObjectType(ECC_WorldDynamic);
MeshComponent->SetCollisionResponseToAllChannels(ECR_Block);
MeshComponent->SetCollisionResponseToChannel(ECC_Pawn, ECR_Overlap);
```

---

## 이벤트 바인딩

```cpp
// Hit 이벤트 (Block 결과)
MeshComponent->OnComponentHit.AddDynamic(this, &AMyActor::OnHit);

void AMyActor::OnHit(UPrimitiveComponent* HitComp, AActor* OtherActor,
    UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit) { }

// Overlap 이벤트
MeshComponent->OnComponentBeginOverlap.AddDynamic(this, &AMyActor::OnOverlapBegin);

void AMyActor::OnOverlapBegin(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
    UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
    bool bFromSweep, const FHitResult& SweepResult) { }
```

Hit 이벤트를 받으려면 컴포넌트의 `bSimulationGeneratesHitEvents` 또는 `bNotifyRigidBodyCollision`이 켜져 있어야 한다.  
Overlap 이벤트를 받으려면 `bGenerateOverlapEvents`가 켜져 있어야 한다.

---

## 내 노트

