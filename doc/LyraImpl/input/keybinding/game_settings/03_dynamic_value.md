# 03. Dynamic Value + DataSource — 코드 없이 설정 연결

> 출처: `Plugins/GameSettings/Source/Public/GameSettingValueDiscreteDynamic.h`  
>        `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSource.h`  
>        `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSourceDynamic.h`

---

## 왜 Dynamic이 필요한가

`UGameSettingValueDiscrete`는 추상 클래스라서 쓰려면 반드시 서브클래싱해야 한다.  
설정 항목이 10개면 클래스도 10개를 만들어야 한다는 뜻이다.

`UGameSettingValueDiscreteDynamic`은 이 문제를 해결한다.  
**"어떤 값을 읽고, 어떤 값을 쓸지"를 클래스 상속 대신 외부에서 주입**한다.  
결과적으로 클래스를 새로 만들지 않아도 설정 항목을 만들 수 있다.

```
[기존 방식] 설정 항목마다 클래스 생성
  UResolutionSetting   extends UGameSettingValueDiscrete
  UColorBlindSetting   extends UGameSettingValueDiscrete
  UFramerateSetting    extends UGameSettingValueDiscrete
  ...

[Dynamic 방식] 클래스 하나 + 데이터만 주입
  UGameSettingValueDiscreteDynamic_Enum  (Getter 주입, Setter 주입, 옵션 목록 주입)
  UGameSettingValueDiscreteDynamic_Bool  (Getter 주입, Setter 주입)
  UGameSettingValueDiscreteDynamic_Number
```

---

## 전체 흐름 한눈에 보기

색맹 모드 설정을 예로 들면:

```
[설정 화면 위젯]
    사용자가 "녹색약" 선택
        │
        ▼
[UGameSettingValueDiscreteDynamic_Enum]
    SetDiscreteOptionByIndex(1)
        │  "EColorBlindMode::Deuteranope" 문자열 전달
        ▼
[FGameSettingDataSourceDynamic]
    경로: ["SharedSettings", "ColorBlindMode"]
        │  ULocalPlayer → SharedSettings → ColorBlindMode 프로퍼티에 값 씀
        ▼
[ULyraSettingsShared::ColorBlindMode]
    실제 변수 값이 바뀜
```

읽기도 같은 경로를 역방향으로 따라간다.  
Setting이 현재 선택지 인덱스를 알아야 할 때 → Getter로 문자열 읽기 → `OptionValues` 배열에서 인덱스 찾기.

---

## `FGameSettingDataSource` — 값 읽기/쓰기 추상화

DataSource는 "실제 데이터가 어디 있는지"를 캡슐화한 오브젝트다.  
Setting은 DataSource를 통해서만 실제 값에 접근하고, 값이 어디 저장되는지는 신경 쓰지 않는다.

```cpp
class FGameSettingDataSource
{
    // 실제로 읽기/쓰기가 가능한 상태인지 확인 (오브젝트가 유효한지 등)
    virtual bool Resolve(ULocalPlayer* InContext) = 0;

    // 현재 값을 문자열로 읽기
    virtual FString GetValueAsString(ULocalPlayer* InContext) const = 0;

    // 문자열 값을 실제 데이터에 쓰기
    virtual void SetValue(ULocalPlayer* InContext, const FString& Value) = 0;

    // 비동기 초기화 (기본 구현은 즉시 완료)
    virtual void Startup(ULocalPlayer* LP, FSimpleDelegate StartupCompleteCallback)
    {
        StartupCompleteCallback.ExecuteIfBound();
    }
};
```

**모든 값을 `FString`으로 주고받는 이유:**  
DataSource는 타입을 모른다. Bool인지 Enum인지 Number인지는 서브클래스(`_Bool`, `_Enum`, `_Number`)가 변환을 담당한다.  
DataSource는 그냥 문자열을 넣고 뺄 뿐이다.

| 실제 타입 | FString 표현 |
|---|---|
| `bool` | `"true"` / `"false"` |
| `EColorBlindMode::Deuteranope` | `"EColorBlindMode::Deuteranope"` |
| `int32 60` | `"60"` |

**`Startup()`이 비동기인 경우:**  
플랫폼 계정 정보처럼 준비까지 시간이 필요한 DataSource는 `StartupCompleteCallback`을 나중에 호출한다.  
Registry는 모든 Setting이 `bReady = true` 상태가 될 때까지 UI를 띄우지 않으므로, DataSource 준비가 끝나야 Setting도 Ready가 된다.

---

## `FGameSettingDataSourceDynamic` — 프로퍼티 경로 기반

DataSource의 구현체 중 하나. **ULocalPlayer에서 시작하는 프로퍼티 경로**를 배열로 받아서,  
리플렉션(`FProperty`)으로 경로를 따라가 값을 읽고 쓴다.

```cpp
// ULocalPlayer → SharedSettings(UObject) → ColorBlindMode(프로퍼티)
MakeShared<FGameSettingDataSourceDynamic>(TArray<FString>{
    "SharedSettings",   // ULocalPlayer의 멤버 오브젝트 이름
    "ColorBlindMode"    // 그 오브젝트의 프로퍼티 이름
})
```

경로 중간 단계는 UObject여야 하고, 최종 단계가 실제로 읽고 쓸 프로퍼티다.  
`UPROPERTY`로 노출된 것이라면 타입 불문하고 모두 사용 가능하다.

```
ULocalPlayer
    └─ SharedSettings  (ULyraSettingsShared*)   ← 경로[0]
            └─ ColorBlindMode (EColorBlindMode) ← 경로[1], 여기에 읽고 씀
```

---

## `UGameSettingValueDiscreteDynamic` 내부 구조

### 옵션 저장 방식

```
OptionValues      : ["true", "false"]                     ← 실제 비교/저장에 쓰는 문자열
OptionDisplayTexts: ["켜짐", "꺼짐"]                       ← 위젯에 표시되는 텍스트
```

인덱스로 연결된다. index 0 → "true" / "켜짐", index 1 → "false" / "꺼짐".

**현재 선택 인덱스를 구하는 과정:**

```
GetDiscreteOptionIndex() 호출
    │
    ├─ Getter->GetValueAsString(LocalPlayer)  → "true" 읽어옴
    │
    └─ OptionValues 배열에서 "true" 위치 탐색 → index 0 반환
```

**사용자가 선택을 바꿀 때:**

```
SetDiscreteOptionByIndex(1) 호출
    │
    ├─ OptionValues[1] = "false"
    │
    └─ Setter->SetValue(LocalPlayer, "false")  → 실제 프로퍼티에 씀
```

### StoreInitial / RestoreToInitial

취소 버튼을 위한 스냅샷 기능이다.  
설정 화면을 열 때 현재 값을 문자열로 기록해두고, 취소하면 그 문자열로 되돌린다.

```cpp
void StoreInitial() override
{
    // "설정 화면 열기 전" 값을 문자열로 기록
    InitialValue = Getter->GetValueAsString(LocalPlayer);
}

void RestoreToInitial() override
{
    // 기록해둔 문자열을 다시 Setter로 씀
    SetValueFromString(InitialValue, EGameSettingChangeReason::RestoreToInitial);
}
```

### 대소문자 무시 비교

Enum 이름 문자열은 플랫폼/컴파일러에 따라 대소문자가 다를 수 있어서  
`OptionValues`에서 현재 값을 찾을 때 대소문자를 무시하고 비교한다.

---

## 서브클래스 목록

공통 구조: **Getter/Setter 주입 + 타입별 변환 담당**.

### `UGameSettingValueDiscreteDynamic_Bool`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Bool>();
Setting->SetDynamicGetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "bSomeFlag"}));
Setting->SetDynamicSetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "bSomeFlag"}));
Setting->SetDefaultValue(false);
Setting->SetTrueText(LOCTEXT("On", "켜짐"));
Setting->SetFalseText(LOCTEXT("Off", "꺼짐"));
```

내부적으로 `AddDynamicOption("true", TrueText)`, `AddDynamicOption("false", FalseText)`를 순서대로 추가한다.  
즉 index 0 = 켜짐, index 1 = 꺼짐.

### `UGameSettingValueDiscreteDynamic_Enum`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Enum>();
Setting->SetDynamicGetter(...);
Setting->SetDynamicSetter(...);
Setting->SetDefaultValue(EColorBlindMode::Off);
Setting->AddEnumOption(EColorBlindMode::Off,         LOCTEXT("Off", "없음"));
Setting->AddEnumOption(EColorBlindMode::Deuteranope, LOCTEXT("D",   "녹색약"));
Setting->AddEnumOption(EColorBlindMode::Protanope,   LOCTEXT("P",   "적색약"));
```

`AddEnumOption` 내부에서 `StaticEnum<T>()->GetNameStringByValue(EnumValue)`로  
Enum 값을 `"EColorBlindMode::Deuteranope"` 같은 문자열로 변환해 `OptionValues`에 저장한다.

### `UGameSettingValueDiscreteDynamic_Number`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Number>();
Setting->SetDynamicGetter(...);
Setting->SetDynamicSetter(...);
Setting->SetDefaultValue(60);
Setting->AddOption(30,  LOCTEXT("30",  "30fps"));
Setting->AddOption(60,  LOCTEXT("60",  "60fps"));
Setting->AddOption(120, LOCTEXT("120", "120fps"));
```

`LexToString(30)` = `"30"`, `LexFromString("60")` = `60`으로 숫자 ↔ 문자열 변환한다.

### `UGameSettingValueDiscreteDynamic_Color` / `_Vector2D`

특수 타입 대응 서브클래스. 구조는 동일하고 변환 방식만 다르다.  
(`FLinearColor::ToString()`, `FVector2D::ToString()` 사용)

---

## Lyra에서의 실제 사용 예

```cpp
// ULyraGameSettingRegistry 계열 파일에서
auto* ColorBlindSetting = NewObject<UGameSettingValueDiscreteDynamic_Enum>();
ColorBlindSetting->SetDevName(TEXT("ColorBlindMode"));
ColorBlindSetting->SetDisplayName(LOCTEXT("ColorBlindMode", "색맹 모드"));

// Getter, Setter 모두 같은 경로 (읽기/쓰기 대상이 동일)
ColorBlindSetting->SetDynamicGetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "ColorBlindMode"}));
ColorBlindSetting->SetDynamicSetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "ColorBlindMode"}));

ColorBlindSetting->SetDefaultValue(EColorBlindMode::Off);
ColorBlindSetting->AddEnumOption(EColorBlindMode::Off,         LOCTEXT("Off", "없음"));
ColorBlindSetting->AddEnumOption(EColorBlindMode::Deuteranope, LOCTEXT("D",   "녹색약"));
ColorBlindSetting->AddEnumOption(EColorBlindMode::Protanope,   LOCTEXT("P",   "적색약"));
```

---

## 키 바인딩이 Dynamic을 쓰지 않는 이유

`ULyraSettingKeyboardInput`은 `UGameSettingValue`를 **직접 서브클래싱**한다.  
키 바인딩은 "프로퍼티 경로"로 표현할 수 없기 때문이다.

- Dynamic: `["SharedSettings", "ColorBlindMode"]` 같은 단순 경로로 값 하나를 읽고 쓴다
- 키 바인딩: Primary 슬롯 / Secondary 슬롯이 따로 있고, Enhanced Input의 `MapPlayerKey()` API를 호출해야 하며, 모달 UI도 필요하다

이런 복잡한 동작은 서브클래싱으로 직접 구현하는 게 맞다.
