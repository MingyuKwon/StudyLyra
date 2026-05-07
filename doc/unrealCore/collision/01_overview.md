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

## ECollisionChannel — 내부 구조

Object Type과 Trace Channel은 **별개의 타입이 아니다.**  
둘 다 같은 `ECollisionChannel` enum 안에 있으며 내부적으로는 그냥 채널 0~31번이다.

```cpp
enum ECollisionChannel
{
    ECC_WorldStatic  = 0,   // 관례적으로 Object Type
    ECC_WorldDynamic = 1,   // 관례적으로 Object Type
    ECC_Pawn         = 2,   // 관례적으로 Object Type
    ECC_Visibility   = 3,   // 관례적으로 Trace Channel
    ECC_Camera       = 4,   // 관례적으로 Trace Channel
    ECC_PhysicsBody  = 5,   // 관례적으로 Object Type
    // ...
};
```

물리 레이어(PhysX/Chaos)는 이 채널 번호로 bitmask 연산을 할 뿐이다.  
"trace용인지 object용인지"는 모른다 — 어떤 API에 넘기느냐가 구분을 만든다.

```cpp
LineTraceSingleByChannel(..., ECC_Visibility, ...);   // Trace Channel로 사용
LineTraceSingleByObjectType(..., ECC_Pawn, ...);      // Object Type으로 사용
```

에디터 UI에서 별도 드롭다운으로 분리되는 것도 `DefaultEngine.ini`의 `bTraceType` 플래그로 구분할 뿐이다.

---

## Object Type — 오브젝트의 정체성

**"나는 무엇인가"** — 컴포넌트가 자신을 어떤 타입으로 분류할지 선언한다.

Object Type이 필요한 이유는 두 가지다.

**① 물리 충돌은 양방향이다**

```
Pawn ↔ WorldStatic 충돌:
  Pawn이 WorldStatic을 어떻게 볼 것인가?   → Block
  WorldStatic이 Pawn을 어떻게 볼 것인가?   → Block
  둘 다 타입이 있어야 서로 응답 정의 가능
```

Trace Channel만으로는 "내가 쏜 레이가 무엇에 맞나"는 알 수 있지만  
"이 오브젝트와 저 오브젝트가 물리적으로 어떻게 반응하나"를 정의할 수 없다.

**② 타입 기반 쿼리**

```cpp
// "이 구 안에 있는 Pawn 타입을 전부 찾아라"
GetWorld()->OverlapMultiByObjectType(
    Results,
    Center,
    FQuat::Identity,
    FCollisionObjectQueryParams(ECC_Pawn),
    FCollisionShape::MakeSphere(500.f)
);
```

엔진 기본 Object Type:

| 채널 | 용도 |
|------|------|
| `WorldStatic` | 움직이지 않는 지형, 건물 |
| `WorldDynamic` | 움직이는 일반 오브젝트 |
| `Pawn` | 캐릭터, 플레이어 |
| `PhysicsBody` | 물리 시뮬레이션 오브젝트 |
| `Vehicle` | 탈것 |
| `Destructible` | 파괴 가능 오브젝트 |

```cpp
CapsuleComponent->SetCollisionObjectType(ECC_Pawn);
```

---

## Trace Channel — 쿼리의 목적

**"무엇을 찾을 것인가"** — LineTrace, Sweep 쿼리에서 어떤 오브젝트를 감지할지 지정한다.

```cpp
FHitResult Hit;
GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Visibility);
```

엔진 기본 Trace Channel:

| 채널 | 용도 |
|------|------|
| `Visibility` | 일반 가시성 체크 |
| `Camera` | 카메라 전용 |

### Object Type 채널로 LineTrace를 쏘면?

`ECC_Pawn`을 Trace Channel 자리에 넣는 것은 기술적으로 가능하다.

```cpp
// 컴파일은 됨
GetWorld()->LineTraceSingleByChannel(Hit, Start, End, ECC_Pawn);
```

각 오브젝트는 모든 채널에 응답 테이블을 갖는다. 벽의 `ECC_Pawn` 응답은  
"Pawn이 나에게 물리적으로 부딪힐 때 Block"으로 세팅된 것이지  
"Pawn 채널 레이에 반응해라" 의도가 아니다.  
우연히 응답이 맞아떨어져 동작할 수 있지만 결과를 예측하기 어렵다 — 쓰지 않는다.

---

## 응답 3종류 — Block / Overlap / Ignore

두 컴포넌트가 만났을 때의 반응을 각 채널별로 설정한다.

| 응답 | 물리 반응 | 이벤트 |
|------|-----------|--------|
| **Block** | 막힘 | `OnHit` |
| **Overlap** | 통과 | `OnBeginOverlap` / `OnEndOverlap` |
| **Ignore** | 통과 | 없음 |

### Response Matrix

최종 응답은 둘 중 **더 허용적인 쪽**을 따른다.

```
Block  + Block   = Block
Block  + Overlap = Overlap
Block  + Ignore  = Ignore
Overlap + Ignore = Ignore

우선순위: Ignore > Overlap > Block
```

---

## Preset (Collision Profile)

Object Type과 모든 채널 응답을 묶어 이름을 붙인 것.

| Preset | Object Type | 주요 응답 |
|--------|-------------|-----------|
| `BlockAll` | WorldStatic | 모든 채널 Block |
| `OverlapAll` | WorldDynamic | 모든 채널 Overlap |
| `NoCollision` | WorldDynamic | 모든 채널 Ignore |
| `Pawn` | Pawn | WorldStatic·WorldDynamic Block, 나머지 Ignore |
| `Trigger` | WorldDynamic | Pawn Overlap, 나머지 Ignore |
| `Projectile` | WorldDynamic | Pawn·WorldStatic Block, 나머지 Ignore |

```cpp
MeshComponent->SetCollisionProfileName(TEXT("BlockAll"));

// 개별 설정
MeshComponent->SetCollisionObjectType(ECC_WorldDynamic);
MeshComponent->SetCollisionResponseToAllChannels(ECR_Block);
MeshComponent->SetCollisionResponseToChannel(ECC_Pawn, ECR_Overlap);
```

---

## 이벤트 바인딩

```cpp
// Hit 이벤트 (Block 결과)
MeshComponent->OnComponentHit.AddDynamic(this, &AMyActor::OnHit);

// Overlap 이벤트
MeshComponent->OnComponentBeginOverlap.AddDynamic(this, &AMyActor::OnOverlapBegin);
```

Hit 이벤트: `bNotifyRigidBodyCollision` 켜져 있어야 함.  
Overlap 이벤트: `bGenerateOverlapEvents` 켜져 있어야 함.

---

## 내 노트
