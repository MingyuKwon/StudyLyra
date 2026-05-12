# UPROPERTY / UFUNCTION / USTRUCT 지정자

> 소스: `Engine/Source/Runtime/CoreUObject/Public/UObject/ObjectMacros.h`

UCLASS/UPROPERTY/UFUNCTION/USTRUCT/UENUM 매크로에 전달하는
지정자(Specifier)와 의미를 정리한다.

---

## UPROPERTY 지정자

### 에디터 노출

| 지정자 | 의미 |
|--------|------|
| `EditAnywhere` | 기본값 패널(CDO)·인스턴스 패널 모두 수정 가능 |
| `EditDefaultsOnly` | 기본값 패널(CDO)에서만 수정 가능 |
| `EditInstanceOnly` | 월드에 배치된 인스턴스에서만 수정 가능 |
| `VisibleAnywhere` | 어디서나 보이되 수정 불가 |
| `VisibleDefaultsOnly` | 기본값 패널에서 보이되 수정 불가 |
| `VisibleInstanceOnly` | 인스턴스에서 보이되 수정 불가 |

### Blueprint 접근

| 지정자 | 의미 |
|--------|------|
| `BlueprintReadWrite` | Blueprint에서 Get·Set 모두 가능 |
| `BlueprintReadOnly` | Blueprint에서 Get만 가능 |
| `BlueprintGetter=FuncName` | Get 시 지정 함수 경유 |
| `BlueprintSetter=FuncName` | Set 시 지정 함수 경유 |

### 복제

| 지정자 | 의미 |
|--------|------|
| `Replicated` | 서버 → 클라이언트 자동 복제 |
| `ReplicatedUsing=OnRep_Health` | 복제 수신 후 콜백 함수 호출 |
| `NotReplicated` | USTRUCT 멤버를 복제에서 제외 |

### 저장·직렬화

| 지정자 | 의미 |
|--------|------|
| `Transient` | 직렬화 제외 (런타임 캐시성 데이터, GC는 여전히 추적) |
| `SaveGame` | 세이브 시스템이 명시적으로 저장하는 필드 |
| `Config` | ini 파일에서 값 로드 |
| `NonTransactional` | 에디터 undo/redo 기록에서 제외 |

### 메타데이터 (Meta=)

| 메타 키 | 의미 |
|---------|------|
| `ClampMin`, `ClampMax` | 에디터 입력값 범위 제한 |
| `UIMin`, `UIMax` | 슬라이더 범위 (ClampMin/Max와 별도) |
| `DisplayName` | 에디터에 표시할 이름 |
| `ToolTip` | 마우스 오버 툴팁 |
| `AllowPrivateAccess` | private 멤버를 Blueprint에 노출 |
| `MustImplement` | TSubclassOf<>·ObjectProperty에서 구현해야 할 인터페이스 |
| `ExposeOnSpawn` | SpawnActor 노드의 핀으로 노출 |

```cpp
// 조합 예시
UPROPERTY(EditAnywhere, BlueprintReadWrite, Replicated, Category="Stats",
          Meta=(ClampMin="0.0", ClampMax="1000.0"))
float Health = 100.f;

UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Components")
TObjectPtr<UCameraComponent> CameraComponent;

UPROPERTY(Transient)
float CachedSpeed;   // 저장 안 됨, GC는 추적함

UPROPERTY(SaveGame)
int32 PlayerScore;

UPROPERTY(ReplicatedUsing=OnRep_Ammo)
int32 CurrentAmmo;

UFUNCTION()
void OnRep_Ammo();   // Replicated/Using 콜백은 반드시 UFUNCTION
```

---

## UFUNCTION 지정자

### Blueprint 연동

| 지정자 | 의미 |
|--------|------|
| `BlueprintCallable` | Blueprint에서 노드로 호출 가능 |
| `BlueprintPure` | 부작용 없음 표시 — exec 핀 없는 노드, `const` 권장 |
| `BlueprintImplementableEvent` | C++ 선언만, Blueprint에서 구현 (C++ 바디 없음) |
| `BlueprintNativeEvent` | C++에서 기본 구현(`_Implementation`), Blueprint에서 오버라이드 가능 |
| `CallInEditor` | 에디터에서 버튼으로 직접 실행 |

### BlueprintNativeEvent 패턴

```cpp
// 헤더
UFUNCTION(BlueprintNativeEvent, BlueprintCallable, Category="Combat")
void OnHit(AActor* OtherActor);

// .cpp — 기본 C++ 구현
void AMyActor::OnHit_Implementation(AActor* OtherActor)
{
    // Blueprint에서 오버라이드하지 않으면 여기가 실행됨
}
```

UHT가 `OnHit()`의 실제 바디를 gen.cpp에 생성한다.
내부에서 `ProcessEvent()`로 Blueprint VM을 호출하거나
Blueprint 오버라이드가 없으면 `_Implementation`으로 폴백한다.

### 네트워크 RPC

| 지정자 | 의미 |
|--------|------|
| `Server` | 클라이언트 → 서버 호출 |
| `Client` | 서버 → 클라이언트 호출 (Actor Owner의 클라이언트) |
| `NetMulticast` | 서버 → 모든 클라이언트 (서버에서도 실행) |
| `Reliable` | 순서 보장·재전송 보장 (중요한 이벤트) |
| `Unreliable` | 빠르지만 유실 가능 (빈번한 상태 동기화) |
| `WithValidation` | `_Validate` 함수 필수, 검증 실패 시 연결 끊음 |

```cpp
// Server RPC
UFUNCTION(Server, Reliable, WithValidation)
void ServerFire(FVector Direction);

void AMyActor::ServerFire_Implementation(FVector Direction) { /* 실제 구현 */ }
bool AMyActor::ServerFire_Validate(FVector Direction) { return Direction.IsNormalized(); }

// NetMulticast
UFUNCTION(NetMulticast, Unreliable)
void MulticastPlayEffect();

void AMyActor::MulticastPlayEffect_Implementation() { /* 이펙트 재생 */ }
```

### 기타

| 지정자 | 의미 |
|--------|------|
| `Exec` | 콘솔 명령어로 호출 가능 |
| `Category="Combat"` | Blueprint 노드 카테고리 |
| `Meta=(DisplayName="발사")` | Blueprint 노드 표시 이름 |
| `Meta=(ExpandEnumAsExecs="Result")` | 열거형 반환값을 exec 핀으로 확장 |
| `Meta=(Latent, LatentInfo="LatentInfo")` | 비동기 지연 노드 (AbilityTask 등) |

---

## USTRUCT 지정자

```cpp
USTRUCT(BlueprintType)
struct FDamageInfo
{
    GENERATED_BODY()   // 또는 GENERATED_USTRUCT_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float Amount;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    TObjectPtr<AActor> Instigator;
};
```

| 지정자 | 의미 |
|--------|------|
| `BlueprintType` | Blueprint 변수 타입·함수 파라미터로 사용 가능 |
| `Atomic` | 직렬화 시 구조체 전체를 원자 단위로 처리 (부분 저장 없음) |
| `NoExport` | 이 구조체의 generated 코드 생략 (엔진 내부용) |

USTRUCT는 UClass와 달리 GC 대상 UObject가 **아니다**.
하지만 멤버에 `UPROPERTY()`가 있으면 GC가 해당 UObject* 참조를 추적한다.

---

## UENUM / UMETA

```cpp
UENUM(BlueprintType)
enum class EWeaponState : uint8
{
    Idle      UMETA(DisplayName="대기"),
    Firing    UMETA(DisplayName="발사 중"),
    Reloading UMETA(DisplayName="재장전"),
    MAX       UMETA(Hidden)   // 배열 크기용, 에디터에서 숨김
};

UPROPERTY(EditAnywhere, BlueprintReadWrite)
EWeaponState WeaponState;
```

`UENUM(BlueprintType)` → Blueprint 열거형 변수·스위치 노드로 사용 가능.
`UMETA(DisplayName)` → 에디터·Blueprint에 표시할 이름.
`UMETA(Hidden)` → 에디터 드롭다운에서 숨김.

---

## 내 노트
