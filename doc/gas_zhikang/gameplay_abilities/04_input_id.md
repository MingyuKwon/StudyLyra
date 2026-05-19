# Input ID 방식과 입력 관련 AbilityTask

> **출처**: Zhi Kang Shao — GAS Best Practices for Setup

---

## 어빌리티를 입력으로 트리거하는 두 가지 방식

### 수동 방식 (Manually)

UE 입력 이벤트를 직접 수신하고 ASC의 `TryActivateAbility` 계열 함수를 직접 호출한다.
복잡한 프로젝트에 적합하지만, 입력 관련 AbilityTask(`WaitInputPress` 등)를 기본으로 지원하지 않는다.

Lyra가 이 방식을 사용하며, Enhanced Input의 유연성을 살리면서 입력 관련 AbilityTask도 별도 게임 코드로 지원한다.

### Input ID 방식 (Via Input ID)

어빌리티를 매핑 가능한 입력에 직접 연결한다.
유연성이 낮지만 소규모 프로젝트에 유용하며, 입력 관련 AbilityTask를 기본 지원한다.

> **참고**  
> Epic의 출시작에서는 Input ID 방식을 사용하지 않는다. 단일 열거형 기반 목록이 대규모 프로젝트에 비유연하기 때문이다.

---

## Input ID 방식 설정 단계

플레이어가 점프(Jump), 근접 공격(Melee), 앉기(Crouch) 세 가지 행동을 갖는 게임을 예시로 한다.

**Step 1**: 해당 항목을 가진 열거형(C++ 또는 블루프린트) 생성

```cpp
UENUM(BlueprintType)
enum class EMyEnum : uint8
{
    Jump,
    Dash,
    Attack,
    TargetedAbility
};
```

**Step 2**: 프로젝트 설정에서 열거형 항목과 동일한 이름의 (레거시 입력) 액션 매핑 정의

**Step 3**: 입력 컴포넌트 설정 시 `BindAbilityActivationToInputComponent()` 호출
확인/취소 입력을 위한 추가 액션 매핑 이름 2개를 함께 지정할 수 있다.

```cpp
void AMyCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
    const FTopLevelAssetPath EnumName("/Script/MyProject.EMyEnum");
    FGameplayAbilityInputBinds Binds("ConfirmTargeting", "CancelTargeting", EnumName);
    LabAbilitySystemComp->BindAbilityActivationToInputComponent(PlayerInputComponent, Binds);
}
```

**Step 4**: 어빌리티 부여 시 열거형 값으로 변환한 Input ID를 함께 제공

설정 완료 후, 액션 매핑에 바인딩된 키를 누르면 해당 Input ID를 가진 부여된 어빌리티가 활성화된다.

---

## WaitInputPress / WaitInputRelease / WaitForConfirm / WaitForCancel

이 AbilityTask들은 기본적으로 **Input ID 방식 + `BindAbilityActivationToInputComponent` 호출** 조합에서만 동작한다.

- `WaitInputPress` / `WaitInputRelease`: 어빌리티를 활성화한 키를 다시 누르거나 처음 놓을 때까지 대기
- `WaitForConfirm` / `WaitForCancel`: 확인·취소 액션 매핑에 바인딩된 키 입력을 대기. 매핑 이름은 `BindAbilityActivationToInputComponent` 호출 시 지정한 이름을 사용

### Lyra의 접근 방식

Lyra는 Input ID 방식을 사용하지 않으면서도 이 AbilityTask들을 지원한다.
Enhanced Input의 유연성을 유지하면서 `WaitInputPress` / `WaitInputRelease`를 게임 코드 내에서 직접 지원하는 커스텀 솔루션을 구현했다.
