# 어빌리티 활성화 방법

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 어빌리티를 활성화하는 6가지 방법

모든 어빌리티는 **서버에서 부여**해야 한다. 활성화 방법은 편의성과 제어 수준에 따라 크게 6가지로 나뉜다.

### 1. 즉시 (Immediately)

서버와 스탠드얼론 클라이언트는 `GiveAbilityAndActivateOnce`를 호출해 어빌리티 부여와 즉시 활성화를 한 번에 처리할 수 있다.

### 2. 클래스로 (Via Class)

클라이언트는 `TryActivateAbilityByClass`에 어빌리티 클래스를 전달해 호출한다.
ASC가 정확히 그 클래스(서브클래스 불가)의 어빌리티를 보유하고 있으면 활성화를 시도한다.
플레이어가 가진 특정 어빌리티를 정확히 알고 있을 때 편리하지만, 동적인 상황에서는 유용성이 떨어진다.

### 3. 태그로 (Via Tag)

어빌리티에 `AssetTags`(DefaultAbilityTags라고도 함)를 설정할 수 있다.
클라이언트는 `TryActivateAbilityByTag`에 태그 집합을 전달한다.
해당 태그를 모두 AssetTag로 가진 부여된 어빌리티가 활성화를 시도한다.

"점프", "근접 공격"처럼 플레이어 행동 목록이 미리 정해져 있고 런타임에 어빌리티 클래스가 교체될 수 있는 경우에 유용하다.

### 4. 핸들로 (Via Handle)

어빌리티를 부여하면 고유한 핸들이 반환된다.
`TryActivateAbility`에 이 핸들을 전달해 특정 어빌리티를 정확히 활성화할 수 있다.
네트워크 프로젝트에서는 핸들을 복제 프로퍼티로 저장해야 한다.

### 5. Input ID로 (Via Input ID)

어빌리티 부여 시 InputID를 함께 제공하고 `BindAbilityActivationToInputComponent`를 호출한 경우,
해당 입력에 매핑된 버튼 입력이 어빌리티를 활성화한다.
간단한 케이스에서 보일러플레이트 코드를 줄이는 데 편리하지만,
고정 열거형을 사용하고 래핑 코드를 추가할 수 없어 유연성이 떨어진다.

자세한 내용은 [04 Input ID](04_input_id.md) 참고.

### 6. Ability Trigger로 (Via Ability Trigger)

소유 Actor에 특정 GameplayTag 또는 "이벤트"(태그 + 페이로드)가 전달될 때 어빌리티가 활성화되도록 설정할 수 있다.
어빌리티 블루프린트의 `AbilityTriggers` 프로퍼티에서 구성한다.
ASC에 부여되어 있고 이미 활성화되지 않은 어빌리티라면 이 트리거에 반응한다.

---

> **참고**  
> 이 함수들은 모두 활성화를 "시도"한다. 비용·쿨다운·태그 및 기타 커스텀 조건은 여전히 검사된다.

---

## 네트워크 게임에서의 어빌리티 활성화

위의 모든 방법이 **완전히 동일하게 동작한다.** GAS가 내부적으로 처리한다.

어빌리티의 `Net Execution Policy`에 따라 필요하고 허용된 경우 서버로 자동 라우팅된다.
핸들로 활성화하는 방식을 사용한다면 핸들을 복제 프로퍼티로 저장해야 한다.

> 핸들(`FGameplayAbilitySpecHandle`)은 서버에서만 생성된다(`GiveAbility()`는 서버 전용). 다만 GAS가 `ActivatableAbilities` 전체를 자동 복제하므로 핸들 값 자체는 클라이언트와 서버가 항상 동일하다. "복제 프로퍼티로 저장"은 GAS 내부가 아닌 게임 코드 이야기다 — `ActivatableAbilities`는 GAS가 복제해 주지만, 게임 코드 변수(`MyAbilityHandle`)는 그렇지 않으므로 클라이언트에서 직접 참조해야 한다면 `UPROPERTY(Replicated)`로 따로 복제해야 한다.
