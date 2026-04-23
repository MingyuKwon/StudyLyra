# Prediction Key

> **GASDoc**: 4.10.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-p"></a>
### 4.10 Prediction

GAS는 클라이언트 측 예측(client-side prediction)을 기본 지원하지만, 모든 것을 예측하지는 않는다. GAS에서의 클라이언트 측 예측이란, 클라이언트가 서버의 허가를 기다리지 않고 `GameplayAbility`를 활성화하고 `GameplayEffect`를 적용할 수 있음을 의미한다. 클라이언트는 서버가 이를 허가할 것이라고 "예측"하고, `GameplayEffect`가 적용될 타겟도 예측한다. 서버는 클라이언트가 활성화한 뒤 네트워크 레이턴시 시간 이후에 `GameplayAbility`를 실행하고, 클라이언트의 예측이 맞았는지 여부를 알려준다. 예측이 틀렸다면 클라이언트는 "오예측(misprediction)"으로 인한 변경사항을 "롤백"하여 서버와 동기화한다.

GAS 관련 예측의 공식적인 참고 자료는 플러그인 소스 코드의 `GameplayPrediction.h`다.

Epic의 관점은 "빠져나갈 수 있는" 것만 예측하는 것이다. 예를 들어, Paragon과 Fortnite는 데미지를 예측하지 않는다. 이는 어차피 예측할 수 없는 [`ExecutionCalculations`](#concepts-ge-ec)를 데미지에 사용하기 때문일 가능성이 높다. 물론 데미지 같은 것을 예측하려고 시도하는 것은 얼마든지 가능하다.

> ... 우리는 "모든 것을 예측하자: 매끄럽게, 자동으로"라는 해결책에 전면적으로 동의하지 않습니다. 우리는 여전히 플레이어 예측은 최소한으로 유지하는 것이 최선이라고 생각합니다 (즉, 빠져나갈 수 있는 최소한의 것만 예측하세요).

*새로운 [Network Prediction Plugin](#concepts-p-npp)에 관한 Epic의 Dave Ratti 코멘트*

**예측되는 것:**
> * Ability 활성화
> * Triggered 이벤트
> * GameplayEffect 적용:
>    * Attribute 수정 (예외: Execution은 현재 예측되지 않으며, Attribute Modifier만 예측됨)
>    * GameplayTag 수정
> * Gameplay Cue 이벤트 (예측 GameplayEffect 내에서도, 단독으로도)
> * 몽타주
> * 이동 (UE의 UCharacterMovement에 내장)

**예측되지 않는 것:**
> * GameplayEffect 제거
> * GameplayEffect 주기적 효과(도트 틱)

*`GameplayPrediction.h` 발췌*

`GameplayEffect` 적용은 예측할 수 있지만, 제거는 예측할 수 없다. 이 한계를 우회하는 방법 중 하나는 `GameplayEffect`를 제거하고 싶을 때 역효과(inverse effect)를 예측 적용하는 것이다. 예컨대 이동 속도 40% 감소를 예측했다면, 이동 속도 40% 버프를 예측 적용하여 예측적으로 제거할 수 있다. 그런 다음 두 `GameplayEffect` 모두를 동시에 제거한다. 이 방법이 모든 상황에 적합한 것은 아니며, `GameplayEffect` 제거 예측에 대한 지원이 여전히 필요한 상황이다. Epic의 Dave Ratti는 [GAS의 미래 버전](https://epicgames.ent.box.com/s/m1egifkxv3he3u3xezb9hzbgroxyhx89)에서 이를 추가하고 싶다고 밝힌 바 있다.

`GameplayEffect` 제거를 예측할 수 없기 때문에, `GameplayAbility` 쿨다운을 완전히 예측할 수 없으며, 역 `GameplayEffect` 우회책도 존재하지 않는다. 서버에서 복제된 `Cooldown GE`는 클라이언트에 존재하며, 이를 우회하려는 시도(`Minimal` 복제 모드 등)는 서버에서 거부된다. 즉, 레이턴시가 높은 클라이언트는 서버에 쿨다운을 알리고 서버의 `Cooldown GE`가 제거되는 시간이 더 오래 걸린다. 이 때문에 레이턴시가 높은 플레이어는 낮은 플레이어에 비해 발사 속도가 느리게 된다. Fortnite는 `Cooldown GE` 대신 커스텀 기록 방식을 사용하여 이 문제를 회피한다.

데미지 예측에 대해서 개인적으로 권장하지 않는다. 비록 GAS를 처음 시작할 때 가장 먼저 시도하는 것 중 하나이지만, 사망 예측은 특히 권장하지 않는다. 데미지를 예측하는 것은 까다로우며, 오예측이 발생하면 적의 체력이 다시 올라가는 것을 플레이어가 보게 된다. 사망 예측의 오예측은 더욱 어색하고 답답한 경험을 초래한다. 예컨대 캐릭터가 죽어 래그돌이 시작되었다가 서버가 수정하면서 래그돌이 멈추고 다시 공격해오는 상황이 발생할 수 있다.

**참고:** `Attribute`를 변경하는 `Instant` `GameplayEffect`(예: `Cost GE`)는 자기 자신에 대해 매끄럽게 예측할 수 있지만, 다른 캐릭터에 대한 `Instant` `Attribute` 변경 예측은 잠깐의 이상 현상 또는 "깜빡임(blip)"을 유발할 수 있다. 예측된 `Instant` `GameplayEffect`는 오예측 시 롤백이 가능하도록 실제로는 `Infinite` `GameplayEffect`처럼 처리된다. 서버의 `GameplayEffect`가 적용되면 잠깐 동안 동일한 `GameplayEffect`가 두 개 존재하여 `Modifier`가 두 번 적용되거나 전혀 적용되지 않는 상황이 생길 수 있다. 결국은 수정되지만 때로는 플레이어에게 깜빡임이 눈에 띌 수 있다.

GAS의 예측 구현이 해결하려는 문제들:
> 1. "이걸 할 수 있나?" 예측을 위한 기본 프로토콜.
> 2. "실행 취소" 예측이 실패했을 때 부작용을 되돌리는 방법.
> 3. "재실행" 로컬에서 예측했지만 서버에서도 복제되는 부작용의 중복 재생을 피하는 방법.
> 4. "완결성" 모든 부작용을 실제로 예측했는지 확인하는 방법.
> 5. "의존성" 의존적 예측과 예측 이벤트 체인을 관리하는 방법.
> 6. "오버라이드" 그렇지 않으면 서버가 소유/복제하는 상태를 예측적으로 오버라이드하는 방법.

*`GameplayPrediction.h` 발췌*

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-p-key"></a>
#### 4.10.1 Prediction Key

GAS의 예측은 **Prediction Key** 개념을 기반으로 동작한다. Prediction Key는 클라이언트가 `GameplayAbility`를 활성화할 때 생성하는 정수 식별자다.

* 클라이언트는 `GameplayAbility`를 활성화할 때 Prediction Key를 생성한다. 이것이 `Activation Prediction Key`다.
* 클라이언트는 `CallServerTryActivateAbility()`를 통해 이 Prediction Key를 서버에 전송한다.
* 클라이언트는 Prediction Key가 유효한 동안 적용하는 모든 `GameplayEffect`에 이 키를 추가한다.
* Prediction Key가 스코프를 벗어나면, 같은 `GameplayAbility` 내에서의 추가 예측 효과는 새로운 [Scoped Prediction Window](#concepts-p-windows)가 필요하다.


* 서버는 클라이언트에서 Prediction Key를 받는다.
* 서버는 자신이 적용하는 모든 `GameplayEffect`에 이 Prediction Key를 추가한다.
* 서버는 Prediction Key를 클라이언트에게 다시 복제한다.


* 클라이언트는 적용에 사용된 Prediction Key와 함께 서버로부터 복제된 `GameplayEffect`를 수신한다. 복제된 `GameplayEffect` 중 클라이언트가 같은 Prediction Key로 적용한 `GameplayEffect`와 일치하는 것이 있으면 예측이 맞은 것이다. 클라이언트가 예측한 것을 제거할 때까지 타겟에 `GameplayEffect`의 복사본이 일시적으로 두 개 존재하게 된다.
* 클라이언트는 서버로부터 Prediction Key를 돌려받는다. 이것이 `Replicated Prediction Key`다. 이 Prediction Key는 이제 stale(만료) 처리된다.
* 클라이언트는 이제 stale 상태가 된 Replicated Prediction Key로 생성한 **모든** `GameplayEffect`를 제거한다. 서버가 복제한 `GameplayEffect`는 유지된다. 클라이언트가 추가했지만 서버로부터 대응하는 복제본을 받지 못한 `GameplayEffect`는 오예측(misprediction)으로 처리된다.

Prediction Key는 `Activation`을 시작으로 `GameplayAbility` 내의 원자적 명령 묶음 "window" 동안만 유효함이 보장된다. 사실상 단 하나의 프레임 동안만 유효하다고 생각하면 된다. latent action `AbilityTask`의 콜백에서는 더 이상 유효한 Prediction Key가 없다. 단, `AbilityTask`에 새로운 [Scoped Prediction Window](#concepts-p-windows)를 생성하는 내장 Synch Point가 있는 경우는 예외다.

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
