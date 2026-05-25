# UInputAction

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputAction.h`

---

## 무엇인가

물리 키와 분리된 **추상 행동 단위**다. `IA_Jump`, `IA_Move`, `IA_Fire`처럼 "뭘 하는가"만 정의하는 DataAsset이다.

어떤 키가 이 Action을 발동하는지는 `UInputMappingContext`가 결정한다. Action 자체는 키를 모른다.

레거시 시스템의 "Action Name" / "Axis Name" 문자열을 대체한다.

---

## 클래스 위치

```
UObject → UDataAsset → UInputAction
```

에디터에서 우클릭 → Input → Input Action으로 생성하는 에셋 파일이다.

---

## 핵심 프로퍼티

### ValueType — 이 Action이 반환하는 값의 타입

```cpp
EInputActionValueType ValueType = EInputActionValueType::Boolean;
```

| 값 | 에디터 표시 | 반환 타입 | 사용 예 |
|---|---|---|---|
| `Boolean` | Digital (bool) | bool | 점프, 공격 |
| `Axis1D` | Axis1D (float) | float | 트리거 압력 |
| `Axis2D` | Axis2D (Vector2D) | FVector2D | 이동, 시점 |
| `Axis3D` | Axis3D (Vector) | FVector | 6DOF 입력 |

**중요**: IMC에서 키를 매핑할 때 이 타입과 맞지 않는 키를 연결하면 에디터 경고가 발생한다. Modifier(SwizzleAxis 등)로 타입을 변환해서 맞춰야 한다.

---

### AccumulationBehavior — 복수 키 매핑 시 값 결합 방식

```cpp
EInputActionAccumulationBehavior AccumulationBehavior = TakeHighestAbsoluteValue;
```

하나의 `UInputAction`에 여러 키를 매핑할 수 있다. 예를 들어 `IA_Move`에 WASD 4개와 게임패드 스틱이 모두 연결되어 있을 때, 이 키들을 **동시에 누르면** 최종 값을 어떻게 결정할지 정하는 것이 이 프로퍼티다.

**TakeHighestAbsoluteValue (기본)** — 컴포넌트별로 절댓값이 더 큰 쪽 채택

```
W키:    (0,  1)   (SwizzleAxis 후)
스틱:   (0, 0.7)

결과:   (0,  1)   ← Y축은 W키(1.0)가 스틱(0.7)보다 크므로 W키 값 사용
```

키보드와 스틱을 동시에 사용할 때 더 강한 입력이 우선하는 자연스러운 동작이다.

**Cumulative** — 모든 값을 합산

```
W키:  (0,  1)
S키:  (0, -1)

결과: (0,  0)   ← W+S 동시 입력 시 상쇄되어 멈춤
```

WASD에서 반대 방향 키를 동시에 누르면 서로 상쇄되길 원할 때 쓴다. 기본값(`TakeHighestAbsoluteValue`)으로는 이 상쇄가 보장되지 않는다.

---

### Triggers — Action 레벨 발화 조건

```cpp
TArray<TObjectPtr<UInputTrigger>> Triggers;
```

IMC의 키 매핑에도 Trigger를 붙일 수 있고, IA 에셋에도 붙일 수 있다. 두 레벨의 Trigger가 모두 통과해야 Action이 발동된다(Mapping 레벨이 먼저, Action 레벨이 나중).

Action 레벨 Trigger는 **키 종류와 무관하게 공통으로 적용**하고 싶은 조건에 쓴다. 예: 어떤 키로 발동하든 항상 Hold가 필요한 Action이라면 IA 에셋에 Hold Trigger를 붙인다.

---

### Modifiers — Action 레벨 값 변환

```cpp
TArray<TObjectPtr<UInputModifier>> Modifiers;
```

Mapping 레벨 Modifier 이후에 추가로 적용되는 변환. 모든 키 매핑의 누적된 최종 값에 한 번 적용된다.

---

### 기타 프로퍼티

```cpp
bool bTriggerWhenPaused = false;   // 게임 일시정지 중에도 발동. 메뉴 Action에 필요
bool bConsumeInput = true;         // true이면 하위 IMC 우선순위의 같은 Action 바인딩 차단
bool bConsumesActionAndAxisMappings = false;  // true이면 레거시 키 매핑도 차단
bool bReserveAllMappings = false;  // 상위 IMC가 자동으로 이 Action 매핑을 덮어쓰는 것 방지
```

---

## FInputActionInstance — 런타임 인스턴스

`UInputAction`은 에셋이라 값이 없다. 런타임 값과 상태는 `UEnhancedPlayerInput`이 `ActionInstanceData` 맵에 Action당 하나씩 `FInputActionInstance`를 생성해서 관리한다.

```cpp
struct FInputActionInstance
{
    FInputActionValue Value;         // 이번 틱의 입력값
    ETriggerEvent TriggerEvent;      // 이번 틱 이벤트 종류
    float ElapsedProcessedTime;      // Trigger가 None이 아닌 상태로 지속된 시간
    float ElapsedTriggeredTime;      // Triggered 상태 지속 시간
    double LastTriggeredWorldTime;   // 마지막으로 Triggered된 World 시각
};
```

`BindAction`의 InstanceSignature 오버로드를 쓰면 콜백에서 이 인스턴스 전체에 접근할 수 있다.

---

## 요약

```
UInputAction = 행동의 "설계도"
  ValueType        : 어떤 타입의 값을 반환하는가
  AccumulationBehavior : 복수 키 값을 어떻게 합산하는가
  Triggers[]       : 공통 발화 조건
  Modifiers[]      : 공통 값 변환
  
키 연결은 UInputMappingContext가 담당.
런타임 값·상태는 UEnhancedPlayerInput의 ActionInstanceData가 담당.
```
