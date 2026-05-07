# UPackage — 개념

## UPackage란

UObject 시스템의 파일·모듈 단위 컨테이너다.  
모든 UObject는 반드시 어떤 패키지에 속해야 한다 — 패키지가 오브젝트의 소속 파일을 결정한다.

---

## 왜 필요한가 — 포인터는 저장할 수 없다

런타임 포인터 주소는 다음 실행 때 달라진다.  
**문자열 경로만이 실행 간에 유효하게 오브젝트를 식별**할 수 있다.

```
/Game/Meshes/SM_Rock . SM_Rock
      ↑                  ↑
  UPackage 경로     패키지 안 오브젝트 이름
```

```
저장:
  MeshComp->StaticMesh = SM_Rock (포인터)
  → GetPathName()으로 경로 변환
  → "/Game/Meshes/SM_Rock.SM_Rock" 문자열을 파일에 기록

로드:
  "/Game/Meshes/SM_Rock.SM_Rock" 읽음
  → UPackage("/Game/Meshes/SM_Rock") 로드 (SM_Rock.uasset 열기)
  → 패키지 안에서 이름 "SM_Rock" 오브젝트 검색
  → 포인터 복원
```

패키지 경로가 없으면 저장된 참조를 로드 시 복원할 수 없다.  
Outer 체인을 타고 올라가면 반드시 UPackage에 도달하는 구조가 이 경로 체계를 보장한다.

---

## 내 노트
