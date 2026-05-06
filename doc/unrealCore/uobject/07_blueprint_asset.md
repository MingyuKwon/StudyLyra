# C++ 클래스 → Blueprint Asset

> 출처:  
> `Engine/Source/Editor/Kismet/Public/BlueprintEditorUtils.h`  
> `Engine/Source/Runtime/CoreUObject/Public/UObject/ObjectMacros.h`

---

## 전제 조건 — Blueprintable 지정자

C++ 클래스가 Blueprint에서 상속 가능하려면 `UCLASS(Blueprintable)`이 붙어 있어야 한다.

```cpp
UCLASS(Blueprintable)
class MYGAME_API AMyActor : public AActor
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float Speed = 300.f;

    UFUNCTION(BlueprintCallable)
    void Fire();
};
```

| 지정자 | 의미 |
|--------|------|
| `Blueprintable` | 이 클래스를 부모로 하는 Blueprint 자식 클래스 생성 가능 |
| `BlueprintType` | Blueprint 변수 타입으로 이 클래스를 사용 가능 |
| `EditAnywhere` | 에디터 Details 패널에서 편집 가능 |
| `BlueprintReadWrite` | Blueprint 그래프에서 읽기·쓰기 가능 |
| `BlueprintCallable` | Blueprint 그래프에서 함수 호출 가능 |

`AActor`와 `UActorComponent`는 기본적으로 `Blueprintable`이다.  
순수 `UObject`를 상속한 클래스는 직접 `Blueprintable`을 붙여야 한다.

---

## 에디터에서 Blueprint Asset 만드는 과정

```
1. C++ 클래스 컴파일 완료
2. Content Browser에서 우클릭 → Blueprint Class
   또는 C++ 클래스 뷰에서 우클릭 → "Create Blueprint class based on AMyActor"
3. 부모 클래스 선택 창에서 AMyActor 선택
4. 이름 지정 (예: BP_MyActor) → 생성
```

생성된 `BP_MyActor`는 `AMyActor`를 상속하는 Blueprint 클래스다.  
에디터 안에서만 존재하는 `.uasset` 파일이다.

---

## Blueprint가 C++ CDO를 상속하는 방식

Blueprint 클래스는 C++ CDO 위에 추가 기본값 레이어를 얹는다.

```
AMyActor C++ CDO
  Speed = 300

BP_MyActor Blueprint CDO
  Speed = 500      ← Details 패널에서 변경한 값이 여기 저장
```

Blueprint를 컴파일하면:
1. Blueprint 그래프를 바이트코드로 컴파일
2. Blueprint CDO를 재생성 (C++ CDO 값 + Blueprint에서 override한 값)
3. 이미 월드에 있는 인스턴스는 다음 PIE 시작까지 유지

---

## C++ 변경 후 Blueprint에 미치는 영향

| 변경 사항 | Blueprint에 미치는 영향 |
|-----------|------------------------|
| UPROPERTY 추가 | Blueprint Details 패널에 자동 노출 |
| UPROPERTY 삭제 | 에디터 경고, Blueprint의 해당 값은 버려짐 |
| UFUNCTION 추가 | Blueprint 그래프에서 사용 가능 |
| 클래스 이름 변경 | Blueprint의 부모 참조가 깨짐 → 재연결 필요 |
| `Blueprintable` 제거 | 기존 Blueprint는 오류 상태가 됨 |

---

## 코드에서 Blueprint 클래스를 참조하는 방법

```cpp
// C++ 코드에서 BP_MyActor를 스폰하고 싶을 때
UPROPERTY(EditDefaultsOnly)
TSubclassOf<AMyActor> EnemyClass;   // 에디터에서 BP_MyActor 할당

void AMyGameMode::SpawnEnemy()
{
    if (EnemyClass)
    {
        GetWorld()->SpawnActor<AMyActor>(EnemyClass, SpawnTransform);
    }
}
```

C++ 코드에 `BP_MyActor` 에셋 경로를 하드코딩하는 것은 피한다.  
에디터에서 `TSubclassOf` UPROPERTY에 할당하는 방식이 표준이다.

---

## 내 노트

