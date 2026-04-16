# Meta Attribute 패턴

## 왜 필요한가?

`Health`를 GE가 직접 수정하게 두면 중간에 끼어들 자리가 없다.
예를 들어 데미지 면역, 팀킬 방지, 피격 이벤트 브로드캐스트 같은 로직을 넣으려면
GE 계산 결과를 **한 번 가로채서 처리**할 중간 단계가 필요하다.

그 중간 단계 역할을 하는 것이 Meta Attribute다.

```
GE 적용
  └─ ExecCalc에서 최종 데미지량 계산
        └─ Damage (Meta Attribute) 에 값을 씀   ← 중간 단계
              └─ PostGameplayEffectExecute 호출
                    ├─ 면역 체크, 팀 체크 등 추가 로직
                    ├─ Health -= Damage           ← 실제 반영
                    ├─ 피격 이벤트 브로드캐스트
                    └─ Damage = 0.0f             ← 초기화
```

## 특징

| 항목 | 일반 Attribute | Meta Attribute |
|------|--------------|----------------|
| 복제 | O (클라이언트에도 전달) | X (서버 전용) |
| 영속성 | 값이 유지됨 | 처리 후 반드시 0으로 초기화 |
| GE Modifier 노출 | O | `HideFromModifiers`로 숨김 |
| 용도 | 실제 게임 상태 표현 | 계산 결과의 임시 전달용 |

## 선언 (LyraHealthSet.h)

```cpp
// 일반 Attribute — 복제됨, 클라이언트도 이 값을 봄
UPROPERTY(BlueprintReadOnly, ReplicatedUsing = OnRep_Health, Category = "Lyra|Health",
    Meta = (HideFromModifiers, AllowPrivateAccess = true))
FGameplayAttributeData Health;

// Meta Attribute — 복제 없음, HideFromModifiers로 GE 에디터에서 숨김
// ExecCalc가 결과를 여기에 쓰고, PostGameplayEffectExecute에서 Health에 반영 후 0으로 초기화
UPROPERTY(BlueprintReadOnly, Category="Lyra|Health",
    Meta=(HideFromModifiers, AllowPrivateAccess=true))
FGameplayAttributeData Damage;

UPROPERTY(BlueprintReadOnly, Category="Lyra|Health",
    Meta=(AllowPrivateAccess=true))
FGameplayAttributeData Healing;
```

## ExecCalc에서 Meta Attribute에 쓰기 (LyraDamageExecution.cpp)

ExecCalc는 Source(공격자)의 `BaseDamage`를 Capture해서 거리/물리재질 감쇠, 팀 체크 등을
적용한 뒤, 최종값을 Target(피격자)의 `Damage` Meta Attribute에 출력한다.

```cpp
// LyraDamageExecution.cpp

// ① Source의 BaseDamage Attribute를 Capture하겠다고 등록
struct FDamageStatics
{
    FGameplayEffectAttributeCaptureDefinition BaseDamageDef;

    FDamageStatics()
    {
        // Source ASC의 BaseDamage를, Spec 생성 시점의 스냅샷으로 캡처
        BaseDamageDef = FGameplayEffectAttributeCaptureDefinition(
            ULyraCombatSet::GetBaseDamageAttribute(),
            EGameplayEffectAttributeCaptureSource::Source,
            /*bSnapshot=*/true
        );
    }
};

void ULyraDamageExecution::Execute_Implementation(...) const
{
    // ② 캡처된 BaseDamage 값 읽기
    float BaseDamage = 0.0f;
    ExecutionParams.AttemptCalculateCapturedAttributeMagnitude(
        DamageStatics().BaseDamageDef, EvaluateParameters, BaseDamage);

    // ③ 거리 감쇠, 물리재질 감쇠, 팀 체크 등 계산
    float DamageDone = BaseDamage * DistanceAttenuation * PhysicalMaterialAttenuation
                       * DamageInteractionAllowedMultiplier;

    // ④ 최종값을 Damage (Meta Attribute) 에 출력
    //    Health를 직접 건드리지 않고 Damage에 쓰는 것이 핵심
    if (DamageDone > 0.0f)
    {
        OutExecutionOutput.AddOutputModifier(
            FGameplayModifierEvaluatedData(
                ULyraHealthSet::GetDamageAttribute(),  // Meta Attribute
                EGameplayModOp::Additive,
                DamageDone
            )
        );
    }
}
```

> `BaseDamage`(CombatSet)와 `Damage`(HealthSet)는 다른 Attribute다.
> - `BaseDamage`: 공격자가 보유한 "공격력" 수치. 아이템/버프로 변할 수 있고 복제된다.
> - `Damage`: 피격자가 이번 GE에서 받을 데미지량. 순간적인 임시값이고 복제하지 않는다.

## PostGameplayEffectExecute에서 처리 (LyraHealthSet.cpp)

ExecCalc가 `Damage`에 값을 쓰면 즉시 `PostGameplayEffectExecute`가 호출된다.
여기서 실제 `Health` 반영, 이벤트 브로드캐스트, 사망 처리를 모두 수행하고 `Damage`를 0으로 초기화한다.

```cpp
// LyraHealthSet.cpp

void ULyraHealthSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
    if (Data.EvaluatedData.Attribute == GetDamageAttribute())
    {
        // 피격 메시지 브로드캐스트 (UI 히트마커, 킬피드 등에서 수신)
        if (Data.EvaluatedData.Magnitude > 0.0f)
        {
            FLyraVerbMessage Message;
            Message.Verb      = TAG_Lyra_Damage_Message;
            Message.Instigator = Data.EffectSpec.GetEffectContext().GetEffectCauser();
            Message.Magnitude  = Data.EvaluatedData.Magnitude;
            UGameplayMessageSubsystem::Get(GetWorld()).BroadcastMessage(Message.Verb, Message);
        }

        // Health에서 Damage만큼 차감하고 클램프
        SetHealth(FMath::Clamp(GetHealth() - GetDamage(), MinimumHealth, GetMaxHealth()));

        // Meta Attribute 반드시 0으로 초기화 — 다음 GE에 누적되면 안 됨
        SetDamage(0.0f);
    }
    else if (Data.EvaluatedData.Attribute == GetHealingAttribute())
    {
        SetHealth(FMath::Clamp(GetHealth() + GetHealing(), MinimumHealth, GetMaxHealth()));
        SetHealing(0.0f);  // 동일하게 초기화
    }

    // 사망 감지
    if ((GetHealth() <= 0.0f) && !bOutOfHealth)
    {
        OnOutOfHealth.Broadcast(...);
    }
    bOutOfHealth = (GetHealth() <= 0.0f);
}
```

## 전체 데미지 흐름 요약

```
[공격자 ASC]                         [피격자 ASC]
CombatSet::BaseDamage = 50           HealthSet::Health = 100
                                     HealthSet::Damage = 0  (Meta)

GE 발동
  └─ LyraDamageExecution::Execute()
        ├─ Source의 BaseDamage(50) Capture
        ├─ DistanceAttenuation(0.8) 적용
        ├─ 팀 체크 통과 (multiplier = 1.0)
        └─ DamageDone = 40.0
              └─ Damage Meta Attribute += 40   → Damage = 40

PostGameplayEffectExecute 호출
  ├─ 피격 메시지 브로드캐스트 (Magnitude = 40)
  ├─ Health = Clamp(100 - 40, 0, 100) = 60
  └─ Damage = 0.0f  ← 초기화

결과: Health = 60, Damage = 0
```
