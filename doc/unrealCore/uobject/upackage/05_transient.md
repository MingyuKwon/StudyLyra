# UPackage — Transient

## Transient란

**"직렬화(저장) 대상에서 제외"** 를 의미한다.  
저장 행위 자체를 막는 게 아니라 직렬화 과정에서 건너뛰는 것이다.

| 위치 | 의미 |
|------|------|
| `UPROPERTY(Transient)` | 이 프로퍼티는 저장 안 함, GC 추적은 유지 |
| `UCLASS(Transient)` | 이 클래스 인스턴스는 저장 안 함 (`UGameInstance`, `UWorld` 등) |
| `GetTransientPackage()` | 저장 안 하는 오브젝트의 Outer 역할 패키지 |
| `RF_Transient` 플래그 | 이 UObject 인스턴스만 저장 안 함 |

---

## 사용 예

```cpp
UPROPERTY()
float MaxSpeed = 600.f;      // 저장됨

UPROPERTY(Transient)
float CurrentSpeed = 0.f;   // 저장 안 됨 — 런타임에 채워지는 캐시값

UPROPERTY(Transient, Replicated)
float CurrentSpeed = 0.f;   // 저장 안 됨 + 네트워크 복제는 됨
                             // Transient는 디스크 직렬화만 제외, 복제와 무관
```

`GetTransientPackage()`는 어느 에셋에도 속하지 않는 임시 오브젝트의 Outer 역할을 한다.

```cpp
UMyRuntimeData* Data = NewObject<UMyRuntimeData>(GetTransientPackage());
// 엔진 시작 시 생성, RF_RootSet 등록, 디스크에 저장 안 됨
```

---

## 내 노트
