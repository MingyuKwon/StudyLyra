# Slate 개요

> 출처:  
> `Engine/Source/Runtime/SlateCore/Public/Widgets/SWidget.h`  
> `Engine/Source/Runtime/Slate/Public/Framework/Application/SlateApplication.h`

Slate는 언리얼 엔진의 저수준 UI 프레임워크다.  
에디터 UI와 인게임 HUD 모두를 이 시스템 위에서 렌더링한다.

---

## Slate란 무엇인가

Slate는 **순수 C++ UI 시스템**이다.  
UObject를 상속하지 않고, GC(가비지 컬렉터)와 무관하게 동작한다.

핵심 특성:

| 특성 | 내용 |
|------|------|
| 메모리 관리 | TSharedRef / TSharedPtr — 참조 카운팅, GC 없음 |
| 렌더링 | FSlateDrawElement 명령 버퍼 → RHI → GPU |
| 플랫폼 | 플랫폼 독립적. Windows/Mac/Linux/콘솔 동일 코드 |
| 스레딩 | 게임 스레드에서 실행. 렌더 스레드는 별도 |

언리얼 에디터 자체(콘텐츠 브라우저, 디테일 패널, 뷰포트 탭 등)가 Slate로 만들어져 있다.

---

## UMG란 무엇인가

UMG(Unreal Motion Graphics)는 **Slate 위에 올린 UObject 래퍼**다.

```
[블루프린트 / 게임 코드]
        │
        ▼
    UMG (UWidget / UUserWidget)     ← UObject, 블루프린트 노출, GC 통합
        │ TakeWidget()              ← 이 호출 시점에 Slate 위젯 생성
        ▼
    Slate (SWidget 파생)            ← 실제 레이아웃 + 렌더링 담당
        │
        ▼
    RHI / GPU
```

UMG가 추가로 제공하는 것:
- 블루프린트 노출 (UFUNCTION, UPROPERTY)
- 언리얼 GC와의 통합
- 에디터 위젯 디자이너 (WBP 에디터)
- 애니메이션 시스템 (UWidgetAnimation)

---

## 왜 두 레이어가 존재하는가

Slate는 UObject가 아니므로 다음이 불가능하다:
- 블루프린트에서 직접 사용
- UPROPERTY로 노출
- 언리얼 GC로 생명주기 관리
- `CreateWidget<T>()` 패턴

UMG가 이 문제를 해결한다.  
`UWidget`은 UObject이므로 블루프린트에서 쓸 수 있고, 내부에서 Slate 위젯을 생성해 위임한다.

```
[디자이너가 보는 것]          [실제로 동작하는 것]
 WBP의 Button 위젯     →      UButton (UObject)
                                   │ TakeWidget()
                                   ▼
                              SButton (SWidget)  ← 여기서 실제 렌더
```

---

## 언제 Slate를 직접 쓰는가

대부분의 게임 코드는 UMG를 쓴다.  
Slate를 직접 쓰는 경우:

1. **에디터 플러그인/툴** — UMG 에디터 없이 SWidget으로 직접 구성
2. **성능 임계 HUD** — UObject 오버헤드 없이 순수 Slate로 구성
3. **SObjectWidget 같은 브릿지 레이어 구현** — Slate ↔ UMG 연결 코드
4. **엔진 코어 UI** — LoadingScreen, Splash, 콘솔 등

---

## 내 노트

