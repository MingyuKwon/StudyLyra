# Attribute 정의

> **GASDoc**: 4.3.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-a-definition"></a>
#### 4.3.1 Attribute 정의

`Attribute`는 [`FGameplayAttributeData`](https://docs.unrealengine.com/en-US/API/Plugins/GameplayAbilities/FGameplayAttributeData/index.html) 구조체로 정의되는 float 값이다. 캐릭터의 체력, 캐릭터의 레벨, 포션의 충전 횟수 등 무엇이든 표현할 수 있다. Actor에 속하는 게임플레이 관련 수치라면 Attribute 사용을 고려해야 한다. Attribute는 ASC가 변경 사항을 [예측(predict)](#concepts-p)할 수 있도록 원칙적으로 [`GameplayEffect`](#concepts-ge)를 통해서만 수정해야 한다.

Attribute는 [`AttributeSet`](#concepts-as) 안에 정의되고 소속된다. AttributeSet은 복제 대상으로 표시된 Attribute의 복제를 담당한다. Attribute를 정의하는 방법은 [`AttributeSet`](#concepts-as) 섹션을 참고한다.

**팁:** 에디터의 Attribute 목록에 표시하고 싶지 않은 Attribute는 `Meta = (HideInDetailsView)` 프로퍼티 지정자를 사용한다.

---

## 내 분석

### 왜 Attribute는 GE를 통해서만 수정해야 하는가 — 예측과 롤백

**예측(Prediction)이란 — 클라이언트 선행 실행**

멀티플레이어에서 서버 응답을 기다리면 입력 지연이 체감된다.
GAS는 클라이언트가 서버 확인 전에 먼저 결과를 적용하고, 나중에 서버와 맞추는 방식을 쓴다.

```
클라이언트: 점프 입력
  → 서버 응답 기다리지 않고 즉시 GA 발동
  → GE로 Stamina -10 즉시 적용 (예측)
  → 동시에 서버에 RPC 전송

서버: RPC 수신
  → 유효하면 동일하게 GE 적용
  → 클라이언트에 결과 전파

클라이언트: 서버 확인 수신
  → 맞으면 그대로 유지
  → 틀리면 롤백
```

**PredictionKey — 예측 추적 단위**

클라이언트가 예측 행동을 할 때마다 `FPredictionKey`(고유 ID)를 발급한다.
GE를 적용할 때 이 키를 함께 담는다.

```cpp
FActiveGameplayEffect {
    FGameplayEffectSpec Spec;
    FPredictionKey PredictionKey;  // "이 GE는 이 예측에서 온 것"
}
```

서버가 같은 GE를 복제해 보내올 때 PredictionKey를 대조한다.
- **일치**: 서버가 예측을 확인 → 클라이언트 측 예측 GE 그대로 유지
- **거부**: `NewRejectedDelegate` 발동 → 해당 PredictionKey에 속한 GE 전부 롤백

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

### FGameplayAttributeData — 두 값으로 나눈 이유

구조체 자체는 단순하다.

```cpp
struct FGameplayAttributeData
{
protected:
    float BaseValue;    // 영구적인 기저값
    float CurrentValue; // 버프/디버프가 반영된 현재값
};
```

**BaseValue** — `Instant` GE가 적용될 때 바뀐다. GE가 제거돼도 남는다.

**CurrentValue** — `Duration` / `Infinite` GE의 Modifier가 Aggregator를 통해 계산되어 반영된다.
GE가 제거되면 BaseValue 기준으로 재계산되어 복귀한다.
게임 코드에서 실제로 읽는 값은 CurrentValue다.

```
BaseValue = 100
+ Duration GE "체력 +20" 적용 → CurrentValue = 120
GE 제거              → CurrentValue = 100 (BaseValue로 복귀)
```

| | 언제 바뀌나 | 누가 쓰나 |
|---|---|---|
| `BaseValue` | Instant GE, `SetXxx()` 호출 | GE 계산의 기준점 |
| `CurrentValue` | Aggregator 재계산 (Duration/Infinite GE) | 게임 코드에서 실제로 읽는 값 |

**`ATTRIBUTE_ACCESSORS` 매크로가 생성하는 4개 함수**

```cpp
ATTRIBUTE_ACCESSORS(ULyraHealthSet, Health)

static FGameplayAttribute GetHealthAttribute(); // FProperty 포인터 반환 (GE Modifier 지정용)
float GetHealth() const;                        // CurrentValue 읽기
void SetHealth(float NewVal);                   // ASC->SetNumericAttributeBase() 경유 (BaseValue 변경)
void InitHealth(float NewVal);                  // BaseValue + CurrentValue 동시 세팅 (초기화 전용)
```

`SetHealth`가 직접 값을 쓰지 않고 ASC를 경유하는 이유는 Aggregator 재계산과 델리게이트 발동을 보장하기 위해서다.
`InitHealth`만 직접 양쪽을 세팅한다 — 초기화 시점에는 Aggregator가 없으므로 예외다.
