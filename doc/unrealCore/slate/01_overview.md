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

## 왜 Slate를 처음부터 UObject로 만들지 않았는가

### 이유 1 — GC는 UI에 근본적으로 안 맞는다

UObject의 GC는 "언젠가 정리해줄게"이지, "지금 당장 없애줄게"가 아니다.

UI 위젯은 생성·소멸이 극단적으로 잦다.  
스크롤 리스트가 아이템 1000개를 스크롤하면 위젯이 수백 번 생겼다 없어진다.  
GC 기반이면 사라진 줄 알았던 위젯들이 다음 GC 사이클까지 메모리에 쌓이고,  
GC가 돌 때 프레임 히치가 생긴다.

TSharedRef는 마지막 참조가 끊기는 즉시 소멸한다 — 예측 가능하고 결정론적이다.

GC 마크 단계는 살아있는 UObject를 전부 순회한다.  
HUD 위젯이 500개면 매 GC마다 500개를 스캔한다.  
게임 중 HUD가 복잡할수록 GC 부하가 커지는 구조가 된다.

### 이유 2 — 에디터가 UObject 시스템보다 먼저 떠야 한다

언리얼 에디터 자체가 Slate로 만들어져 있다.  
엔진 기동 순서를 보면:

```
엔진 기동
  → UObject/GC 시스템 초기화    ← 이게 끝나야 UObject를 쓸 수 있음
  → 에디터 창 표시              ← 근데 로딩 중에도 화면을 띄워야 함
```

UObject 시스템이 초기화되는 동안 로딩 화면, 스플래시, 에디터 기본 창을 띄워야 한다.  
UI가 UObject에 의존하면 "UObject가 준비되기 전에 UObject 기반 UI를 띄워라"는  
닭이 먼저냐 달걀이 먼저냐 문제가 생긴다.

Slate는 UObject에 의존하지 않으므로 엔진 초기화 최초 단계부터 쓸 수 있다.

### 역사적 순서

Slate(UE4, 2012) → UMG(UE4, 2014).  
Slate가 먼저 나왔고, UMG는 "Slate를 블루프린트에서 쓸 수 있게 해달라"는 요구로 나중에 추가된 레이어다.

UObject로 만들지 않은 게 아니라, **UObject로 만들 수 없는 곳에서 써야 하는 시스템**이라 처음부터 분리 설계됐다.

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

