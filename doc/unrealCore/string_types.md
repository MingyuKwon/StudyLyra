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

### 사용 예시

#### 소켓·본 이름

스켈레탈 메시의 소켓이나 본은 FName으로 식별한다.
캐릭터 이동 중 매 틱마다 조회되므로 O(1) 비교가 중요하다.

```cpp
// 소켓 위치·회전 조회
FVector  SocketLoc = Mesh->GetSocketLocation(FName("hand_r"));
FRotator SocketRot = Mesh->GetSocketRotation(FName("hand_r"));

// 소켓에 붙이기
WeaponActor->AttachToComponent(
    Mesh,
    FAttachmentTransformRules::SnapToTargetIncludingScale,
    FName("weapon_socket")
);

// 본 이름으로 Physics 설정
Mesh->SetAllBodiesBelowSimulatePhysics(FName("pelvis"), true);
```

#### 컴포넌트 생성 이름

`CreateDefaultSubobject`의 이름 파라미터가 FName이다.
이 이름은 컴포넌트의 `GetFName()`으로 조회되고, 에디터 계층 패널에 표시된다.

```cpp
AMyActor::AMyActor()
{
    CameraComponent = CreateDefaultSubobject<UCameraComponent>(FName("CameraComponent"));
    SpringArm = CreateDefaultSubobject<USpringArmComponent>(FName("SpringArm"));
}
```

#### 머티리얼 파라미터 이름

머티리얼 인스턴스의 파라미터를 이름으로 조회·설정한다.

```cpp
UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Material, this);

MID->SetScalarParameterValue(FName("Opacity"), 0.5f);
MID->SetVectorParameterValue(FName("Color"), FLinearColor::Red);

// 파라미터 존재 여부 확인
float Value;
bool bFound = MID->GetScalarParameterValue(FName("Opacity"), Value);
```

#### 애니메이션 — 몽타주 섹션·커브 이름

```cpp
// 몽타주의 특정 섹션부터 재생
AnimInstance->Montage_Play(AttackMontage);
AnimInstance->Montage_JumpToSection(FName("ComboB"), AttackMontage);

// 애니메이션 커브 값 읽기 (블렌드 스페이스, 노티파이 등에서 설정)
float SpeedCurve = AnimInstance->GetCurveValue(FName("Speed"));
```

#### DataTable 행 이름

DataTable의 각 행은 FName 키로 관리된다.

```cpp
// DataTable에서 행 찾기
if (FMyItemData* Row = ItemDataTable->FindRow<FMyItemData>(FName("Sword_001"), TEXT("")))
{
    int32 Damage = Row->Damage;
}
```

#### Actor Tags

Actor의 `Tags` 배열은 `TArray<FName>`이다.

```cpp
// 태그 확인
if (SomeActor->ActorHasTag(FName("Enemy")))
{
    // 적 처리
}

// 태그 추가
SomeActor->Tags.Add(FName("Stunned"));
```

#### Collision Profile 이름

콜리전 프리셋도 FName으로 식별한다.

```cpp
Mesh->SetCollisionProfileName(FName("BlockAll"));
Mesh->SetCollisionProfileName(FName("OverlapAllDynamic"));
```

#### 리플렉션 시스템

```cpp
UFunction* Func = Actor->FindFunctionByName(FName("Fire"));
FProperty* Prop = Actor->GetClass()->FindPropertyByName(FName("Health"));
```

---

## FText

로컬라이제이션을 지원하는 문자열. UI에 표시되는 텍스트에만 사용한다.

### 구조

```
FText (번역 가능한 경우)
├── 로컬라이제이션 키 (Namespace + Key)  ← 번역 테이블 참조
└── 현재 언어에 맞는 문자열 캐시
```

`Namespace + Key` 조합으로 번역 테이블을 참조한다.  
런타임에 언어 설정을 바꾸면 FText가 자동으로 갱신된다.

### FText 생성 방법

`NSLOCTEXT`는 FText를 만들어 반환하는 매크로다. FText가 타입이고, NSLOCTEXT는 그 타입을 초기화하는 방법 중 하나다 (`int32 x = 42`에서 `42`가 int32를 만드는 것과 같다).

```cpp
// 번역 가능 — Namespace, Key, 번역 없을 때 폴백 순
FText A = NSLOCTEXT("MyGame", "HealthLabel", "체력");
// 영어 설정 시 → "Health" (번역 파일에 등록돼 있으면)

// 번역 불필요한 동적 값
FText B = FText::FromString(PlayerName);

// 숫자·퍼센트 — 로케일에 맞는 구분자 자동 적용
FText C = FText::AsNumber(1234567);   // "1,234,567"
FText D = FText::AsPercent(0.75f);   // "75%"

// 만드는 방법과 무관하게 동일하게 사용
MyTextBlock->SetText(A);
FString Str = A.ToString();  // 현재 언어로 로컬라이즈된 결과 반환
```

파일 상단에 `LOCTEXT_NAMESPACE`를 선언하면 Namespace를 매번 쓰지 않아도 된다.

```cpp
#define LOCTEXT_NAMESPACE "MyGame"
FText Label = LOCTEXT("HealthLabel", "체력");  // Namespace 생략
#undef LOCTEXT_NAMESPACE
```

### FText::FromString 주의

`FText::FromString`으로 만든 FText는 Namespace·Key가 없다.  
언어를 바꿔도 문자열이 그대로 남는다.

```cpp
FText Label = FText::FromString(TEXT("체력"));
// 언어를 영어로 바꿔도 → "체력" 그대로
```

번역돼야 하는 고정 문구에는 쓰지 않는다.  
플레이어 이름·점수처럼 애초에 번역 대상이 아닌 동적 값에만 쓴다.

### 상황별 선택

| 상황 | 방법 |
|------|------|
| 번역이 필요한 고정 UI 문구 | `NSLOCTEXT("NS", "Key", "기본값")` |
| 번역 불필요한 동적 값 (이름, 숫자) | `FText::FromString()` / `FText::AsNumber()` |
| 문자열 처리·조작 | `FString` |
| 로그·디버그 출력 | `FString` |

`FText`끼리 직접 비교(`==`)는 피한다. 비교가 필요하면 `FString`으로 변환 후 비교한다.

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
