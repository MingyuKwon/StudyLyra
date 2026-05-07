# Core Redirects

> 출처:  
> `Engine/Source/Runtime/CoreUObject/Private/UObject/CoreRedirects.cpp`  
> `Config/DefaultEngine.ini`

---

## Core Redirects란

클래스·프로퍼티·열거형·구조체를 **리네임했을 때 기존 에셋이 깨지지 않도록** 로드 시점에 이름을 교체해주는 시스템이다.

`.uasset` 파일 안의 Import 테이블에는 참조하는 클래스·프로퍼티의 **이름 문자열**이 저장된다.  
클래스 이름을 바꾸면 기존 `.uasset`의 Import 테이블에는 구 이름이 그대로 남는다.

```
BP_Hero.uasset Import 테이블:
  /Script/MyGame.OldClassName   ← 리네임 전 이름이 박혀 있음
```

Core Redirects가 없으면 로드 시 구 이름을 찾지 못해 에셋이 깨진다.  
Core Redirects가 있으면 로드 시 구 이름을 새 이름으로 교체해 정상 로드된다.

---

## 동작 — 에셋 파일은 수정되지 않는다

**Core Redirects는 에셋 파일 자체를 수정하지 않는다.**  
`.uasset` 안의 구 이름은 그대로 남고, 로드 시점에 **메모리 안에서만** 번역이 일어난다.

```
.uasset 파일:   /Script/MyGame.OldClassName  ← 파일에는 구 이름 그대로
Core Redirects 적용 (메모리):
  OldClassName → NewClassName 교체
  교체된 이름으로 UClass 검색 → 포인터 복원
```

로드할 때마다 번역 비용이 발생하므로 **배포 전에는 반드시 정리**해야 한다.

### Fix Up Redirectors

에디터에서 **"Fix Up Redirectors"** 를 실행하면 에셋 파일 자체를 새 이름으로 갱신한다.

```
Fix Up Redirectors 실행:
  1. 영향받는 에셋 전부 로드
  2. Core Redirects 적용 후 새 이름으로 다시 저장
  3. .uasset 파일 안의 이름이 새 이름으로 갱신됨
  4. Core Redirects 항목 제거 가능
```

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
; 열거형 타입 리네임
+EnumRedirects=(OldName="OldEnumName", NewName="NewEnumName")

; 열거형 값 리네임
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

### FunctionRedirects — 함수 리네임

```ini
+FunctionRedirects=(OldName="MyClass.OldFunctionName", NewName="NewFunctionName")
```

---

## 설정 위치

프로젝트의 `Config/DefaultEngine.ini`에 작성한다.  
플러그인은 플러그인 자체의 `Config/` 폴더 ini에 둘 수 있다.

```ini
[CoreRedirects]
+ClassRedirects=(OldName="AMyOldActor", NewName="AMyNewActor")
+PropertyRedirects=(OldName="AMyNewActor.OldSpeed", NewName="NewSpeed")
```

---

## Soft 참조와의 관계

Soft 참조(`TSoftObjectPtr`, `TSoftClassPtr`)는 내부적으로 경로 문자열(`FSoftObjectPath`)을 저장한다.

```cpp
TSoftObjectPtr<UStaticMesh> MyMesh;
// 내부: FSoftObjectPath = "/Game/Meshes/SM_Rock.SM_Rock"
```

에디터에서 이 값을 설정하면 경로 문자열이 `.uasset`에 직렬화된다.  
Core Redirects는 두 시점에 적용된다.

```
① 포함된 에셋이 로드될 때:
  .uasset 안의 FSoftObjectPath 문자열 읽기
  → Core Redirects 적용 → 새 경로로 교체 (메모리에서)

② 실제 로드 요청 시 (LoadSynchronous / AsyncLoad):
  경로 문자열로 패키지 찾기 전에 Core Redirects 적용
  → 새 경로로 에셋 로드
```

단, **런타임에 코드에서 직접 문자열로 만든 경로**는 Core Redirects가 적용되지 않는다.

```cpp
// 직렬화된 값 → Core Redirects 적용됨 ✓
UPROPERTY()
TSoftObjectPtr<UStaticMesh> MyMesh;  // 에디터에서 설정한 값

// 코드에서 직접 만든 문자열 → Core Redirects 적용 안 됨 ✗
FSoftObjectPath Path(TEXT("/Game/Meshes/OldName.OldName"));
```

Fix Up Redirectors는 Soft Reference 문자열도 `.uasset` 안에서 새 경로로 갱신한다.

---

## 내 노트
