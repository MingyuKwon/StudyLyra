# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-definition"></a>
#### Attribute란 무엇이며, 어떤 값을 표현하는 데 사용해야 하는가?

`FGameplayAttributeData` 구조체로 정의되는 float 값이다. 체력, 캐릭터 레벨, 포션 충전 횟수처럼 Actor에 속하는 게임플레이 관련 수치에 사용한다.

Attribute는 `AttributeSet` 안에 정의되며, AttributeSet이 복제 대상 Attribute의 복제를 담당한다. ASC가 변경을 예측(predict)할 수 있도록 원칙적으로 `GameplayEffect`를 통해서만 수정해야 한다.

**팁:** 에디터 Attribute 목록에서 숨기려면 `Meta = (HideInDetailsView)` 프로퍼티 지정자를 사용한다.

---

### Attribute를 직접 수정하지 않고 반드시 GE를 통해야 하는 이유는?

> PredictionKey 동작 원리 전체: [`network_prediction/01_prediction_key.md`](../network_prediction/01_prediction_key.md)

GAS 예측 시스템은 `FPredictionKey`로 변경을 추적하고, 서버가 거부하면 해당 Key에 묶인 변경을 자동 롤백한다. GE를 거쳐야 변경이 PredictionKey에 묶인다.

```cpp
// 직접 수정하면 PredictionKey가 없어 롤백 불가능
AttributeSet->Stamina = AttributeSet->Stamina - 10;
```

직접 수정은 메모리 값 덮어쓰기라 추적 자체가 불가능하다. GE는 Attribute 변경에 PredictionKey를 붙여 추적 가능하게 만드는 장치다.

### FGameplayAttributeData 구조와 ATTRIBUTE_ACCESSORS 매크로는 어떻게 연결되는가?

`FGameplayAttributeData`의 내부 구조와 접근자 매크로는 [`02_base_current_value.md`](02_base_current_value.md)에서 다룬다.
