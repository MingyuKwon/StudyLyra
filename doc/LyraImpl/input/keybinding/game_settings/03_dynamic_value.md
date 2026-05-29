# 03. Dynamic Value + DataSource — 코드 없이 설정 연결

> 출처: `Plugins/GameSettings/Source/Public/GameSettingValueDiscreteDynamic.h`  
>        `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSource.h`  
>        `Plugins/GameSettings/Source/Public/DataSource/GameSettingDataSourceDynamic.h`

---

## 왜 Dynamic이 필요한가

`UGameSettingValueDiscrete`를 서브클래싱하려면 각 설정마다 클래스를 하나씩 만들어야 한다.  
`UGameSettingValueDiscreteDynamic`은 **Getter/Setter를 데이터 오브젝트로 주입**해서 서브클래싱 없이 설정 항목을 만들 수 있게 한다.

```cpp
// 서브클래싱 없이 설정 생성
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Bool>();
Setting->SetDynamicGetter(MakeShared<FGameSettingDataSourceDynamic>(/* 읽기 */));
Setting->SetDynamicSetter(MakeShared<FGameSettingDataSourceDynamic>(/* 쓰기 */));
Setting->SetTrueText(LOCTEXT("On", "켜짐"));
Setting->SetFalseText(LOCTEXT("Off", "꺼짐"));
```

---

## `FGameSettingDataSource` — 값 읽기/쓰기 추상화

```cpp
class FGameSettingDataSource
{
    virtual bool Resolve(ULocalPlayer* InContext) = 0;
    virtual FString GetValueAsString(ULocalPlayer* InContext) const = 0;
    virtual void SetValue(ULocalPlayer* InContext, const FString& Value) = 0;
    virtual void Startup(ULocalPlayer* LP, FSimpleDelegate StartupCompleteCallback)
    {
        StartupCompleteCallback.ExecuteIfBound();  // 기본: 즉시 완료
    }
};
```

모든 값을 `FString`으로 주고받는다. `Bool`은 `"true"/"false"`, `Enum`은 이름 문자열, `Number`는 숫자 문자열.  
`Resolve()`는 실제 읽기/쓰기가 가능한 상태인지 확인한다.

`Startup()`이 비동기인 경우: 플랫폼 계정 정보처럼 준비까지 시간이 필요한 소스는 `StartupCompleteCallback`을 나중에 호출한다. Setting이 `bReady` 상태가 되려면 DataSource가 완료되어야 한다.

---

## `FGameSettingDataSourceDynamic` — 프로퍼티 경로 기반

```cpp
// ULocalPlayer의 서브오브젝트 프로퍼티를 경로로 지정
MakeShared<FGameSettingDataSourceDynamic>(TArray<FString>{
    "SharedSettings",       // ULocalPlayer->SharedSettings
    "ColorBlindMode"        // SharedSettings->ColorBlindMode
})
```

UObject 참조 경로를 배열로 지정하면, 내부에서 `ULocalPlayer`부터 시작해서 경로를 따라가 값을 읽고 쓴다.  
리플렉션(`FProperty`) 기반이므로 `UPROPERTY`로 노출된 것이라면 무엇이든 쓸 수 있다.

---

## `UGameSettingValueDiscreteDynamic` 상세

### 내부 저장 방식

```
OptionValues: TArray<FString>       ← 실제 값 문자열 ("true", "0", "EColorBlindMode::Off" 등)
OptionDisplayTexts: TArray<FText>   ← UI 표시 텍스트 ("켜짐", "빠름", "없음" 등)
```

`GetDiscreteOptions()`는 `OptionDisplayTexts`를 반환한다.  
`GetDiscreteOptionIndex()`는 Getter로 현재 값을 읽어 `OptionValues`에서 인덱스를 찾아 반환한다.

### StoreInitial / RestoreToInitial

```cpp
void StoreInitial() override
{
    InitialValue = Getter->GetValueAsString(LocalPlayer);  // 현재 값 문자열 기록
}

void RestoreToInitial() override
{
    SetValueFromString(InitialValue, EGameSettingChangeReason::RestoreToInitial);
}
```

### 옵션 비교 — 대소문자 무시

```cpp
bool AreOptionsEqual(const FString& A, const FString& B) const
{
    return A.Equals(B, ESearchCase::IgnoreCase);  // Enum 이름 비교 등에서 안전
}
```

---

## 서브클래스 목록

### `UGameSettingValueDiscreteDynamic_Bool`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Bool>();
Setting->SetDynamicGetter(...);
Setting->SetDynamicSetter(...);
Setting->SetDefaultValue(false);
Setting->SetTrueText(LOCTEXT("On", "켜짐"));
Setting->SetFalseText(LOCTEXT("Off", "꺼짐"));
```

내부적으로 `AddDynamicOption("true", TrueText)`, `AddDynamicOption("false", FalseText)` 순서로 추가한다.

### `UGameSettingValueDiscreteDynamic_Enum`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Enum>();
Setting->SetDefaultValue(EColorBlindMode::Off);
Setting->AddEnumOption(EColorBlindMode::Off,         LOCTEXT("Off", "없음"));
Setting->AddEnumOption(EColorBlindMode::Deuteranope, LOCTEXT("D",   "녹색약"));
Setting->AddEnumOption(EColorBlindMode::Protanope,   LOCTEXT("P",   "적색약"));
```

Enum 값 → `StaticEnum<T>()->GetNameStringByValue()`로 문자열 변환해서 저장한다.

### `UGameSettingValueDiscreteDynamic_Number`

```cpp
auto* Setting = NewObject<UGameSettingValueDiscreteDynamic_Number>();
Setting->SetDefaultValue(60);
Setting->AddOption(30,  LOCTEXT("30",  "30"));
Setting->AddOption(60,  LOCTEXT("60",  "60"));
Setting->AddOption(120, LOCTEXT("120", "120"));
```

`LexToString()`/`LexFromString()`으로 숫자 ↔ 문자열 변환한다.

### `UGameSettingValueDiscreteDynamic_Color` / `_Vector2D`

특수 타입 대응 서브클래스. 구조는 동일하고 변환 방식(`FLinearColor::ToString()`, `FVector2D::ToString()`)만 다르다.

---

## Lyra에서의 사용 예

`LyraSettingsShared.cpp`에서 색맹 모드 설정을 Dynamic으로 만드는 패턴:

```cpp
// ULyraGameSettingRegistry_VideoAndDisplay.cpp 계열
auto* ColorBlindSetting = NewObject<UGameSettingValueDiscreteDynamic_Enum>();
ColorBlindSetting->SetDevName(TEXT("ColorBlindMode"));
ColorBlindSetting->SetDisplayName(LOCTEXT("ColorBlindMode", "색맹 모드"));

ColorBlindSetting->SetDynamicGetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "ColorBlindMode"}));
ColorBlindSetting->SetDynamicSetter(MakeShared<FGameSettingDataSourceDynamic>(
    TArray<FString>{"SharedSettings", "ColorBlindMode"}));

ColorBlindSetting->SetDefaultValue(EColorBlindMode::Off);
ColorBlindSetting->AddEnumOption(EColorBlindMode::Off, ...);
// ...
```

키 바인딩은 Dynamic 방식을 쓰지 않고 `ULyraSettingKeyboardInput`을 직접 서브클래싱한다.  
키 변경은 "Getter/Setter 프로퍼티 경로"로 표현할 수 없기 때문이다.
