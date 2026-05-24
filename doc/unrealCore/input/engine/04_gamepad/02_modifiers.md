# 패드 입력 보정 — 데드존과 InputModifier

> 출처: `C:/UE_5.7/Engine/Plugins/EnhancedInput/Source/EnhancedInput/Public/InputModifiers.h`  
>        `C:/UE_5.7/Engine/Source/Runtime/Engine/Private/UserInterface/PlayerInput.cpp`

---

## 데드존 — 스틱이 0으로 돌아오지 않는 문제

물리 스틱은 손을 떼도 정확히 (0, 0)으로 돌아오지 않는다.  
그대로 두면 캐릭터가 미세하게 표류한다.

**해결: `UInputModifierDeadZone`** — InputAction에 붙이는 Modifier

```
LowerThreshold = 0.2  → 이 값 미만은 0으로 처리
UpperThreshold = 1.0  → 이 값 초과는 1로 클램프
LowerThreshold ~ UpperThreshold 사이 → 0 ~ 1로 재매핑
```

### 데드존 타입 3종

| 타입 | 동작 | 사용 시점 |
|------|------|-----------|
| `Axial` | X축, Y축 각각 독립 적용 | 단순한 경우, UE4 호환 |
| `Radial` (Smoothed) | 두 축을 원형으로 함께 처리 + 경계 부드럽게 | 대부분의 게임, 추천 |
| `UnscaledRadial` | 원형 처리하되 경계에서 갑자기 점프 | 레트로 느낌, 특수 용도 |

**Axial의 문제점:** X와 Y를 각각 처리하면 대각선 방향에서 데드존이 마름모꼴이 된다.  
스틱을 조금 기울이면 한 축은 죽고 한 축만 살아있는 현상이 생긴다.  
**Radial이 권장되는 이유:** 원형으로 처리하면 어느 방향으로 기울여도 일관된 감도가 나온다.

---

## InputModifier 체인 — 패드에 자주 쓰이는 것들

InputAction에 Modifier를 여러 개 순서대로 붙인다.  
앞 Modifier의 출력이 다음 Modifier의 입력이 된다.

| Modifier | 역할 | 패드 사용 예 |
|----------|------|-------------|
| `DeadZone` | 소음 제거, 재매핑 | 스틱 필수 |
| `Scalar` | 감도 배율 (축별 독립) | 스틱 감도 조정 |
| `ScaleByDeltaTime` | 값 × DeltaTime | 스틱 카메라 Rate 변환 |
| `Negate` | 축 반전 | Y축 반전 옵션 |
| `SwizzleAxis` | 축 순서 교체 | 1D 입력을 Y축으로 올릴 때 |
| `ResponseCurveExponential` | 지수 곡선 감도 | 느리게 시작 → 빠르게 끝 느낌 |
| `ResponseCurveUser` | 커스텀 커브 | 섬세한 감도 튜닝 |
| `Smooth` | 여러 프레임에 걸쳐 평균화 | 입력 떨림 제거 |
| `FOVScaling` | 줌 배율에 따라 감도 조정 | 조준 시 감도 자동 감소 |

---

## 마우스 vs 스틱 — 처리 방식 차이

```cpp
// 마우스: 델타 그대로 → Modifier 없음 (OS가 이미 델타 처리)
void Input_LookMouse(const FInputActionValue& Value)
{
    Pawn->AddControllerYawInput(Value.Get<FVector2D>().X);
}

// 스틱: 기울기(-1~1) × Rate × DeltaSeconds → Rate 변환
void Input_LookStick(const FInputActionValue& Value)
{
    Pawn->AddControllerYawInput(Value.X * 300.0f * World->GetDeltaSeconds());
}
```

마우스는 OS 레벨에서 이미 이동량(델타)을 주기 때문에 DeltaSeconds가 필요 없다.  
스틱은 "지금 얼마나 기울어져 있나"이므로, 시간을 곱해야 프레임 독립적인 회전이 된다.
