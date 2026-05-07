# UPackage — 로드 시점

## 종류별 로드 시점

| 종류 | 로드 시점 |
|------|-----------|
| 스크립트 패키지 | 엔진 시작 시 — 모듈 DLL 로드와 함께 자동 생성 |
| Transient 패키지 | 엔진 시작 시 — 항상 존재, 언로드되지 않음 |
| 콘텐츠 패키지 | 참조 방식에 따라 다름 (아래) |

스크립트·Transient 패키지는 로드 시점이 고정이다.  
콘텐츠 패키지만 참조 방식에 따라 달라진다.

---

## 콘텐츠 패키지 로드 시점 — 참조 방식이 결정한다

### Hard 참조 — 참조하는 패키지 로드 시 함께

```cpp
UPROPERTY()
UStaticMesh* MyMesh;   // Hard 참조
```

이 Actor가 담긴 레벨이 로드될 때 `MyMesh` 패키지도 **같이 로드**된다.

```
MyLevel 로드
  → BP_MyActor 로드
      → SM_Rock 로드
          → T_Rock_Diffuse 로드    ← 체인 전체가 한 번에 딸려 올라옴
```

참조 체인이 깊을수록 초기 로드 시간이 길어진다.

### Soft 참조 — 명시적 요청 시에만

```cpp
UPROPERTY()
TSoftObjectPtr<UStaticMesh> MyMesh;   // Soft 참조
```

레벨이 로드돼도 `MyMesh` 패키지는 로드되지 않는다. 직접 요청해야 한다.

```cpp
// 동기 로드 (완료까지 게임 스레드 블로킹)
UStaticMesh* Mesh = MyMesh.LoadSynchronous();

// 비동기 로드 (완료 시 콜백)
StreamableManager.RequestAsyncLoad(
    MyMesh.ToSoftObjectPath(),
    FStreamableDelegate::CreateUObject(this, &AMyActor::OnMeshLoaded)
);
```

### 레벨 스트리밍 — 조건 충족 시

```
플레이어가 특정 구역 진입
  → ULevelStreaming 조건 감지
  → 해당 맵 패키지 비동기 로드 → 로드 완료 후 레벨 활성화
```

---

## 내 노트
