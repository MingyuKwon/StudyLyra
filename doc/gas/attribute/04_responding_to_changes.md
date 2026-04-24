# Attribute 변화 감지

> **GASDoc**: 4.3.4 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-changes"></a>
#### 4.3.4 Attribute 변화에 응답하기

Attribute가 변경될 때 UI나 다른 게임플레이 요소를 업데이트하려면 `UAbilitySystemComponent::GetGameplayAttributeValueChangeDelegate(FGameplayAttribute Attribute)`를 사용한다. 이 함수는 Attribute가 변경될 때마다 자동으로 호출되는 델리게이트를 반환하며, 바인딩할 수 있다. 델리게이트는 `NewValue`, `OldValue`, `FGameplayEffectModCallbackData`를 담은 `FOnAttributeChangeData` 파라미터를 제공한다. > **참고**  
> `FGameplayEffectModCallbackData`는 서버에서만 설정된다.

```c++
AbilitySystemComponent->GetGameplayAttributeValueChangeDelegate(AttributeSetBase->GetHealthAttribute()).AddUObject(this, &AGDPlayerState::HealthChanged);
```

```c++
virtual void HealthChanged(const FOnAttributeChangeData& Data);
```

샘플 프로젝트는 `GDPlayerState`에서 Attribute 값 변경 델리게이트에 바인딩하여 HUD를 업데이트하고, 체력이 0이 됐을 때 플레이어 사망을 처리한다.

샘플 프로젝트에는 이를 `AsyncTask`로 래핑한 커스텀 블루프린트 노드도 포함되어 있다. `UI_HUD` UMG 위젯에서 체력, 마나, 스태미나 값을 업데이트하는 데 사용된다. 이 `AsyncTask`는 `EndTask()`를 수동으로 호출할 때까지 계속 살아있으며, UMG 위젯의 `Destruct` 이벤트에서 이를 처리한다. `AsyncTaskAttributeChanged.h/cpp`를 참고한다.

![Listen for Attribute Change BP Node](https://github.com/tranek/GASDocumentation/raw/master/Images/attributechange.png)

---

## 내 분석
