# 태그 변화 감지

> **GASDoc**: 4.2.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-gt-change"></a>
### 4.2.1 GameplayTag 변화에 응답하기

ASC는 GameplayTag가 추가되거나 제거될 때 발동하는 델리게이트를 제공한다. `EGameplayTagEventType`을 통해 GameplayTag가 추가/제거될 때만 발동할지, 아니면 GameplayTag의 `TagMapCount`가 변경될 때마다 발동할지를 지정할 수 있다.

```c++
AbilitySystemComponent->RegisterGameplayTagEvent(FGameplayTag::RequestGameplayTag(FName("State.Debuff.Stun")), EGameplayTagEventType::NewOrRemoved).AddUObject(this, &AGDPlayerState::StunTagChanged);
```

콜백 함수는 GameplayTag와 새로운 `TagCount`를 파라미터로 받는다.

```c++
virtual void StunTagChanged(const FGameplayTag CallbackTag, int32 NewCount);
```

**[⬆ Back to Top](#table-of-contents)**

---

## 내 분석
