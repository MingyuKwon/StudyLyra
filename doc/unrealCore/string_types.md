# UE5 String 타입 — FString, FName, FText

> 소스:  
> `Engine/Source/Runtime/Core/Public/Containers/UnrealString.h`  
> `Engine/Source/Runtime/Core/Public/UObject/NameTypes.h`  
> `Engine/Source/Runtime/Core/Public/Internationalization/Text.h`

언리얼에서 문자열을 표현하는 세 가지 타입과 각각의 특징.

---

## FString

범용 가변 문자열. 내부는 `TArray<TCHAR>`로 구현되어 heap에 할당된다.

```cpp
FString Str = TEXT("Hello");
Str += TEXT(" World");                          // 이어붙이기
Str.Append(TEXT("!"));
bool bFound = Str.Contains(TEXT("World"));      // 검색
FString Result = Str.Replace(TEXT("World"), TEXT("UE5"));
int32 Len = Str.Len();

// 숫자 변환
FString NumStr = FString::FromInt(42);
FString FloatStr = FString::SanitizeFloat(3.14f);
int32 Num = FCString::Atoi(*Str);               // * 로 TCHAR* 추출
```

- 문자 하나 수정·삽입·삭제 등 일반적인 문자열 조작에 사용
- 복사 시 내용 전체를 복사하므로 비용이 있다
- 함수 파라미터로 넘길 때는 `const FString&`으로 받는 것이 기본

---

## FName

전역 **Name Table(FNamePool)** 에 등록되는 해시 기반 식별자.

### 구조

```
최초 생성: FName(TEXT("MyActor"))
  → FNamePool에서 "MyActor" 검색
  → 없으면 등록 후 인덱스 배정
  → 있으면 기존 인덱스 반환

FName 변수가 실제로 들고 다니는 것:
  FName
  ├── Index  (int32) ← Name Table 인덱스
  └── Number (int32) ← 중복 구분용 ("MyActor_0", "MyActor_1" 등)
```

같은 문자열은 테이블에 한 번만 저장된다.  
FName 변수 자체는 인덱스만 들고 다니므로 **복사·비교가 O(1)** 이다.

### 특징

- 대소문자를 **구분하지 않는다** — `"MyActor" == "myactor"` 는 true
- 한 번 등록된 이름은 프로그램 종료 시까지 테이블에 남는다 (해제 없음)
- 리플렉션 시스템에서 프로퍼티명·함수명·클래스명에 FName을 사용하는 이유가 이것 — 수십만 번 비교해도 O(1)

```cpp
FName Name1 = FName(TEXT("Fire"));
FName Name2 = FName(TEXT("fire"));

Name1 == Name2;          // true (대소문자 무시)
Name1.ToString();        // "Fire" (원본 대소문자 보존)
Name1.IsValid();         // 유효한 FName인지
NAME_None == FName();    // 빈 FName 비교
```

### 언제 쓰는가

| 사용처 | 이유 |
|--------|------|
| 에셋 이름, 소켓 이름 | 식별자 비교가 빈번, O(1) 비교 필요 |
| `FindFunctionByName()` | 함수명이 FName |
| `FindPropertyByName()` | 프로퍼티명이 FName |
| `GameplayTag` 내부 | 태그 경로가 FName 체인 |

---

## FText

로컬라이제이션을 지원하는 문자열. UI에 표시되는 텍스트에만 사용한다.

### 구조

```
FText
├── 로컬라이제이션 키 (Namespace + Key)  ← 번역 테이블 참조
└── 현재 언어에 맞는 문자열 캐시
```

빌드 시 `Namespace::Key` 조합으로 번역 테이블(.po 파일)을 참조한다.  
런타임에 언어를 바꾸면 FText가 자동으로 갱신된다.

```cpp
// 번역 가능 — Namespace "MyGame", Key "HealthLabel"
FText Text = NSLOCTEXT("MyGame", "HealthLabel", "체력");

// 번역 불필요한 경우 (디버그, 로그)
FText Text2 = FText::FromString(TEXT("Hello"));  // 로컬라이즈 안 됨

// 숫자 포맷
FText NumText = FText::AsNumber(1234567);        // "1,234,567" (로케일 적용)
FText PctText = FText::AsPercent(0.75f);         // "75%"
```

- `FText`끼리 직접 비교(`==`)는 피한다 — 번역 결과를 비교하는 것이므로 의도가 불명확
- 비교가 필요하면 `FString`으로 변환 후 비교

---

## 세 타입 비교

| | FString | FName | FText |
|--|---------|-------|-------|
| 내부 구조 | `TArray<TCHAR>` (heap) | Name Table 인덱스 (int32) | heap + 로컬라이즈 키 |
| 복사 비용 | 있음 (문자 전체 복사) | 없음 (인덱스만) | 있음 |
| 비교 속도 | O(n) | O(1) | 느림 |
| 대소문자 | 구분 | **무시** | - |
| 로컬라이제이션 | X | X | O |
| 주요 용도 | 일반 문자열 처리·조작 | 식별자, 에셋·함수·프로퍼티 이름 | UI 표시 텍스트 |

---

## 타입 간 변환

```cpp
FString Str = TEXT("Hello");

// FString → 다른 타입
FName Name  = FName(*Str);                // *로 TCHAR* 추출 후 FName 생성
FText Text  = FText::FromString(Str);     // 로컬라이즈 안 되는 FText

// FName → FString
FString s1 = Name.ToString();

// FText → FString
FString s2 = Text.ToString();             // 현재 언어로 로컬라이즈된 결과

// 리터럴
FString s3 = TEXT("Hello");              // TEXT() 필수 — TCHAR* 리터럴
FName   n1 = TEXT("MyActor");
FText   t1 = LOCTEXT("Key", "안녕");     // 번역 가능 버전
```

> `TEXT()` 매크로 없이 `"Hello"` 를 쓰면 `char*` 리터럴이 된다.  
> 유니코드 문자가 포함된 경우 플랫폼에 따라 깨질 수 있으므로 항상 `TEXT()`를 붙인다.

---

## 내 노트
