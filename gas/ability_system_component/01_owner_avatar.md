# Owner/Avatar 구조

> 소스: `LyraPlayerState.h`, `LyraCharacter.h`

---

## Owner Actor vs Avatar Actor

| 역할 | 설명 | Lyra 구현체 |
|---|---|---|
| **Owner** | ASC를 소유하는 Actor. GE/Ability 권한 보유. 네트워크 소유자. | `ALyraPlayerState` |
| **Avatar** | 실제 게임 세계에 존재하는 Actor. 물리/애니메이션 처리. | `ALyraCharacter` |

둘을 분리하면 리스폰 시 새 Character가 생겨도 PlayerState(ASC/Attribute)는 그대로 유지된다.

---

## 왜 PlayerState에 ASC를 두는가

```
리스폰 발생
    │
    ▼
ALyraCharacter 소멸 (Avatar)
    │
    ▼
새 ALyraCharacter 스폰 (새 Avatar)
    │
    ▼
InitAbilityActorInfo(PlayerState, NewCharacter) 재호출
    │
    ▼
ASC, Attribute, ActiveGE → 모두 보존됨 (PlayerState는 살아있음)
```

리스폰 불필요한 NPC나 환경 오브젝트는 Owner = Avatar 동일하게 해도 됨.

---

## Lyra에서의 구현

### ALyraPlayerState

```cpp
// LyraPlayerState.h
class ALyraPlayerState : public AModularPlayerState,
                         public IAbilitySystemInterface,   // GetAbilitySystemComponent() 구현
                         public ILyraTeamAgentInterface
{
    // IAbilitySystemInterface 구현
    virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;

    // ASC 직접 접근용
    ULyraAbilitySystemComponent* GetLyraAbilitySystemComponent() const { return AbilitySystemComponent; }

private:
    UPROPERTY(VisibleAnywhere, Category = "Lyra|PlayerState")
    TObjectPtr<ULyraAbilitySystemComponent> AbilitySystemComponent;

    UPROPERTY()
    TObjectPtr<const ULyraPawnData> PawnData;
};
```

`PostInitializeComponents()`에서 ASC 생성 + ReplicationMode 설정:
```cpp
void ALyraPlayerState::PostInitializeComponents()
{
    Super::PostInitializeComponents();
    
    // AbilitySystemComponent는 PlayerState 생성자에서 CreateDefaultSubobject로 생성
    // ReplicationMode: Mixed (플레이어 제어 캐릭터)
    AbilitySystemComponent->SetReplicationMode(EGameplayEffectReplicationMode::Mixed);
    AbilitySystemComponent->InitAbilityActorInfo(this, GetPawn());
}
```

### ALyraCharacter

```cpp
// LyraCharacter는 IAbilitySystemInterface를 직접 구현하지 않음
// → ULyraPawnExtensionComponent를 통해 PlayerState의 ASC를 참조
```

Character 자체가 ASC를 소유하지 않고, PawnExtensionComponent가 PlayerState에서 ASC를 가져온다.

---

## IAbilitySystemInterface

Owner Actor에 이 인터페이스를 구현해야 GAS가 ASC를 찾을 수 있다.

```cpp
// 외부에서 ASC를 얻는 방법
UAbilitySystemComponent* ASC = UAbilitySystemBlueprintLibrary::GetAbilitySystemComponent(Actor);
// 내부적으로 Cast<IAbilitySystemInterface>(Actor)->GetAbilitySystemComponent() 호출
```

---

## 같은 Owner에 ASC 여러 개 — 비추천

GASDoc Dave Ratti: `IAbilitySystemInterface::GetAbilitySystemComponent()`가 하나의 ASC만 반환할 수 있어서,
여러 개 있으면 어느 쪽을 반환할지 애매해진다. 비추천.
