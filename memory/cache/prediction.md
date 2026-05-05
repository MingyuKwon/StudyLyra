# Lyra Prediction 시스템

> 소스를 직접 열람하여 확인한 분석 캐시. 추측 없음.

---

## Lyra 히트스캔 발사 Prediction

> 출처: `Source/LyraGame/Weapons/LyraGameplayAbility_RangedWeapon.cpp`  
>        `Source/LyraGame/Weapons/LyraWeaponStateComponent.cpp`  
> 상세 문서: `doc/LyraImpl/prediction/`

### 핵심 설계

클라이언트가 먼저 로컬 트레이스 → 즉시 결과 반영 → TargetData를 서버로 전송 → 서버 검증.  
WaitTargetData AbilityTask 미사용. `StartRangedWeaponTargeting()`(BP 호출)에서 직접 트레이스 후 콜백 호출.

### 발사 흐름 4단계

1. **ActivateAbility**: `AbilityTargetDataSetDelegate`에 `OnTargetDataReadyCallback` 등록 (PredictionKey 키)
2. **StartRangedWeaponTargeting** (클라): `FScopedPredictionWindow` → `PerformLocalTargeting()` → `FGameplayAbilityTargetDataHandle` 생성 → `AddUnconfirmedServerSideHitMarkers()` → `OnTargetDataReadyCallback()` 직접 호출
3. **OnTargetDataReadyCallback**:
   - 클라: `CallServerSetReplicatedTargetData` RPC 전송
   - 서버: 히트 검증 → `ClientConfirmTargetData` RPC
   - 공통: `CommitAbility()` → `AddSpread()` → `OnRangedWeaponTargetDataReady()` BP 이벤트
4. **EndAbility**: delegate 제거 + `ConsumeClientReplicatedTargetData()`

### 히트마커 확인 시스템

- `AddUnconfirmedServerSideHitMarkers()`: 발사 즉시 스크린 좌표 기반 미확인 배치 등록 (UniqueId로 식별)
- `ClientConfirmTargetData(UniqueId, bSuccess, HitReplaces)`: 서버→클라 RPC. HitReplaces = 거부된 히트 인덱스 배열
- 유효한 히트만 `LastWeaponDamageScreenLocations`에 추가 → UI 표시

### 주요 타입

- `FLyraGameplayAbilityTargetData_SingleTargetHit`: HitResult + CartridgeID
- `FLyraServerSideHitMarkerBatch`: UniqueId + 스크린 좌표 배열
- `CartridgeID`: `FMath::Rand()`로 생성, 같은 연사의 탄들을 묶는 ID
