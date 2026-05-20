# 고급 GA 기능

> **GASDoc**: 4.6.13~16 · [원문 참조](../cache/GASDocument_Readme.md)

---

<a name="concepts-ga-batching"></a>
#### Ability Batching이란 무엇이며, 히트스캔 총에서 어떻게 RPC를 최적화하는가?

전통적인 `Gameplay Ability` 라이프사이클은 클라이언트에서 서버로 최소 2~3회의 RPC를 발생시킨다.

1. `CallServerTryActivateAbility()`
2. `ServerSetReplicatedTargetData()` (선택)
3. `ServerEndAbility()`

한 프레임 내에 이 모든 작업이 하나의 원자적 그룹으로 수행된다면, 2~3개의 RPC를 하나의 RPC로 묶어 최적화할 수 있다. `GAS`에서는 이 RPC 최적화 기법을 `Ability Batching`이라고 한다. `Ability Batching`의 대표적인 사용 사례는 히트스캔 총이다. 히트스캔 총은 어빌리티를 활성화하고, 라인 트레이스를 수행하고, `TargetData`를 서버로 전송하고, 어빌리티를 종료하는 모든 동작을 한 프레임 내의 하나의 원자적 그룹으로 처리한다. [GASShooter](https://github.com/tranek/GASShooter) 샘플 프로젝트는 히트스캔 총에 이 기법을 적용하여 시연한다.

반자동 총은 최적 사례로서 `CallServerTryActivateAbility()`, `ServerSetReplicatedTargetData()`(총알 히트 결과), `ServerEndAbility()`를 세 개의 RPC 대신 하나의 RPC로 묶는다.

완전 자동/버스트 총의 경우, 첫 번째 총알에 대해 `CallServerTryActivateAbility()`와 `ServerSetReplicatedTargetData()`를 두 개의 RPC 대신 하나의 RPC로 배치한다. 이후 각 총알은 자체적인 `ServerSetReplicatedTargetData()` RPC를 사용한다. 마지막으로 총 발사가 멈출 때 `ServerEndAbility()`가 별도의 RPC로 전송된다. 이는 최악의 경우로, 두 개의 RPC 절약이 아닌 첫 번째 총알에서 하나의 RPC만 절약된다.

`Ability Batching`은 ASC에서 기본적으로 비활성화되어 있다. `Ability Batching`을 활성화하려면 `ShouldDoServerAbilityRPCBatch()`를 override하여 true를 반환하도록 한다.

```c++
virtual bool ShouldDoServerAbilityRPCBatch() const override { return true; }
```

`Ability Batching`이 활성화된 상태에서, 배치하려는 어빌리티를 활성화하기 전에 반드시 `FScopedServerAbilityRPCBatcher` 구조체를 먼저 생성해야 한다. 이 특수 구조체는 그 스코프 안에서 뒤따르는 모든 어빌리티를 배치하려고 시도한다. `FScopedServerAbilityRPCBatcher`가 스코프를 벗어나면, 이후 활성화되는 어빌리티는 배치 시도를 하지 않는다. `FScopedServerAbilityRPCBatcher`는 배치 가능한 각 함수에 특수 코드를 두어 RPC 전송 호출을 가로채고, 대신 메시지를 배치 구조체에 패킹하는 방식으로 동작한다. `FScopedServerAbilityRPCBatcher`가 스코프를 벗어날 때, `UAbilitySystemComponent::EndServerAbilityRPCBatch()`에서 자동으로 이 배치 구조체를 서버에 RPC로 전송한다. 서버는 `UAbilitySystemComponent::ServerAbilityRPCBatch_Internal(FServerAbilityRPCBatch& BatchInfo)`에서 배치 RPC를 수신한다. `BatchInfo` 파라미터에는 어빌리티가 종료되어야 하는지 여부, 활성화 시점에 입력이 눌렸는지 여부, 포함된 경우 `TargetData`가 담겨 있다. 배치가 올바르게 동작하는지 확인하려면 이 함수에 브레이크포인트를 설정하는 것이 좋다. 또는 cvar `AbilitySystem.ServerRPCBatching.Log 1`을 사용하여 Ability Batching 전용 로깅을 활성화할 수 있다.

이 메커니즘은 C++에서만 사용할 수 있으며, `FGameplayAbilitySpecHandle`로만 어빌리티를 활성화할 수 있다.

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

GASShooter는 반자동 총과 완전 자동 총 모두에 동일한 배치 `GameplayAbility`를 재사용하며, 이 어빌리티는 직접 `EndAbility()`를 호출하지 않는다(종료는 현재 발사 모드에 따라 플레이어 입력을 관리하고 배치 어빌리티를 호출하는 로컬 전용 어빌리티에서 처리된다). 모든 RPC는 `FScopedServerAbilityRPCBatcher` 스코프 내에서 발생해야 하므로, 제어/관리용 로컬 전용 어빌리티가 이 어빌리티의 `EndAbility()` 호출을 배치할지(반자동) 배치하지 않을지(완전 자동, `EndAbility()`는 나중에 자체 RPC로 처리)를 지정할 수 있도록 `EndAbilityImmediately` 파라미터를 제공한다.

GASShooter는 앞서 언급한 로컬 전용 어빌리티에서 배치 어빌리티를 트리거할 수 있도록 Blueprint 노드를 노출한다.

<a name="concepts-ga-netsecuritypolicy"></a>
#### GA의 Net Security Policy 옵션들은 클라이언트의 어떤 시도를 어떻게 차단하는가?

`GameplayAbility`의 `NetSecurityPolicy`는 해당 어빌리티가 네트워크 상에서 어디에서 실행되어야 하는지를 결정한다. 제한된 어빌리티를 실행하려는 클라이언트의 시도로부터 보호 기능을 제공한다.

| `NetSecurityPolicy`     | 설명                                                                                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ClientOrServer`        | 보안 제한 없음. 클라이언트 또는 서버 모두 이 어빌리티의 실행과 종료를 자유롭게 트리거할 수 있다.                                                           |
| `ServerOnlyExecution`   | 이 어빌리티의 실행을 요청하는 클라이언트는 서버에서 무시된다. 클라이언트는 여전히 서버에 어빌리티의 취소 또는 종료를 요청할 수 있다.                        |
| `ServerOnlyTermination` | 이 어빌리티의 취소 또는 종료를 요청하는 클라이언트는 서버에서 무시된다. 클라이언트는 여전히 어빌리티의 실행을 요청할 수 있다.                              |
| `ServerOnly`            | 서버가 이 어빌리티의 실행과 종료를 모두 제어한다. 클라이언트의 모든 요청은 무시된다.                                                                       |

---

