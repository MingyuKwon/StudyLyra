# CDO — Class Default Object

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/Class.h`  
> `Engine/Source/Runtime/CoreUObject/Private/UObjectGlobals.cpp`

---

## CDO란

**클래스당 하나씩 존재하는 기본 인스턴스**다.  
클래스가 로드될 때 엔진이 자동으로 생성하며, 해당 클래스의 "기본값 저장소" 역할을 한다.

```cpp
// CDO에 접근하는 방법
AMyActor* DefaultActor = AMyActor::StaticClass()->GetDefaultObject<AMyActor>();

// 또는
AMyActor* CDO = GetDefault<AMyActor>();
```

---

## CDO가 만들어지는 시점

클래스 패키지가 메모리에 로드되는 순간, 엔진이 해당 클래스의 생성자를 호출해 CDO를 만든다.  
플레이가 시작되기 전, 에디터 시작 시점에도 이미 존재한다.

```
프로그램 시작
  → 클래스 등록 (UCLASS 매크로 generated code)
  → StaticConstructObject_Internal() 호출
  → 생성자(AMyActor::AMyActor()) 실행
  → CDO 완성
```

이 때문에 생성자는 **실제 게임 로직을 실행하면 안 된다** — CDO 생성 시에도 불리기 때문이다.  
생성자에서는 기본값 설정, CreateDefaultSubobject 호출만 해야 한다.

---

## CDO의 역할

### 1. 기본값 저장소

에디터의 Details 패널에서 Actor를 선택했을 때 보이는 기본값이 CDO에 저장된 값이다.  
새 인스턴스를 스폰하면 CDO의 값을 복사해 초기화한다.

```cpp
UCLASS()
class AMyActor : public AActor
{
    UPROPERTY(EditDefaultsOnly)
    float Speed = 300.f;    // CDO에서 Speed = 300으로 저장됨
};
// 에디터에서 Speed를 500으로 바꾸면 CDO.Speed = 500
// 이후 스폰되는 모든 AMyActor는 Speed = 500으로 시작
```

### 2. Blueprint 기본값의 베이스

Blueprint 클래스는 C++ CDO 위에 추가 기본값을 덮어쓴다.  
Blueprint를 컴파일하면 Blueprint CDO가 갱신된다.

```
C++ AMyActor CDO   (Speed = 300)
    └── BP_MyActor CDO   (Speed = 500, override)
            └── 스폰된 인스턴스   (Speed = 500)
```

### 3. GetDefaultObject() 패턴

인스턴스 없이 클래스의 기본 설정을 읽고 싶을 때 CDO를 직접 참조한다.

```cpp
// 예: 이 클래스의 기본 Speed가 얼마인지 코드에서 확인
float DefaultSpeed = GetDefault<AMyActor>()->Speed;
```

---

## CDO 수정 시 주의

CDO는 공유 인스턴스다. CDO를 직접 수정하면 이후 스폰되는 **모든 인스턴스의 기본값**이 바뀐다.  
런타임에 CDO를 의도적으로 수정하는 경우는 극히 드물고, 대부분 버그다.

```cpp
// 절대 하면 안 되는 패턴
AMyActor* CDO = GetDefault<AMyActor>();
CDO->Speed = 999.f;   // 이후 모든 스폰 인스턴스 Speed = 999
```

---

## 내 노트

