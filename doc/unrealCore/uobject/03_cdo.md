# CDO — Class Default Object

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/UObjectGlobals.cpp`

---

## CDO란

**클래스당 하나씩 존재하는 기본 인스턴스**다.  
모든 UObject 서브클래스(AActor, UActorComponent, UDataAsset, 순수 UObject 자식 모두)에 존재한다.  
클래스가 로드될 때 엔진이 자동으로 생성하며, 두 가지 핵심 역할을 한다.

---

## CDO의 두 핵심 역할

### 역할 1 — 에디터 기본값 저장소

C++ 생성자에 `Speed = 300.f`라고 써뒀다.  
에디터 Details 패널에서 이걸 500으로 바꿨다.  
이 변경사항을 어디에 저장하는가 — **CDO에 저장한다.**

CDO가 없으면 에디터에서 바꾼 기본값을 저장할 곳이 없고,  
코드를 수정하지 않는 한 기본값을 변경할 방법이 없다.

### 역할 2 — 새 인스턴스의 초기화 기준점

SpawnActor / NewObject 시 CDO의 프로퍼티를 새 인스턴스에 복사하는 방식으로 초기화한다.

```
StaticConstructObject_Internal() 내부:
  1. 메모리 할당
  2. FObjectInitializer 생성 → 스레드 로컬 스택 푸시
  3. 생성자(C++ constructor) 실행
  4. FObjectInitializer 소멸자 실행
       → InitProperties()     ← CDO 프로퍼티 복사 (여기서 발생)
       → PostInitProperties() ← 복사 완료 후 호출되는 콜백
```

Blueprint 클래스는 기본값이 Blueprint VM 실행으로 결정되는데,  
CDO 덕분에 VM을 컴파일 시 딱 한 번만 실행하고 이후 인스턴스는 복사만 한다.

```
Blueprint CDO 생성 시: VM 실행 1번
인스턴스 100개 스폰:   프로퍼티 복사 100번  (VM 실행 0번)
```

---

## CDO가 만들어지는 시점

클래스 패키지가 메모리에 로드되는 순간 엔진이 `StaticConstructObject_Internal`을 호출해 CDO를 만든다.  
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

## 델타 직렬화 — CDO가 기준점인 이유

CDO는 인스턴스 초기화뿐 아니라 **직렬화(저장/로드)의 기준점**이기도 하다.  
파일에 저장할 때 CDO와 다른 값만 기록하고, 로드할 때 CDO를 먼저 복사한 뒤 기록된 차이만 덮어씌운다.

```
저장: 인스턴스 각 프로퍼티를 CDO(Archetype)와 비교
  → 같으면 쓰지 않음
  → 다르면 "프로퍼티 이름 + 값" 기록

로드: CDO 프로퍼티 복사 → 저장된 델타 덮어씀
```

### 세 레이어 모두 델타로 저장된다

```
C++ CDO           Speed=300, HP=100       ← 완전한 값 (생성자)
  └── BP CDO      Speed=500               ← C++ CDO 대비 달라진 것만 .uasset에 저장
        └── 레벨 인스턴스  HP=200          ← BP CDO 대비 달라진 것만 .umap에 저장
```

### 부모 변경이 자동으로 전파된다

BP CDO의 `Speed`를 500→600으로 바꾸면, 레벨 인스턴스의 `.umap` 델타에 `Speed`가 없는 경우  
로드 시 600이 자동으로 적용된다.  
인스턴스에서 직접 바꾼 값은 델타에 기록되어 있으므로 전파되지 않는다.

에디터 Details 패널의 **노란 리셋 화살표** = 이 프로퍼티가 Archetype(CDO)과 다르다 = 델타에 기록된 상태.  
화살표를 클릭하면 델타에서 그 프로퍼티를 제거 → Archetype 값으로 복원.

---

## Blueprint CDO 상속 체인

```
C++ AMyActor CDO      Speed=300   ← 생성자에서 설정
  └── BP_MyActor CDO  Speed=500   ← 에디터 Details에서 변경, .uasset에 델타 저장
        └── 스폰된 인스턴스        ← BP CDO에서 복사 후 .umap 델타 적용
```

Blueprint를 컴파일하면 Blueprint CDO가 갱신된다.  
자식 Blueprint CDO도 부모 Blueprint CDO 기준 델타만 저장한다.

---

## CDO 활용 방법

### 기본값 읽기 — GetDefault

인스턴스 없이 클래스의 기본값을 조회할 때 사용한다.

```cpp
const AMyActor* CDO = GetDefault<AMyActor>();
float DefaultSpeed = CDO->Speed;
```

### SpawnActor / NewObject — CDO를 자동으로 쓴다

```cpp
AMyActor* Actor = GetWorld()->SpawnActor<AMyActor>(Transform);
// Actor->Speed == CDO->Speed (에디터에서 설정한 값으로 자동 초기화)
```

### 특정 인스턴스를 템플릿으로 쓰기

CDO 대신 기존 인스턴스의 값을 복사해서 새 오브젝트를 만들 수 있다.

```cpp
FActorSpawnParameters Params;
Params.Template = ExistingActor;
GetWorld()->SpawnActor<AMyActor>(AMyActor::StaticClass(), Transform, Params);
```

### CDO 직접 수정 — GetMutableDefault

이후 스폰되는 **모든 인스턴스의 기본값**이 바뀐다.  
런타임에 의도적으로 쓰는 경우는 극히 드물고, 대부분 버그다.

```cpp
AMyActor* MutableCDO = GetMutableDefault<AMyActor>();
MutableCDO->Speed = 999.f;
// 이 이후 SpawnActor<AMyActor>()로 만드는 모든 인스턴스의 Speed = 999
```

---

## 내 노트

