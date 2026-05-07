# Core Redirects

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/CoreRedirects.cpp`  
> `Config/DefaultEngine.ini`

---

## Core Redirects란

클래스·프로퍼티·열거형·구조체를 **리네임했을 때 기존 에셋이 깨지지 않도록** 로드 시점에 이름을 교체해주는 시스템이다.

### 왜 필요한가

`.uasset` 파일 안의 Import 테이블에는 참조하는 클래스·프로퍼티의 **이름 문자열**이 저장된다.  
클래스 이름을 바꾸면 기존 `.uasset`의 Import 테이블에는 구 이름이 그대로 남는다.

```
BP_Hero.uasset Import 테이블:
  /Script/MyGame.OldClassName   ← 리네임 전 이름이 박혀 있음
```

Core Redirects가 없으면 로드 시 `/Script/MyGame.OldClassName`을 찾지 못해 에셋이 깨진다.  
Core Redirects가 있으면 로드 시 구 이름을 새 이름으로 교체해 정상 로드된다.

---

## 동작 시점

패키지 로드 파이프라인의 Import 해석 단계에서 적용된다.

```
FLinkerLoad가 Import 테이블 읽기
  → 각 Import 이름에 Core Redirects 적용
      OldClassName → NewClassName 교체
  → 교체된 이름으로 UClass 검색
  → 포인터 복원
```

에디터에서 **"Fix Up Redirectors"** 를 실행하면 에셋 파일 자체의 이름을 새 이름으로 갱신하고  
Core Redirects 항목을 제거할 수 있다. 배포 전에 정리하는 것이 권장된다.

---

## 지원하는 종류

### ClassRedirects — 클래스 리네임

```ini
[CoreRedirects]
+ClassRedirects=(OldName="OldClassName", NewName="NewClassName")

; 모듈까지 포함한 전체 경로
+ClassRedirects=(OldName="/Script/OldModule.OldClass", NewName="/Script/NewModule.NewClass")
```

C++ 클래스와 Blueprint 클래스 모두 지원한다.

### PropertyRedirects — 프로퍼티 리네임

```ini
+PropertyRedirects=(OldName="MyClass.OldPropertyName", NewName="NewPropertyName")
```

클래스 이름과 함께 써야 한다. 저장된 델타 데이터의 프로퍼티 이름 키를 교체한다.

### EnumRedirects — 열거형 리네임

```ini
; 열거형 타입 자체를 리네임
+EnumRedirects=(OldName="OldEnumName", NewName="NewEnumName")

; 열거형 값을 리네임
+EnumRedirects=(OldName="OldEnumName", NewName="NewEnumName", ValueChanges=(("OldValue","NewValue")))
```

### StructRedirects — 구조체 리네임

```ini
+StructRedirects=(OldName="OldStructName", NewName="NewStructName")
```

### PackageRedirects — 패키지(모듈) 리네임

```ini
+PackageRedirects=(OldName="/OldModule", NewName="/NewModule", MatchSubstring=true)
```

모듈 전체를 리네임할 때 사용한다.

### FunctionRedirects — 함수 리네임

```ini
+FunctionRedirects=(OldName="MyClass.OldFunctionName", NewName="NewFunctionName")
```

---

## 설정 위치

프로젝트의 `Config/DefaultEngine.ini` 또는 플랫폼별 ini 파일에 작성한다.

```ini
[CoreRedirects]
+ClassRedirects=(OldName="AMyOldActor", NewName="AMyNewActor")
+PropertyRedirects=(OldName="AMyNewActor.OldSpeed", NewName="NewSpeed")
```

플러그인은 플러그인 자체의 `Config/` 폴더에 ini를 둘 수 있다.

---

## Soft 참조와의 관계

Soft 참조(`TSoftObjectPtr`, `TSoftClassPtr`)는 경로 문자열을 그대로 저장한다.  
Core Redirects는 로드 시점에 적용되므로 Soft 참조로 저장된 구 경로도 교체된다.  
단, "Fix Up Redirectors"를 실행하면 Soft 참조 경로도 새 이름으로 갱신된다.

---

## 내 노트
