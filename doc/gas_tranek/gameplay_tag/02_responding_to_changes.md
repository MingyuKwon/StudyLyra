# 태그 변화 감지

> **GASDoc**: 4.2.1 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-gt-change"></a>
### GameplayTag가 추가/제거될 때 이벤트를 감지하려면 어떻게 해야 하는가?

ASC의 `RegisterGameplayTagEvent()`로 델리게이트를 등록한다. `EGameplayTagEventType`으로 발동 조건을 선택한다.

| 이벤트 타입 | 발동 시점 |
|---|---|
| `NewOrRemoved` | 태그가 처음 추가되거나 완전히 제거될 때 |
| `AnyCountChange` | `TagMapCount`가 변경될 때마다 |

```c++
AbilitySystemComponent->RegisterGameplayTagEvent(
    FGameplayTag::RequestGameplayTag(FName("State.Debuff.Stun")),
    EGameplayTagEventType::NewOrRemoved
).AddUObject(this, &AGDPlayerState::StunTagChanged);
```

콜백 함수는 태그와 새로운 `TagCount`를 파라미터로 받는다.

```c++
virtual void StunTagChanged(const FGameplayTag CallbackTag, int32 NewCount);
```

---
