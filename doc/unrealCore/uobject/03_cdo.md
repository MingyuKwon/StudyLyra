# CDO — Class Default Object

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObjectGlobals.cpp`

---

## CDO란

**클래스당 하나씩 존재하는 기본 인스턴스**다.  
클래스가 로드될 때 엔진이 자동으로 생성하며, 두 가지 핵심 역할을 한다.

---

## CDO의 존재 의의

### 문제 1 — 에디터에서 바꾼 기본값을 어디에 저장하는가

C++ 생성자에 `Speed = 300.f`라고 써뒀다.  
에디터 Details 패널에서 이걸 500으로 바꿨다.  
이 변경사항을 어디에 저장하는가 — **CDO에 저장한다.**

CDO가 없으면 에디터에서 바꾼 기본값을 저장할 곳이 없고,  
코드를 수정하지 않는 한 기본값을 변경할 방법이 없다.

### 문제 2 — 새 인스턴스 생성 시 기본값을 어떻게 초기화하는가

SpawnActor를 할 때마다 생성자를 처음부터 실행하면 느리고,  
에디터에서 바꾼 값을 반영할 방법도 없다.  
대신 **CDO의 프로퍼티를 새 인스턴스에 복사**하는 방식으로 초기화한다.

```
SpawnActor<AMyActor>() 내부:
  1. 메모리 할당
  2. CDO의 프로퍼티 값을 새 인스턴스에 복사   ← CDO의 핵심 역할
  3. 생성자 실행 (FObjectInitializer)
  4. PostInitProperties()
```

---

## CDO가 만들어지는 시점

클래스 패키지가 메모리에 로드되는 순간 엔진이 생성자를 호출해 CDO를 만든다.  
플레이 시작 전, 에디터 시작 시점에도 이미 존재한다.

```
프로그램 시작
  → 클래스 등록 (UCLASS generated code)
  → StaticConstructObject_Internal() 호출
  → 생성자(AMyActor::AMyActor()) 실행
  → CDO 완성
```

이 때문에 생성자는 **실제 게임 로직을 실행하면 안 된다** — CDO 생성 시에도 불리기 때문이다.  
생성자에서는 기본값 설정과 CreateDefaultSubobject 호출만 해야 한다.

---

## Blueprint CDO 상속 체인

Blueprint 클래스는 C++ CDO 위에 추가 기본값 레이어를 얹는다.

```
C++ AMyActor CDO      Speed = 300   ← 생성자에서 설정
  └── BP_MyActor CDO  Speed = 500   ← 에디터 Details에서 변경, Blueprint CDO에 저장
        └── 스폰된 인스턴스  Speed = 500   ← BP CDO에서 복사
```

Blueprint를 컴파일하면 Blueprint CDO가 갱신된다.

---

## CDO 활용 방법

### 기본값 읽기 — GetDefault

인스턴스 없이 클래스의 기본값을 조회할 때 사용한다.

```cpp
const AMyActor* CDO = GetDefault<AMyActor>();
float DefaultSpeed = CDO->Speed;   // 에디터에서 설정한 기본값
```

### 일반 SpawnActor / NewObject — CDO를 자동으로 쓴다

별도 코드 없이 CDO가 템플릿으로 쓰인다.

```cpp
AMyActor* Actor = GetWorld()->SpawnActor<AMyActor>(Transform);
// Actor->Speed == CDO->Speed (에디터에서 설정한 값으로 자동 초기화)
```

### 특정 인스턴스를 템플릿으로 쓰기

CDO 대신 기존 인스턴스의 값을 복사해서 새 오브젝트를 만들 수 있다.

```cpp
FActorSpawnParameters Params;
Params.Template = ExistingActor;   // ExistingActor의 프로퍼티를 복사해서 생성
GetWorld()->SpawnActor<AMyActor>(AMyActor::StaticClass(), Transform, Params);
```

### CDO 직접 수정 — GetMutableDefault

이후 스폰되는 **모든 인스턴스의 기본값**이 바뀐다.  
런타임에 의도적으로 쓰는 경우는 극히 드물고, 대부분 버그다.

```cpp
// 런타임에 CDO 수정
AMyActor* MutableCDO = GetMutableDefault<AMyActor>();
MutableCDO->Speed = 999.f;
// 이 이후 SpawnActor<AMyActor>()로 만드는 모든 인스턴스의 Speed = 999
```

---

## 내 노트

