# 뷰포트 추가 / 제거

> 출처:  
> `Engine/Source/Runtime/UMG/Public/Blueprint/UserWidget.h` (line 344~361)  
> `Engine/Source/Runtime/UMG/Private/UserWidget.cpp`  
> `Engine/Source/Runtime/UMG/Public/Blueprint/GameViewportSubsystem.h`

---

## 화면에 띄우는 두 가지 방법

### AddToViewport — 전체 뷰포트

```cpp
MyWidget->AddToViewport(0);   // ZOrder 기본값 0
```

모든 플레이어가 보는 단일 뷰포트에 추가된다.  
싱글플레이어 또는 공통 HUD에 사용한다.

내부적으로 `UGameViewportSubsystem::AddWidget()`을 호출하고, 이 시점에 `TakeWidget()`이 실행돼 Slate 위젯이 생성된다.

### AddToPlayerScreen — 특정 플레이어의 화면

```cpp
MyWidget->AddToPlayerScreen(0);   // 이 위젯을 소유한 LocalPlayer의 화면에만 추가
```

스플릿스크린 게임에서 플레이어별 독립 HUD를 만들 때 사용한다.  
`UUserWidget`이 어느 `ULocalPlayer`에 속하는지는 `CreateWidget()` 호출 시 결정된다.

```cpp
// PlayerController 기준으로 LocalPlayer가 결정됨
UMyWidget* HUD = CreateWidget<UMyWidget>(PlayerController, UMyWidget::StaticClass());
HUD->AddToPlayerScreen();   // PlayerController의 LocalPlayer 화면에만 표시
```

---

## ZOrder — 위젯 겹침 순서

```cpp
MyWidget->AddToViewport(10);   // ZOrder = 10 → 더 위에 표시
```

ZOrder가 높을수록 다른 위젯 위에 그려진다.  
같은 ZOrder면 나중에 추가된 위젯이 위에 온다.

일반적인 ZOrder 관례:

| ZOrder 범위 | 용도 |
|-------------|------|
| 0 ~ 9 | 배경, 게임 HUD |
| 10 ~ 49 | 일반 UI (인벤토리, 메뉴) |
| 50 ~ 99 | 팝업, 다이얼로그 |
| 100+ | 시스템 UI, 페이드 오버레이 |

---

## 화면에서 제거

```cpp
MyWidget->RemoveFromParent();   // 현재 권장 방식 (UE 5.1+)
```

`RemoveFromViewport()`는 UE 5.1에서 deprecated됐다.  
`RemoveFromParent()`를 사용한다.

`RemoveFromParent()`를 호출하면:
1. Slate 위젯 트리에서 제거
2. `NativeDestruct()` 호출
3. SObjectWidget의 UUserWidget 보호 해제

위젯 UObject 자체는 아직 살아있다.  
UPROPERTY로 참조가 남아있으면 GC되지 않는다.  
다시 `AddToViewport()`를 호출하면 `NativeConstruct()`가 다시 불려 재사용할 수 있다.

---

## IsInViewport — 현재 표시 중인지 확인

```cpp
if (MyWidget->IsInViewport())
{
    MyWidget->RemoveFromParent();
}
```

---

## 위젯 위치/크기 조정

뷰포트에 추가한 후에도 위치·크기를 조정할 수 있다.

```cpp
// 뷰포트 내 위치 설정 (픽셀 좌표)
MyWidget->SetPositionInViewport(FVector2D(100, 200));

// 뷰포트 내 크기 설정
MyWidget->SetDesiredSizeInViewport(FVector2D(400, 300));

// 앵커 설정 (정규화 좌표 0~1)
MyWidget->SetAnchorsInViewport(FAnchors(0.5f, 0.5f));   // 화면 중앙 기준

// 정렬 피벗 설정 (위젯 자신의 0~1 좌표)
MyWidget->SetAlignmentInViewport(FVector2D(0.5f, 0.5f));  // 위젯 중심이 앵커에 맞춤
```

---

## 전체 패턴 예시

```cpp
// 위젯 생성 (Initialize 호출)
UPROPERTY()
UMyHUDWidget* HUDWidget;

HUDWidget = CreateWidget<UMyHUDWidget>(GetWorld(), UMyHUDWidget::StaticClass());

// 화면에 추가 (Construct 호출)
HUDWidget->AddToViewport();

// ... 게임 진행 ...

// 일시적으로 숨기기 — 제거하지 않고 가시성만 변경
HUDWidget->SetVisibility(ESlateVisibility::Collapsed);

// 다시 보이기
HUDWidget->SetVisibility(ESlateVisibility::Visible);

// 완전히 제거 (Destruct 호출)
HUDWidget->RemoveFromParent();
HUDWidget = nullptr;   // UPROPERTY 참조 해제 → 다음 GC에서 수거
```

> **참고**  
> 숨기기/보이기는 `RemoveFromParent()` + `AddToViewport()`보다 `SetVisibility()`가 훨씬 싸다.  
> Construct/Destruct 호출 오버헤드와 Slate 위젯 재생성 비용이 없다.

---

## 내 노트

