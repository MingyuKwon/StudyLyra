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

**[⬆ Back to Top](#table-of-contents)**

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

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
