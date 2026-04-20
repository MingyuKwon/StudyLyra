# CameraMode 시스템

> 소스: `Camera/LyraCameraMode.h/cpp`, `Camera/LyraCameraComponent.h/cpp`, `Camera/LyraCameraMode_ThirdPerson.h`

---

## 왜 필요한가

단순 방식은 CameraComponent 안에 조건문을 쌓는다:

```cpp
if (bIsADS) SetCamera(ADSPos);
else if (bIsCrouching) SetCamera(CrouchPos);
else SetCamera(NormalPos);
```

모드가 늘어날수록 조건문이 복잡해지고 모드 간 전환 보간도 수동이 된다.  
Lyra는 이를 **모드 오브젝트 + 블렌드 스택**으로 해결한다.

---

## 전체 구조

```
ULyraCameraComponent          (UCameraComponent 서브클래스, Pawn에 붙는 컴포넌트)
    │
    ├── DetermineCameraModeDelegate   ← 매 프레임 "어떤 모드 쓸지" 외부에 위임
    │         (바인딩 주체: ULyraHeroComponent)
    │
    └── ULyraCameraModeStack          ← 활성 모드 블렌드 스택
            ├── [0] ULyraCameraMode_ADS        (BlendWeight: 0.7, 블렌딩 중)
            └── [1] ULyraCameraMode_ThirdPerson (BlendWeight: 1.0, 기저)
```

---

## 매 프레임 흐름

```
PlayerController → GetCameraView(DeltaTime)
    │
    ▼
ULyraCameraComponent::GetCameraView()
    ├── UpdateCameraModes()
    │       DetermineCameraModeDelegate.Execute()
    │         → TSubclassOf<ULyraCameraMode> 반환
    │         → CameraModeStack->PushCameraMode(CameraMode)
    │
    ├── CameraModeStack->EvaluateStack(DeltaTime)
    │       각 모드 UpdateCameraMode()  (View 계산 + BlendWeight 진행)
    │       BlendStack()  →  바닥부터 위로 블렌딩  →  FLyraCameraModeView 최종값
    │
    └── DesiredView에 최종 Location / Rotation / FOV 기록
        PC->SetControlRotation(CameraModeView.ControlRotation)  ← PC 동기화
```

---

## ULyraCameraMode — 단일 카메라 행동

### Outer = ULyraCameraComponent

모드 인스턴스는 `NewObject<ULyraCameraMode>(CameraComponent, CameraModeClass)` 로 생성된다.  
Outer가 CameraComponent이므로 모드가 자신이 속한 컴포넌트를 항상 안다:

```cpp
// LyraCameraMode.cpp:66
ULyraCameraComponent* ULyraCameraMode::GetLyraCameraComponent() const
{
    return CastChecked<ULyraCameraComponent>(GetOuter());
}
```

### 매 프레임 UpdateCameraMode() = 두 단계

```cpp
void ULyraCameraMode::UpdateCameraMode(float DeltaTime)
{
    UpdateView(DeltaTime);      // 이 모드의 카메라 위치/회전 계산
    UpdateBlending(DeltaTime);  // BlendAlpha 진행 → BlendWeight 계산
}
```

### UpdateView 기본 구현

```cpp
void ULyraCameraMode::UpdateView(float DeltaTime)
{
    FVector PivotLocation = GetPivotLocation();   // 캐릭터 눈 높이 (웅크림 보정 포함)
    FRotator PivotRotation = GetPivotRotation();  // Pawn->GetViewRotation()

    PivotRotation.Pitch = FMath::ClampAngle(PivotRotation.Pitch, ViewPitchMin, ViewPitchMax);

    View.Location = PivotLocation;
    View.Rotation = PivotRotation;
    View.ControlRotation = View.Rotation;
    View.FieldOfView = FieldOfView;
}
```

### GetPivotLocation — 웅크림 보정

```cpp
// LyraCameraMode.cpp:99
const float DefaultHalfHeight = CapsuleCompCDO->GetUnscaledCapsuleHalfHeight();
const float ActualHalfHeight  = CapsuleComp->GetUnscaledCapsuleHalfHeight();
const float HeightAdjustment  = (DefaultHalfHeight - ActualHalfHeight) + CDO->BaseEyeHeight;

return Character->GetActorLocation() + FVector::UpVector * HeightAdjustment;
// 앉아도 카메라가 캐릭터 눈 위치를 자연스럽게 따라감
```

### 블렌드 설정 프로퍼티

```cpp
UPROPERTY(EditDefaultsOnly) float BlendTime;             // 기본 0.5초
UPROPERTY(EditDefaultsOnly) ELyraCameraModeBlendFunction BlendFunction;  // 기본 EaseOut
UPROPERTY(EditDefaultsOnly) float BlendExponent;         // 기본 4.0
```

| BlendFunction | 특성 |
|---------------|------|
| `Linear` | 일정 속도 |
| `EaseIn` | 빠르게 시작 → 부드럽게 도달 |
| `EaseOut` | 부드럽게 시작 → 빠르게 도달 (기본값) |
| `EaseInOut` | 양쪽 부드럽게 |

### CameraTypeTag — GAS 연동

```cpp
UPROPERTY(EditDefaultsOnly)
FGameplayTag CameraTypeTag;
```

모드에 GameplayTag를 달면 게임 코드가 구체 클래스 이름 없이 현재 카메라 상태를 조회할 수 있다:

```cpp
float Weight;
FGameplayTag Tag;
CameraComponent->GetBlendInfo(Weight, Tag);
// Tag == "Camera.Mode.ADS" && Weight > 0.9 → ADS 거의 완료
// → GA에서 조준 중 정확도 보너스 부여 등에 활용
```

---

## ULyraCameraModeStack — 블렌드 스택

### PushCameraMode

```cpp
// LyraCameraMode.cpp:264
void ULyraCameraModeStack::PushCameraMode(TSubclassOf<ULyraCameraMode> CameraModeClass)
{
    ULyraCameraMode* CameraMode = GetCameraModeInstance(CameraModeClass);  // 인스턴스 재사용
    // 이미 스택 최상단이면 무시
    // 이미 스택 내부에 있으면 현재 기여도 계산 후 제거
    // BlendTime > 0이고 스택이 비어있지 않으면 블렌딩 시작, 아니면 가중치 1.0으로 즉시
    CameraModeStack.Insert(CameraMode, 0);       // 최상단에 삽입
    CameraModeStack.Last()->SetBlendWeight(1.0f); // 바닥은 항상 1.0
}
```

**인스턴스 풀링**: `CameraModeInstances`에 한 번 만든 모드를 보관하고 재사용한다.  
같은 모드를 재Push해도 새 오브젝트를 생성하지 않는다.

### BlendStack — 바닥→꼭대기 방향 블렌딩

```cpp
// LyraCameraMode.cpp:407
OutCameraModeView = CameraModeStack.Last()->GetCameraModeView();  // 바닥 모드 100%로 시작

for (int32 StackIndex = StackSize - 2; StackIndex >= 0; --StackIndex)
{
    OutCameraModeView.Blend(CameraModeStack[StackIndex]->GetCameraModeView(),
                            CameraModeStack[StackIndex]->GetBlendWeight());
}
```

BlendWeight = 1.0에 도달한 모드가 생기면 그 아래 모드들은 불필요하므로 `OnDeactivation()` 후 제거된다.

---

## DetermineCameraModeDelegate — 결정 위임

`ULyraCameraComponent`는 어떤 모드를 써야 하는지 스스로 결정하지 않는다.

```cpp
// LyraCameraComponent.h:44
FLyraCameraModeDelegate DetermineCameraModeDelegate;
// DECLARE_DELEGATE_RetVal(TSubclassOf<ULyraCameraMode>, FLyraCameraModeDelegate)
```

```cpp
// LyraCameraComponent.cpp:91
void ULyraCameraComponent::UpdateCameraModes()
{
    if (DetermineCameraModeDelegate.IsBound())
    {
        if (const TSubclassOf<ULyraCameraMode> CameraMode = DetermineCameraModeDelegate.Execute())
        {
            CameraModeStack->PushCameraMode(CameraMode);
        }
    }
}
```

`ULyraHeroComponent`가 이 델리게이트를 바인딩한다.  
**"어떤 모드 쓸지"는 캐릭터 쪽 로직이 결정** — 카메라 시스템은 결정을 모른다.

---

## ULyraCameraMode_ThirdPerson — 실제 구현체

`ULyraCameraMode`를 상속해 `UpdateView`를 오버라이드한다.

```cpp
UCLASS(Abstract, Blueprintable)
class ULyraCameraMode_ThirdPerson : public ULyraCameraMode
```

| 프로퍼티 | 역할 |
|----------|------|
| `TargetOffsetCurve` | 피치 각도 → 카메라 오프셋 커브 (위 볼 땐 당기고, 아래 볼 땐 밀고) |
| `bPreventPenetration` | 벽 관통 방지 레이캐스트 ON/OFF |
| `bDoPredictiveAvoidance` | 벽에 가까워지기 전 미리 당기기 |
| `PenetrationAvoidanceFeelers` | 관통 감지 레이 배열 (index 0: 기본, 1+: 예측용) |
| `CrouchOffsetBlendMultiplier` | 웅크림 오프셋 블렌딩 속도 |

`Blueprintable`이므로 에디터에서 커브와 오프셋을 DataAsset처럼 조정 가능하다.
