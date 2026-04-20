# GameplayMessageRouter 플러그인

> 소스: `Plugins/GameplayMessageRouter/Source/GameplayMessageRuntime/`  
> 핵심 파일: `GameplayMessageSubsystem.h/cpp`, `GameplayMessageTypes2.h`

---

## 한 줄 정의

**발신자와 수신자가 서로를 모르면서 메시지를 주고받는 pub/sub 메시지 버스.**  
GameplayTag를 채널로, 임의의 `USTRUCT`를 페이로드로 사용한다.

---

## 왜 필요한가

데미지 발생 시 HUD, 킬피드, 사운드, 통계 시스템 등 여러 곳이 알아야 한다.  
직접 참조 방식은 발신자가 모든 수신자를 알아야 한다:

```cpp
// 나쁜 방식
HUDRef->OnDamage(Amount);
KillFeedRef->OnDamage(Amount);
SoundManagerRef->OnDamage(Amount);
```

`UGameplayMessageSubsystem`을 쓰면 발신자와 수신자가 완전히 분리된다:

```cpp
// 발신 측 — 수신자를 전혀 모름
UGameplayMessageSubsystem::Get(this).BroadcastMessage(TAG_Lyra_Damage_Message, Msg);

// 수신 측 — 발신자를 전혀 모름
Subsystem.RegisterListener(TAG_Lyra_Damage_Message, this, &UMyHUD::OnDamage);
```

---

## 내부 구조

```
UGameplayMessageSubsystem  (UGameInstanceSubsystem — 게임 인스턴스 수명)
    │
    └── TMap<FGameplayTag, FChannelListenerList> ListenerMap
              │
              └── FChannelListenerList
                    ├── TArray<FGameplayMessageListenerData> Listeners
                    │       ├── TFunction<void(Tag, UScriptStruct*, void*)> ReceivedCallback
                    │       ├── int32 HandleID
                    │       ├── EGameplayMessageMatch MatchType
                    │       └── TWeakObjectPtr<UScriptStruct> ListenerStructType
                    └── int32 HandleID  ← 자동 증가 ID 발급기
```

---

## BroadcastMessage 흐름

```cpp
// 외부 진입점 (템플릿, 타입 안전)
Subsystem.BroadcastMessage(TAG_Lyra_Damage_Message, MyDamageStruct);
    │
    ▼
BroadcastMessageInternal(Channel, StructType, &MessageBytes)
    │
    ├── Tag = "Lyra.Damage.Message"  →  ExactMatch + PartialMatch 리스너 호출
    ├── Tag = "Lyra.Damage"          →  PartialMatch 리스너만 호출
    └── Tag = "Lyra"                 →  PartialMatch 리스너만 호출
```

브로드캐스트 태그에서 부모 태그 방향으로 올라가며 순회한다.  
`PartialMatch`로 등록하면 하위 태그 전체를 한 번에 수신할 수 있다.

**이터레이션 안전 처리** — 콜백 도중 Unregister가 발생해도 안전하도록 리스너 배열을 복사 후 순회한다:

```cpp
TArray<FGameplayMessageListenerData> ListenerArray(pList->Listeners);  // 복사본으로 순회
```

---

## RegisterListener 3가지 오버로드

```cpp
// 1. 람다
Handle = Subsystem.RegisterListener<FLyraDamageMessage>(
    TAG_Lyra_Damage_Message,
    [](FGameplayTag Channel, const FLyraDamageMessage& Msg) { ... });

// 2. 멤버 함수 + 자동 WeakPtr 보호
Handle = Subsystem.RegisterListener<FLyraDamageMessage>(
    TAG_Lyra_Damage_Message,
    this, &UMyClass::OnDamageMessage);
// → TWeakObjectPtr로 감쌈. 오브젝트 소멸 후 콜백은 조용히 무시됨

// 3. 고급 파라미터 (MatchType 등)
FGameplayMessageListenerParams<FLyraDamageMessage> Params;
Params.MatchType = EGameplayMessageMatch::PartialMatch;
Params.SetMessageReceivedCallback(this, &UMyClass::OnDamageMessage);
Handle = Subsystem.RegisterListener(TAG_Lyra_Damage, Params);
```

---

## EGameplayMessageMatch

| 값 | 동작 |
|----|------|
| `ExactMatch` (기본) | 등록한 태그와 정확히 일치하는 브로드캐스트만 수신 |
| `PartialMatch` | 등록한 태그를 루트로 하는 모든 하위 태그 수신 (`A.B` 등록 → `A.B.C` 브로드캐스트도 수신) |

---

## 핸들 기반 등록 해제

```cpp
FGameplayMessageListenerHandle Handle = Subsystem.RegisterListener(...);

Handle.Unregister();              // 핸들에서 직접
Subsystem.UnregisterListener(Handle);  // 서브시스템에서
```

`FGameplayMessageListenerHandle` 내부: `(TWeakObjectPtr<Subsystem>, FGameplayTag Channel, int32 ID)`  
Subsystem이 먼저 소멸해도 WeakPtr 덕분에 안전하다.

---

## 타입 안전 보장

```cpp
// BroadcastMessageInternal 내부
if (!StructType->IsChildOf(Listener.ListenerStructType.Get()))
{
    UE_LOG(..., Error, TEXT("Struct type mismatch on channel %s ..."));
    // 콜백 건너뜀
}
```

채널이 같아도 구조체 타입이 다르면 에러 로그 후 스킵.  
브로드캐스트 타입이 리스너 타입의 **서브클래스**이면 허용(`IsChildOf`).

---

## Blueprint 지원

```cpp
UFUNCTION(BlueprintCallable, CustomThunk, meta=(CustomStructureParam="Message"))
void K2_BroadcastMessage(FGameplayTag Channel, const int32& Message);
```

`CustomThunk + CustomStructureParam` 조합으로 Blueprint에서 임의 구조체를 핀으로 연결 가능.  
실제 함수 본체는 `checkNoEntry()` — Blueprint VM이 `execK2_BroadcastMessage`를 직접 호출해 스택에서 포인터를 꺼낸다.

---

## Lyra 활용 예시

```cpp
// LyraHealthSet.cpp — PostGameplayEffectExecute
FLyraVerbMessage Message;
Message.Verb      = TAG_Lyra_Damage_Message;
Message.Instigator = ...;
Message.Magnitude  = Damage;
UGameplayMessageSubsystem::Get(this).BroadcastMessage(TAG_Lyra_Damage_Message, Message);
```

AttributeSet은 수신자(HUD, 킬피드 등)를 전혀 모른다. 각 수신자는 독립적으로 `RegisterListener`로 구독한다.
