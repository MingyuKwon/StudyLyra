# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-a-definition"></a>
#### Attribute란 무엇이며, 어떤 값을 표현하는 데 사용해야 하는가?

`Attribute`는 [`FGameplayAttributeData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayAttributeData/index.html) 구조체로 정의되는 float 값이다. 캐릭터의 체력, 캐릭터의 레벨, 포션의 충전 횟수 등 무엇이든 표현할 수 있다. Actor에 속하는 게임플레이 관련 수치라면 Attribute 사용을 고려해야 한다. Attribute는 ASC가 변경 사항을 예측(predict)할 수 있도록 원칙적으로 `GameplayEffect`를 통해서만 수정해야 한다.

Attribute는 `AttributeSet` 안에 정의되고 소속된다. AttributeSet은 복제 대상으로 표시된 Attribute의 복제를 담당한다. Attribute를 정의하는 방법은 `AttributeSet` 섹션을 참고한다.

**팁:** 에디터의 Attribute 목록에 표시하고 싶지 않은 Attribute는 `Meta = (HideInDetailsView)` 프로퍼티 지정자를 사용한다.

---

### Attribute를 직접 수정하지 않고 반드시 GE를 통해야 하는 이유는?

> PredictionKey 동작 원리 전체: [`network_prediction/01_prediction_key.md`](../network_prediction/01_prediction_key.md)

GAS는 클라이언트가 서버 확인 전에 먼저 GE를 적용하고, `FPredictionKey`로 변경을 추적한다. 서버가 거부하면 엔진이 해당 Key에 묶인 GE를 자동 롤백한다.

**왜 GE를 거치지 않으면 예측이 불가능한가**

Attribute를 직접 수정하면 PredictionKey가 없다.

```cpp
// 이렇게 하면 변경 기록이 없음
AttributeSet->Stamina = AttributeSet->Stamina - 10;
// → 서버가 거부해도 롤백할 방법이 없음
```

GE를 거쳐야 변경이 PredictionKey에 묶이고, 거부 시 엔진이 해당 키로 적용된 것들을 찾아 자동 롤백한다.
직접 수정은 메모리 값 덮어쓰기라 추적 자체가 불가능하다.

**한 줄 요약**: GE는 Attribute 변경에 PredictionKey를 붙여 추적 가능하게 만드는 장치이고, 그게 없으면 롤백 메커니즘이 작동하지 않는다.

### FGameplayAttributeData 구조와 ATTRIBUTE_ACCESSORS 매크로는 어떻게 연결되는가?

`FGameplayAttributeData`의 내부 구조와 접근자 매크로는 [`02_base_current_value.md`](02_base_current_value.md)에서 다룬다.
