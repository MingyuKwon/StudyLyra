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

---

## `FGameplayAbilitySpecHandle` — 핸들의 생성과 복제

### 핸들은 서버에서만 생성된다

`FGameplayAbilitySpec` 생성자는 내부에서 `Handle.GenerateNewHandle()`을 호출한다.

```cpp
// GameplayAbilitySpecHandle.cpp
void FGameplayAbilitySpecHandle::GenerateNewHandle()
{
    static int32 GHandle = 1;  // 프로세스 로컬 정적 카운터
    Handle = GHandle++;
}
```

`GiveAbility()`는 서버 전용 함수다. 클라이언트에서 호출하면 즉시 early return한다.

```cpp
if (!IsOwnerActorAuthoritative())
{
    ABILITY_LOG(Error, TEXT("GiveAbility called on ability %s on the client, not allowed!"));
    return FGameplayAbilitySpecHandle();
}
```

따라서 핸들 값은 **서버 프로세스의 정적 카운터**에서만 생성된다. 클라이언트 쪽 카운터는 건드리지 않는다.

### 클라이언트도 같은 핸들 값을 갖는다 — `ActivatableAbilities` 복제

GAS는 `ActivatableAbilities`(`FGameplayAbilitySpecContainer`) 전체를 자동 복제한다.

```cpp
// AbilitySystemComponent.cpp
DOREPLIFETIME_WITH_PARAMS_FAST(UAbilitySystemComponent, ActivatableAbilities, Params);
```

`FGameplayAbilitySpec` 안에 `Handle` 필드가 포함되어 있으므로, 서버가 만든 핸들 값이 복제를 통해 클라이언트에 그대로 전달된다. **서버와 클라이언트의 핸들 값은 항상 동일하다.**

### "핸들을 복제 프로퍼티로 저장해야 한다"의 의미

GAS 내부가 아니라 **게임 코드 레벨** 이야기다.

`ActivatableAbilities`는 GAS가 자동으로 복제하지만, 게임 코드에서 선언한 변수는 그렇지 않다. 클라이언트에서 특정 핸들을 직접 보관하고 `TryActivateAbility(handle)`를 호출하려면, 해당 핸들 변수를 명시적으로 복제해야 한다.

```cpp
// 서버에서 부여 후 핸들을 게임 코드 변수에 저장
UPROPERTY(Replicated)
FGameplayAbilitySpecHandle MyAbilityHandle;

MyAbilityHandle = ASC->GiveAbility(Spec);  // 서버에서만 실행
```

이렇게 하면 클라이언트도 동일한 핸들 값을 받아 `TryActivateAbility(MyAbilityHandle)`를 호출할 수 있다.

핸들을 따로 보관하지 않는 대안도 있다. `ActivatableAbilities`가 복제되어 있으므로 클라이언트에서 클래스나 태그로 검색해 핸들을 꺼낼 수 있다. Lyra의 `ULyraAbilitySet`은 부여한 어빌리티들의 핸들을 `FHandles` 구조체에 묶어 관리하는 방식을 사용한다.
