# 고급 GA 기능

> **GASDoc**: 4.6.13~16 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-batching"></a>
#### Ability Batching이란 무엇이며, 히트스캔 총에서 어떻게 RPC를 최적화하는가?

전통적인 GA 라이프사이클은 클라이언트에서 서버로 최소 2~3회의 RPC를 발생시킨다:

1. `CallServerTryActivateAbility()`
2. `ServerSetReplicatedTargetData()` (선택)
3. `ServerEndAbility()`

한 프레임 내에 이 모든 작업이 하나의 원자적 그룹으로 수행된다면 이 RPC들을 하나로 묶을 수 있다. 이것이 **Ability Batching**이다.

대표 사용 사례인 히트스캔 총은 어빌리티 활성화 → 라인 트레이스 → TargetData 서버 전송 → 어빌리티 종료를 한 프레임 내에 처리하므로 3개 RPC를 1개로 줄일 수 있다.

활성화 방법:
```c++
virtual bool ShouldDoServerAbilityRPCBatch() const override { return true; }
```

배치하려는 어빌리티 활성화 전에 `FScopedServerAbilityRPCBatcher`를 생성한다. 이 구조체가 스코프 안에서 뒤따르는 어빌리티의 RPC를 가로채 패킹하고, 스코프를 벗어날 때 하나의 RPC로 서버에 전송한다.

```c++
bool UGSAbilitySystemComponent::BatchRPCTryActivateAbility(FGameplayAbilitySpecHandle InAbilityHandle, bool EndAbilityImmediately)
{
    bool AbilityActivated = false;
    if (InAbilityHandle.IsValid())
    {
        FScopedServerAbilityRPCBatcher GSAbilityRPCBatcher(this, InAbilityHandle);
        AbilityActivated = TryActivateAbility(InAbilityHandle, true);

        if (EndAbilityImmediately)
        {
            FGameplayAbilitySpec* AbilitySpec = FindAbilitySpecFromHandle(InAbilityHandle);
            if (AbilitySpec)
            {
                UGSGameplayAbility* GSAbility = Cast<UGSGameplayAbility>(AbilitySpec->GetPrimaryInstance());
                GSAbility->ExternalEndAbility();
            }
        }
        return AbilityActivated;
    }
    return AbilityActivated;
}
```

| 총 종류 | 배치 효과 |
|---|---|
| 반자동 총 | `Activate` + `TargetData` + `End` → 1개 RPC |
| 완전 자동 총 | 첫 번째 총알에서 `Activate` + `TargetData` → 1개 RPC 절약. 이후 각 총알은 개별 RPC |

이 메커니즘은 **C++에서만** 사용 가능하며, `FGameplayAbilitySpecHandle`로만 어빌리티를 활성화할 수 있다.

<a name="concepts-ga-netsecuritypolicy"></a>
#### GA의 Net Security Policy 옵션들은 클라이언트의 어떤 시도를 어떻게 차단하는가?

제한된 어빌리티를 실행하려는 클라이언트의 시도를 서버에서 차단하는 설정이다.

| NetSecurityPolicy | 설명 |
|---|---|
| `ClientOrServer` | 보안 제한 없음. 클라이언트 또는 서버 모두 실행과 종료를 자유롭게 트리거할 수 있다. |
| `ServerOnlyExecution` | 클라이언트의 실행 요청은 서버에서 무시된다. 취소/종료 요청은 허용된다. |
| `ServerOnlyTermination` | 클라이언트의 취소/종료 요청은 서버에서 무시된다. 실행 요청은 허용된다. |
| `ServerOnly` | 서버가 실행과 종료 모두를 제어한다. 클라이언트의 모든 요청이 무시된다. |

---
