# 고급 GA 기능

> **GASDoc**: 4.6.13~16 · [원문 참조](../cache/GASDocument_Readme.md)

---

## 개념 요약

<a name="concepts-ga-leveling"></a>
#### 4.6.13 Leveling Up Abilities
There are two common methods for leveling up an ability:

| Level Up Method                            | Description                                                                                                                                                                                                      |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ungrant and Regrant at the New Level       | Ungrant (remove) the `GameplayAbility` from the `ASC` and regrant it back at the next level on the server. This terminates the `GameplayAbility` if it was active at the time.                                   |
| Increase the `GameplayAbilitySpec's` Level | On the server, find the `GameplayAbilitySpec`, increase its level, and mark it dirty so that replicates to the owning client. This method does not terminate the `GameplayAbility` if it was active at the time. |

The main difference between the two methods is if you want active `GameplayAbilities` to be canceled at the time of level up. You will most likely use both methods depending on your `GameplayAbilities`. I recommend adding a `bool` to your `UGameplayAbility` subclass specifying which method to use.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-sets"></a>
#### 4.6.14 Ability Sets
`GameplayAbilitySets` are convenience `UDataAsset` classes for holding input bindings and lists of startup `GameplayAbilities` for Characters with logic to grant the `GameplayAbilities`. Subclasses can also include extra logic or properties. Paragon had a `GameplayAbilitySet` per hero that included all of their given `GameplayAbilities`.

I find this class to be unnecessary at least given what I've seen of it so far. The Sample Project handles all of the functionality of `GameplayAbilitySets` inside of the `GDCharacterBase` and its subclasses.

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-batching"></a>
#### 4.6.15 Ability Batching
Traditional `Gameplay Ability` lifecycle involves a minimum of two or three RPCs from the client to the server.

1. `CallServerTryActivateAbility()`
1. `ServerSetReplicatedTargetData()` (Optional)
1. `ServerEndAbility()`

If a `GameplayAbility` performs all of these actions in one atomic grouping in a frame, we can optimize this workflow to batch (combine) all two or three RPCs into one RPC. `GAS` refers to this RPC optimization as `Ability Batching`. The common example of when to use `Ability Batching` is for hitscan guns. Hitscan guns activate, do a line trace, send the [`TargetData`](#concepts-targeting-data) to the server, and end the ability all in one atomic group in one frame. The [GASShooter](https://github.com/tranek/GASShooter) sample project demonstrates this technique for its hitscan guns.

Semi-Automatic guns are the best case scenario and batch the `CallServerTryActivateAbility()`, `ServerSetReplicatedTargetData()` (the bullet hit result), and `ServerEndAbility()` into one RPC instead of three RPCs.

Full-Automatic/Burst guns batch `CallServerTryActivateAbility()` and `ServerSetReplicatedTargetData()` for the first bullet into one RPC instead of two RPCs. Each subsequent bullet is its own `ServerSetReplicatedTargetData()` RPC. Finally, `ServerEndAbility()` is sent as a separate RPC when the gun stops firing. This is a worst case scenario where we only save one RPC on the first bullet instead of two. This scenario could have also been implemented with activating the ability via a [`Gameplay Event`](#concepts-ga-data) which would send the bullet's `TargetData` in with the `EventPayload` to the server from the client. The downside of the latter approach is that the `TargetData` would have to be generated externally to the ability whereas the batching approach generates the `TargetData` inside of the ability.

`Ability Batching` is disabled by default on the [`ASC`](#concepts-asc). To enable `Ability Batching`, override `ShouldDoServerAbilityRPCBatch()` to return true:

```c++
virtual bool ShouldDoServerAbilityRPCBatch() const override { return true; }
```

Now that `Ability Batching` is enabled, before activating abilities that you want batched, you must create a `FScopedServerAbilityRPCBatcher` struct beforehand. This special struct will try to batch any abilities following it within its scope. Once the `FScopedServerAbilityRPCBatcher` falls out of scope, any abilities activated will not try to batch. `FScopedServerAbilityRPCBatcher` works by having special code in each of the functions that can be batched that intercepts the call from sending the RPC and instead packs the message into a batch struct. When `FScopedServerAbilityRPCBatcher` falls out of scope, it automatically RPCs this batch struct to the server in `UAbilitySystemComponent::EndServerAbilityRPCBatch()`. The server receives the batch RPC in `UAbilitySystemComponent::ServerAbilityRPCBatch_Internal(FServerAbilityRPCBatch& BatchInfo)`. The `BatchInfo` parameter will contain flags for if the ability should end and if input was pressed at the time of activation and the `TargetData` if that was included. This is a good function to put a breakpoint on to confirm that your batching is working properly. Alternatively, use the cvar `AbilitySystem.ServerRPCBatching.Log 1` to enable special ability batching logging.

This mechanism can only be done in C++ and can only activate abilities by their `FGameplayAbilitySpecHandle`.

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

GASShooter reuses the same batched `GameplayAbility` for semi-automatic and full-automatic guns which never directly call `EndAbility()` (it is handled outside of the ability by a local-only ability that manages player input and the call to the batched ability based on the current firemode). Since all of the RPCs must happen within the scope of the `FScopedServerAbilityRPCBatcher`, I provide the `EndAbilityImmediately` parameter so that the controlling/managing local-only can specify whether this ability should batch the `EndAbility()` call (semi-automatic), or not batch the `EndAbility()` call (full-automatic) and the `EndAbility()` call will happen sometime later in its own RPC.

GASShooter exposes a Blueprint node to allow batching abilities which the aforementioned local-only ability uses to trigger the batched ability.

![Activate Batched Ability](https://github.com/tranek/GASDocumentation/raw/master/Images/batchabilityactivate.png)

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-ga-netsecuritypolicy"></a>
#### 4.6.16 Net Security Policy
A `GameplayAbility`'s `NetSecurityPolicy` determines where should an ability execute on the network. It provides protection from clients attempting to execute restricted abilities.

| `NetSecurityPolicy`     | Description                                                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ClientOrServer`        | No security requirements. Client or server can trigger execution and termination of this ability freely.                                           |
| `ServerOnlyExecution`   | A client requesting execution of this ability will be ignored by the server. Clients can still request that the server cancel or end this ability. |
| `ServerOnlyTermination` | A client requesting cancellation or ending of this ability will be ignored by the server. Clients can still request execution of the ability.      |
| `ServerOnly`            | Server controls both execution and termination of this ability. A client making any requests will be ignored.                                      |

**[⬆ Back to Top](#table-of-contents)**

<a name="concepts-at"></a>
### 4.7 Ability Tasks

---

## 내 분석
