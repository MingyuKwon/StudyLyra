# 히트마커 확인 시스템 — LyraWeaponStateComponent

> 출처: `Source/LyraGame/Weapons/LyraWeaponStateComponent.cpp`

히트마커는 클라이언트가 먼저 **"미확인"** 상태로 표시하고,  
서버 검증 이후 **확정 또는 취소**된다.

---

## 구조

```
UnconfirmedServerSideHitMarkers   TArray<FLyraServerSideHitMarkerBatch>
  └─ FLyraServerSideHitMarkerBatch
        ├─ UniqueId                ← TargetData.UniqueId와 매칭용
        └─ Markers[]              ← 화면 공간 히트 위치 목록
              ├─ Location          ← 스크린 좌표
              ├─ bShowAsSuccess    ← 적팀 여부
              └─ HitZone           ← 머리/몸통 등 (PhysicalMaterial 태그)

LastWeaponDamageScreenLocations   TArray<FLyraScreenSpaceHitLocation>
  └─ 서버 확정된 히트들만 저장 → 히트마커 UI에서 읽음
```

---

## AddUnconfirmedServerSideHitMarkers (클라이언트)

```cpp
void ULyraWeaponStateComponent::AddUnconfirmedServerSideHitMarkers(
    const FGameplayAbilityTargetDataHandle& InTargetData,
    const TArray<FHitResult>& FoundHits)
{
    // UniqueId로 새 배치 생성
    FLyraServerSideHitMarkerBatch& Batch =
        UnconfirmedServerSideHitMarkers.Emplace_GetRef(InTargetData.UniqueId);

    for (const FHitResult& Hit : FoundHits)
    {
        FVector2D HitScreenLocation;
        // 월드 좌표 → 스크린 좌표 변환
        UGameplayStatics::ProjectWorldToScreen(OwnerPC, Hit.Location, HitScreenLocation);

        FLyraScreenSpaceHitLocation& Entry = Batch.Markers.AddDefaulted_GetRef();
        Entry.Location = HitScreenLocation;
        Entry.bShowAsSuccess = ShouldShowHitAsSuccess(Hit);  // 적팀 여부

        // PhysicalMaterial 태그로 히트 존(머리/몸통 등) 파악
        if (const UPhysicalMaterialWithTags* PhysMat = ...)
            Entry.HitZone = MaterialTag;  // Gameplay.Zone.* 태그
    }
}
```

발사 직후 **서버 응답을 기다리지 않고** 미확인 배치를 바로 저장한다.

---

## ClientConfirmTargetData (서버 → 클라이언트 RPC)

```cpp
void ULyraWeaponStateComponent::ClientConfirmTargetData_Implementation(
    uint16 UniqueId, bool bSuccess, const TArray<uint8>& HitReplaces)
{
    // UniqueId로 해당 배치 찾기
    for (FLyraServerSideHitMarkerBatch& Batch : UnconfirmedServerSideHitMarkers)
    {
        if (Batch.UniqueId == UniqueId)
        {
            if (bSuccess && HitReplaces.Num() != Batch.Markers.Num())
            {
                int32 HitLocationIndex = 0;
                for (const FLyraScreenSpaceHitLocation& Entry : Batch.Markers)
                {
                    // HitReplaces에 없는 것 = 서버가 유효하다고 인정한 히트
                    if (!HitReplaces.Contains(HitLocationIndex) && Entry.bShowAsSuccess)
                        LastWeaponDamageScreenLocations.Add(Entry);
                    ++HitLocationIndex;
                }
            }
            // 미확인 배치 제거
            UnconfirmedServerSideHitMarkers.RemoveAt(i);
            break;
        }
    }
}
```

### HitReplaces 의미

| 상황 | HitReplaces |
|------|-------------|
| 전부 유효 | 빈 배열 |
| 일부 거부 | 거부된 히트의 인덱스들 |
| 전부 거부 | Markers.Num()과 동일한 수 → `bSuccess` 조건 불통과 |

---

## 흐름 요약

```
[발사 직후 — 클라이언트]
StartRangedWeaponTargeting()
  → AddUnconfirmedServerSideHitMarkers()
      UniqueId=3, Markers=[{스크린위치A, 성공}, {스크린위치B, 성공}]
      → UnconfirmedServerSideHitMarkers에 추가

[서버]
TargetData 수신 → 히트 검증
  → HitReplaces = [1]  (인덱스1 거부)
  → ClientConfirmTargetData(UniqueId=3, true, [1]) RPC 전송

[클라이언트]
ClientConfirmTargetData 수신
  → UniqueId=3 배치 찾음
  → 인덱스0 유효 → LastWeaponDamageScreenLocations에 추가 → 히트마커 UI 표시
  → 인덱스1 거부 → 스킵
  → 배치 제거
```

---

## 내 노트

히트마커는 **UI 피드백 전용**이다. 실제 데미지는 서버가 TargetData를 받아서 GE로 직접 적용한다.  
클라이언트가 먼저 히트마커를 그리는 이유는 응답성(느낌) 때문이고, 서버 검증으로 최종 확정된다.  
`UniqueId`가 배치 매칭의 핵심 — `WeaponStateComponent->GetUnconfirmedServerSideHitMarkerCount()`가 발사 시점마다 다른 ID를 만든다.
