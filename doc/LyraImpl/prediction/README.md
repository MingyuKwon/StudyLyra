# Lyra Prediction 시스템

> 출처: `Source/LyraGame/Weapons/LyraGameplayAbility_RangedWeapon.cpp`  
>        `Source/LyraGame/Weapons/LyraWeaponStateComponent.cpp`

Lyra의 히트스캔 발사는 **클라이언트 예측(Client-side Prediction)** 구조로 동작한다.  
클라이언트가 먼저 트레이스하고 즉시 결과를 반영한 뒤, 서버가 나중에 검증한다.

## 문서 목록

| 문서 | 내용 |
|------|------|
| [01. 발사 Prediction 흐름](01_ranged_weapon.md) | ActivateAbility → StartTargeting → OnTargetDataReady → 서버 검증 |
| [02. 히트마커 확인 시스템](02_hit_markers.md) | Unconfirmed → ClientConfirm 구조 |

---

## 핵심 설계 원칙

**클라이언트가 먼저, 서버가 검증한다.**

```
클라이언트                              서버
──────────────────────────────────────────────────────
발사 입력
  → 로컬 라인 트레이스 (즉시)
  → 히트마커 즉시 표시 (미확인)
  → 이펙트/데미지 즉시 적용 (예측)
  → TargetData → ServerSetReplicatedTargetData RPC ──→ TargetData 수신
                                                        히트 검증
                                                        ClientConfirmTargetData RPC
클라이언트 히트마커 확정 ←───────────────────────────────
```

서버의 검증 결과에 따라 히트마커가 확정되거나 취소되지만,  
데미지 자체는 서버가 TargetData를 수신한 뒤 직접 적용한다.

---

## 관련 클래스

| 클래스 | 역할 |
|--------|------|
| `ULyraGameplayAbility_RangedWeapon` | 발사 GA — prediction 흐름 전체 조율 |
| `ULyraWeaponStateComponent` | 히트마커 미확인/확정 관리 (PlayerController에 붙음) |
| `FLyraGameplayAbilityTargetData_SingleTargetHit` | 히트 1개의 데이터 (HitResult + CartridgeID) |
| `FLyraGameplayEffectContext` | GE 컨텍스트 확장 (CartridgeID, AbilitySource) |
