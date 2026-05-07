# CollisionEnabled 종류

> 출처:  
> `Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h` (line 1570~1630)

`ECollisionEnabled`는 **이 컴포넌트를 어떤 물리 시스템에 참여시킬지** 결정한다.  
Query 시스템(LineTrace·Sweep·Overlap)과 Physics 시스템(강체 시뮬레이션)을 독립적으로 켜고 끈다.

---

## 종류

### NoCollision

```cpp
// "Will not create any representation in the physics engine."
// "Best performance possible (especially for moving objects)"
NoCollision
```

Query도 Physics도 모두 비활성화.  
물리 엔진에 아무 데이터도 생성하지 않는다.

**사용 예**: 장식용 메시, 파티클, 이미 판정이 끝난 오브젝트.

---

### QueryOnly

```cpp
// "Only used for spatial queries (raycasts, sweeps, and overlaps)."
// "Cannot be used for simulation (rigid body, constraints)."
// "Performance gains by keeping data out of simulation tree."
QueryOnly
```

LineTrace, Sweep, Overlap에는 감지되지만 물리 시뮬레이션에는 참여하지 않는다.  
물리 엔진 내부의 **Query Tree**에만 등록된다.

**사용 예**: 캐릭터 Capsule (이동은 CharacterMovement가 처리, 물리 시뮬 불필요), 트리거 볼륨.

---

### PhysicsOnly

```cpp
// "Only used only for physics simulation (rigid body, constraints)."
// "Cannot be used for spatial queries (raycasts, sweeps, overlaps)."
// "Useful for jiggly bits on characters that do not need per bone detection."
PhysicsOnly
```

강체 시뮬레이션(중력, 충격, 제약)에는 참여하지만 LineTrace 등에는 감지되지 않는다.  
물리 엔진 내부의 **Simulation Tree**에만 등록된다.

**사용 예**: 캐릭터의 천 시뮬레이션 본, 레이캐스트에 잡힐 필요 없는 물리 오브젝트.

---

### QueryAndPhysics

```cpp
// "Can be used for both spatial queries and simulation."
QueryAndPhysics
```

Query와 Physics 모두 활성화. 가장 무거운 옵션.  
Query Tree와 Simulation Tree 양쪽에 모두 등록된다.

**사용 예**: 실제로 튕겨야 하고 LineTrace에도 잡혀야 하는 오브젝트 (바위, 차량, 상자 등).

---

### ProbeOnly

```cpp
// "Useful for when you want to detect potential physics interactions
//  and pass contact data to hit callbacks or contact modification,
//  but don't want to physically react to these contacts."
ProbeOnly
```

물리 접촉 데이터를 생성하고 Hit 콜백을 받지만, 실제로 물리 반응(튕김 등)은 하지 않는다.

**사용 예**: 물리 접촉을 감지해서 게임 로직을 트리거하되 물체가 튕기면 안 되는 경우.

---

### QueryAndProbe

```cpp
// "Query Collision and Contact Data, No Physics Collision"
QueryAndProbe
```

LineTrace·Sweep·Overlap 감지 + 물리 접촉 데이터 생성.  
물리 시뮬레이션(튕김)은 하지 않는다.

---

## 한눈에 비교

| 타입 | Query (Trace·Overlap) | Physics (시뮬레이션) | Probe (접촉 데이터) |
|------|--------------------|---------------------|---------------------|
| `NoCollision` | X | X | X |
| `QueryOnly` | O | X | X |
| `PhysicsOnly` | X | O | X |
| `QueryAndPhysics` | O | O | X |
| `ProbeOnly` | X | X | O |
| `QueryAndProbe` | O | X | O |

---

## 채널 시스템과의 관계

`CollisionEnabled`와 채널(ECollisionChannel + ResponseTable)은 **레이어가 다르다.**

```
CollisionEnabled  → "나는 어떤 시스템에 등록되나?"   (파이프라인 게이트)
ResponseTable     → "등록됐을 때 채널별로 어떻게 반응?" (등록 이후 판정)
```

채널은 Query인지 Physics인지 모른다. 어느 시스템의 파이프라인에서 조회되느냐가 구분을 만들 뿐이다.

### LineTrace가 들어올 때

```
1. Query 가속구조(BVH)에서 후보 추출
     → QueryOnly / QueryAndPhysics / QueryAndProbe 인 컴포넌트만 여기 있음
     → PhysicsOnly / NoCollision은 이 단계에서 이미 없음

2. 후보들 상대로 채널 + ResponseTable 매칭
     → "이 컴포넌트의 ECC_Visibility 응답이 Block / Overlap / Ignore?"
```

물리 시뮬레이션도 동일한 구조:

```
1. Chaos 브로드페이즈에서 후보 추출
     → PhysicsOnly / QueryAndPhysics 인 컴포넌트만

2. 충돌 후보끼리 채널 응답 확인
```

### 핵심

| 역할 | 담당 |
|------|------|
| 이 시스템에 참여하나? | `CollisionEnabled` |
| 참여했을 때 어떻게 반응? | `ECollisionChannel` + `ResponseTable` |

---

## 소스의 판별 함수

```cpp
// EngineTypes.h:1613
inline bool CollisionEnabledHasPhysics(ECollisionEnabled::Type CollisionEnabled)
{
    return (CollisionEnabled == ECollisionEnabled::PhysicsOnly) ||
           (CollisionEnabled == ECollisionEnabled::QueryAndPhysics);
}

inline bool CollisionEnabledHasQuery(ECollisionEnabled::Type CollisionEnabled)
{
    return (CollisionEnabled == ECollisionEnabled::QueryOnly) ||
           (CollisionEnabled == ECollisionEnabled::QueryAndPhysics) ||
           (CollisionEnabled == ECollisionEnabled::QueryAndProbe);
}
```

---

## 선택 기준

```
물리 반응(튕김·중력)이 필요한가?
  Yes → PhysicsOnly 또는 QueryAndPhysics
  No  →
    LineTrace·Overlap에 감지돼야 하는가?
      Yes → QueryOnly 또는 QueryAndProbe
      No  → NoCollision
```

**이동하는 오브젝트**일수록 `QueryOnly` 또는 `NoCollision`을 선호한다.  
Physics Tree는 매 프레임 모든 시뮬레이션 오브젝트를 처리하므로,  
불필요하게 Physics Tree에 등록된 오브젝트가 많을수록 성능이 떨어진다.

---

## 내 노트

