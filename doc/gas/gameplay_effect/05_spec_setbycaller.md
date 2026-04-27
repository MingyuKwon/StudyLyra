# GESpec & SetByCaller

> **GASDoc**: 4.5.9 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ge-spec"></a>
#### 4.5.9 GameplayEffectSpec (GESpec)

[`GameplayEffectSpec`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayEffectSpec/index.html)(GESpec)은 `GameplayEffect`의 인스턴스화된 표현으로 볼 수 있다. GESpec은 자신이 나타내는 `GameplayEffect` 클래스, 생성 레벨, 생성자 정보를 담고 있다. 디자이너가 런타임 이전에 미리 생성해야 하는 `GameplayEffect`와 달리, GESpec은 런타임에 자유롭게 생성하고 수정한 뒤 적용할 수 있다. `GameplayEffect`를 적용할 때 `GameplayEffect`로부터 `GameplayEffectSpec`이 생성되며, 실제로 적용되는 것은 이 GESpec이다.

`GameplayEffectSpec`은 `UAbilitySystemComponent::MakeOutgoingSpec()`(BlueprintCallable)으로 생성한다. `GameplayEffectSpec`을 즉시 적용하지 않아도 된다. 어빌리티에서 생성된 발사체에 `GameplayEffectSpec`을 전달하여, 발사체가 나중에 맞힌 Target에 적용하는 패턴이 일반적이다. `GameplayEffectSpec`이 성공적으로 적용되면 `FActiveGameplayEffect`라는 새 구조체를 반환한다.

`GameplayEffectSpec`의 주요 구성 요소:
- 이 `GameplayEffectSpec`이 생성된 원본 `GameplayEffect` 클래스
- 이 `GameplayEffectSpec`의 레벨. 보통 생성한 어빌리티의 레벨과 동일하지만 다를 수도 있다
- `GameplayEffectSpec`의 지속 시간. 기본적으로 `GameplayEffect`의 지속 시간을 따르지만 다를 수 있다
- Periodic Effect의 경우 `GameplayEffectSpec`의 주기. 기본적으로 `GameplayEffect`의 주기를 따르지만 다를 수 있다
- 이 `GameplayEffectSpec`의 현재 스택 카운트. 스택 한도는 `GameplayEffect`에 정의된다
- [`GameplayEffectContextHandle`](#concepts-ge-context)은 이 `GameplayEffectSpec`을 누가 생성했는지를 알려준다
- Snapshotting으로 인해 `GameplayEffectSpec` 생성 시점에 캡처된 Attribute 값들
- `DynamicGrantedTags`: `GameplayEffect`가 부여하는 `GameplayTag` 외에 `GameplayEffectSpec`이 Target에 추가로 부여하는 태그
- `DynamicAssetTags`: `GameplayEffect`가 보유한 `AssetTag` 외에 `GameplayEffectSpec`이 추가로 가지는 태그
- `SetByCaller` TMap들

<a name="concepts-ge-spec-setbycaller"></a>
##### 4.5.9.1 SetByCallers

`SetByCaller`는 `GameplayEffectSpec`이 `GameplayTag` 또는 `FName`에 연결된 float 값을 실어 나를 수 있게 한다. 이 값들은 각각 `TMap<FGameplayTag, float>`와 `TMap<FName, float>`로 `GameplayEffectSpec`에 저장된다. 이는 `GameplayEffect`에서 Modifier로 사용하거나, 어빌리티 내부에서 생성된 수치 데이터를 [`GameplayEffectExecutionCalculation`](#concepts-ge-ec)이나 [`ModifierMagnitudeCalculation`](#concepts-ge-mmc)으로 전달하는 일반적인 수단으로 활용된다.

| `SetByCaller` 사용 맥락 | 주의사항 |
| ----------------------- | -------- |
| `Modifier`로 사용 | `GameplayEffect` 클래스에 미리 정의되어야 한다. `GameplayTag` 버전만 사용 가능하다. `GameplayEffect` 클래스에 정의되어 있는데 `GameplayEffectSpec`에 대응하는 태그와 float 값 쌍이 없으면, `GameplayEffectSpec` 적용 시 런타임 에러가 발생하고 0을 반환한다. `Divide` 연산의 경우 이것이 잠재적인 문제가 될 수 있다. [`Modifier`](#concepts-ge-mods) 참조 |
| 그 외 (EC/MMC 등) | 어디에도 미리 정의할 필요가 없다. `GameplayEffectSpec`에 존재하지 않는 `SetByCaller`를 읽으면 개발자가 정의한 기본값을 선택적 경고와 함께 반환할 수 있다 |

Blueprint에서 `SetByCaller` 값을 설정하려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 Blueprint 노드를 사용한다.

Blueprint에서 `SetByCaller` 값을 읽으려면 Blueprint Library에 커스텀 노드를 만들어야 한다.

C++에서 `SetByCaller` 값을 설정하려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 함수를 사용한다.

```c++
void FGameplayEffectSpec::SetSetByCallerMagnitude(FName DataName, float Magnitude);
```
```c++
void FGameplayEffectSpec::SetSetByCallerMagnitude(FGameplayTag DataTag, float Magnitude);
```

C++에서 `SetByCaller` 값을 읽으려면, 필요한 버전(`GameplayTag` 또는 `FName`)의 함수를 사용한다.

```c++
float GetSetByCallerMagnitude(FName DataName, bool WarnIfNotFound = true, float DefaultIfNotFound = 0.f) const;
```
```c++
float GetSetByCallerMagnitude(FGameplayTag DataTag, bool WarnIfNotFound = true, float DefaultIfNotFound = 0.f) const;
```

Blueprint에서 오탈자를 방지하기 위해 `FName` 버전보다 `GameplayTag` 버전 사용을 권장한다.

---

## 내 분석

### Spec이 별도로 존재하는 이유

GE가 CDO 하나를 공유하기 때문에 오히려 Spec이 반드시 필요해진다.

```
GE는 CDO 하나를 모든 적용이 공유
  → CDO는 절대 수정 불가 (공유 객체)
  → "이번 적용에만 해당하는 데이터"를 담을 별도 객체가 필요
  → FGameplayEffectSpec
```

| | `UGameplayEffect` (CDO) | `FGameplayEffectSpec` |
|---|---|---|
| 수명 | 에셋 수명 내내 유지 | 적용마다 생성, 적용 후 소멸 or FActiveGameplayEffect에 보관 |
| 공유 | 모든 적용이 공유 | 적용마다 각자 하나씩 |
| 역할 | 정적 설계 (Modifier 목록, Duration 타입 등) | 동적 적용 컨텍스트 |

**Spec이 담는 "이번 적용에만 해당하는 데이터":**

- **Level** — 발동한 어빌리티 레벨. CDO에 저장 불가 (매 발동마다 다름)
- **EffectContext** — 발동자(Instigator), HitResult 등 런타임 컨텍스트
- **SetByCaller TMap** — 어빌리티가 런타임에 계산한 값을 GE 쪽으로 전달하는 수단 (아래 참조)
- **Captured Attributes (Snapshot)** — 발동 시점의 Attribute 값 보존. 이후 Attribute가 바뀌어도 발동 당시 값 유지
- **DynamicGrantedTags / DynamicAssetTags** — 런타임에만 결정되는 태그

### SetByCaller 사용 패턴

> 소스: `LyraGameplayTags.h/cpp`, `LyraCheatManager.cpp`, `LyraHealthComponent.cpp`, `LyraGameData.h`

SetByCaller는 Spec에 담기는 `TMap<FGameplayTag, float>` 키-값 쌍이다. 호출자가 값을 태그에 묶어 Spec에 주입하고, GE 쪽에서 꺼내 쓴다.

#### 맥락 1 — GE Modifier의 Magnitude로 사용

GE Blueprint에서 Modifier의 Magnitude 타입을 `SetByCaller`로 지정해두면, 호출자가 Spec에 넣은 값이 그대로 Modifier 수치로 사용된다. Lyra는 `DamageGameplayEffect_SetByCaller` / `HealGameplayEffect_SetByCaller` 같은 범용 GE를 등록해두고 여러 곳에서 재사용한다.

```cpp
// LyraCheatManager.cpp, LyraHealthComponent.cpp 동일 패턴
FGameplayEffectSpecHandle SpecHandle =
    ASC->MakeOutgoingSpec(ULyraGameData::Get().DamageGameplayEffect_SetByCaller, 1.0f, ASC->MakeEffectContext());

SpecHandle.Data->SetSetByCallerMagnitude(LyraGameplayTags::SetByCaller_Damage, DamageAmount);
ASC->ApplyGameplayEffectSpecToSelf(*SpecHandle.Data.Get());
```

#### 맥락 2 — Execution / MMC 코드에서 직접 읽기

Execution 코드에서 `GetSetByCallerMagnitude`로 직접 읽는 방법이다. GE Blueprint에 미리 정의할 필요가 없어 유연하다.

```cpp
float DamageAmount = Spec.GetSetByCallerMagnitude(
    LyraGameplayTags::SetByCaller_Damage, /*WarnIfNotFound=*/true, /*Default=*/0.f);
```

#### 두 맥락 비교

| | Modifier로 사용 | EC/MMC에서 직접 읽기 |
|---|---|---|
| GE Blueprint 사전 정의 | **필요** | 불필요 |
| 태그-값 쌍 없으면 | 런타임 에러 + 0 반환 | 기본값 반환 (경고 선택적) |

### SetByCaller 값의 네트워크 동기화

> 소스: `GameplayEffect.h` (SetByCallerTagMagnitudes UPROPERTY), `GameplayEffectTypes.cpp:1288`

**서버→클라이언트 방향은 복제된다. 클라이언트→서버 방향은 불가능하다.**

`FGameplayEffectSpec`의 SetByCaller TMap은 `UPROPERTY`이므로, 서버에서 GE가 Apply된 뒤 `FActiveGameplayEffect`(FFastArraySerializerItem)가 클라이언트로 복제될 때 Spec 안의 SetByCaller 값도 함께 전달된다.

단, Spec 핸들 자체의 직접 전송은 의도적으로 막혀있다:

```cpp
// GameplayEffectTypes.cpp:1288
bool FGameplayEffectSpecHandle::NetSerialize(FArchive& Ar, ...)
{
    ABILITY_LOG(Fatal, TEXT("FGameplayEffectSpecHandle should not be NetSerialized"));
}
```

예측(Prediction) 흐름에서 클라이언트가 SetByCaller를 설정해도, 그 값이 서버로 전송되는 게 아니다. 양쪽이 동일한 GA 코드를 독립적으로 실행해서 각자 값을 계산한다.

| 시나리오 | 전달 여부 |
|---|---|
| 서버 GE Apply → 클라이언트 복제 | ✓ FActiveGameplayEffect.Spec 안에 포함 |
| 클라이언트가 Spec에 SetByCaller 설정 | ✗ 로컬 예측에만 쓰임 |
| Spec 핸들을 직접 RPC 전송 | ✗ Fatal로 차단 |

**실용적 함의**: 데미지 등 민감한 수치는 반드시 서버 권한 GA에서 계산해서 SetByCaller에 넣어야 한다. 클라이언트가 계산한 값을 서버에 신뢰시킬 방법이 없다.

### Snapshotting — Spec 생성 시점에 Attribute 캡처

> 소스: `GameplayEffectAttributeCaptureDefinition.h`, `LyraDamageExecution.cpp`, `LyraHealExecution.cpp`

MMC나 Execution이 Attribute 값을 읽을 때, 그 값을 **언제 찍느냐**를 결정하는 것이 Snapshotting이다. `FGameplayEffectAttributeCaptureDefinition` 구조체 하나로 표현된다.

```cpp
// GameplayEffectAttributeCaptureDefinition.h
struct FGameplayEffectAttributeCaptureDefinition
{
    FGameplayAttribute                      AttributeToCapture; // 어떤 Attribute를
    EGameplayEffectAttributeCaptureSource   AttributeSource;    // Source(공격자)? Target(피격자)?
    bool                                    bSnapshot;          // 언제 찍느냐
};
```

| bSnapshot | Source/Target | 캡처 시점 | Duration/Infinite GE 자동 갱신 |
|---|---|---|---|
| `true` | Source | **Spec 생성 시** | No — 고정값 |
| `true` | Target | Spec 적용 시 | No — 고정값 |
| `false` | Source | Spec 적용 시 | Yes |
| `false` | Target | Spec 적용 시 | Yes |

Source + `bSnapshot=true`만 유일하게 **Spec 생성 시점**에 캡처된다.

#### Lyra Execution 사용 패턴 (LyraDamageExecution.cpp)

```cpp
// 1. static 구조체로 캡처 정의 선언 (한 번만 생성)
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;
    FDamageStatics()
    {
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            true);  // bSnapshot=true: Spec 생성 시점 고정
    }
};

// 2. 생성자에서 등록 → GAS가 Spec 생성/적용 시 자동 캡처
ULyraDamageExecution::ULyraDamageExecution()
{
    RelevantAttributesToCapture.Add(DamageStatics().BaseDamageDef);
}

// 3. Execute_Implementation에서 읽기
float BaseDamage = 0.0f;
ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
    DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

OutExecutionOutput.AddOutputModifier(
    FGameplayModifierEvaluatedData(ULyraHealthSet::GetDamageAttribute(),
                                   EGameplayModOp::Additive, BaseDamage * ...));
```

#### 발사체 패턴에서 bSnapshot의 의미

```
발사 시점: Spec 생성 → bSnapshot=true → 공격자 공격력 고정
비행 중:   공격자에게 버프 적용
명중 시점: Spec 적용 → 버프 이전 수치로 데미지 계산
```

`bSnapshot=false`였다면 명중 시점의 공격력이 사용된다. 어느 쪽이 맞는지는 게임 설계 의도에 따라 다르다.
