# UPackage — 로드 파이프라인

## FLinkerLoad

`FLinkerLoad` — 패키지 파일을 디스크에서 읽는 클래스다.  
패키지 로드 요청이 들어오면 FLinkerLoad가 파일을 열고 오브젝트를 복원한다.

패키지 파일의 내부 구조:

```
파일 헤더      (버전, 플래그 등 요약 정보)
Name 테이블    (파일 안에서 쓰이는 FName 문자열 목록)
Import 테이블  (이 패키지가 참조하는 다른 패키지의 오브젝트 목록)
Export 테이블  (이 패키지에 실제로 들어있는 오브젝트 목록)
Export 데이터  (각 오브젝트의 직렬화된 프로퍼티 값 — CDO 대비 델타)
```

Import는 "다른 파일에서 빌려 쓰는 것", Export는 "이 파일이 소유한 것"이다.  
포인터 복원 시 Import 테이블의 경로 문자열로 다른 패키지를 찾아 포인터를 연결한다.

---

## 오브젝트 복원 흐름

```
패키지 로드 요청
  → FLinkerLoad 파일 열기
  → Export 테이블 순회 (1차) — 각 오브젝트마다:
        StaticConstructObject_Internal()   ← 생성 + CDO 복사
        RF_NeedLoad 플래그 부착            ← "아직 읽을 데이터 있음"

  → Export 데이터 순회 (2차) — 각 오브젝트마다:
        Serialize()                        ← 델타 데이터 덮어씀
        RF_NeedLoad 제거

  → PostLoad() 호출                        ← 모든 Serialize 완료 후
```

두 순회가 분리된 이유: A가 B를 참조할 때 A를 Serialize하기 전에 B가 먼저 존재해야 하므로,  
전체 오브젝트를 먼저 생성(1차)하고 나서 데이터를 채운다(2차).

---

## PostLoad

패키지에서 로드된 **모든 Export 오브젝트**에 호출된다.  
호출 순서는 의존성 순서 — A가 B를 참조하면 B의 PostLoad가 먼저 불린다.

용도: 캐시 재구성, 버전 마이그레이션, 포인터 픽스업 등 "데이터가 다 들어온 뒤 처리해야 할 것들".

| | PostInitProperties | PostLoad |
|---|---|---|
| 호출 시점 | 생성자 직후 (항상) | 패키지 Serialize 완료 후 |
| 대상 | 모든 UObject | 패키지에서 로드된 오브젝트만 |
| 용도 | 생성 직후 파생값 초기화 | 캐시 재구성, 버전 마이그레이션, 포인터 픽스업 |

---

## 클래스 로드 vs 인스턴스 생성

SpawnActor로 만드는 오브젝트는 PostLoad가 없다. 디스크에서 읽어오는 게 아니라  
메모리에서 새로 만들기 때문이다. 그런데 "액터 정보는 디스크에서 오는 거 아닌가?" 라는 의문이 생긴다.

**클래스 정보의 로드**와 **인스턴스 생성**은 별개의 단계다.

```
1단계 — 클래스 로드 (패키지 로드, 한 번만)
  BP_Hero.uasset 로드
    → UBlueprintGeneratedClass "BP_Hero_C" 복원   ← PostLoad 호출됨
    → BP_Hero CDO 복원                             ← PostLoad 호출됨

2단계 — 인스턴스 생성 (런타임, 매번)
  SpawnActor<ABP_Hero>()
    → 이미 메모리에 있는 UClass와 CDO를 참고해 새 오브젝트 생성
    → CDO에서 프로퍼티 복사
    → PostInitProperties                           ← PostLoad 없음
```

SpawnActor는 클래스 정보(1단계에서 이미 메모리에 올라온 UClass + CDO)를 바탕으로  
**메모리에서 새 오브젝트를 만드는 것**이다. 인스턴스 자체는 디스크에서 읽어오는 게 아니다.

레벨 배치 액터는 인스턴스 데이터(델타)가 `.umap`에 저장되어 있어 디스크에서 복원한다.  
런타임 스폰 액터는 어느 파일에도 인스턴스 데이터가 없으므로 PostLoad가 필요 없다.

```
레벨 배치 액터 (디스크에서 복원):
  생성자 → PostInitProperties → Serialize(델타 적용) → PostLoad

런타임 SpawnActor (메모리에서 새로 생성):
  생성자 → PostInitProperties
  (PostLoad 없음)
```

---

## 내 노트
