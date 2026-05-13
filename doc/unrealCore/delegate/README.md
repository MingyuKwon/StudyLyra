# Delegate

> 소스:  
> `Engine/Source/Runtime/Core/Public/Delegates/Delegate.h`  
> `Engine/Source/Runtime/Core/Public/Delegates/MulticastDelegateBase.h`

타입 안전한 함수 포인터·콜백 시스템.  
특정 이벤트가 발생했을 때 미리 등록해둔 함수들을 호출하는 데 사용한다.

---

## 종류

| 종류 | 바인딩 수 | Blueprint | 직렬화 | 주요 용도 |
|------|---------|-----------|--------|----------|
| Delegate (Single) | 1개 | X | X | 단일 콜백 |
| Multicast Delegate | 여러 개 | X | X | 다수 리스너 |
| Dynamic Delegate | 1개 | O | O | Blueprint 단일 콜백 |
| Dynamic Multicast Delegate | 여러 개 | O | O | Blueprint 이벤트 (가장 흔함) |

---

## 목차

| 파일 | 내용 |
|------|------|
| [01_declaration.md](01_declaration.md) | 선언 매크로 — DECLARE_DELEGATE / MULTICAST / DYNAMIC 4종 |
| [02_binding.md](02_binding.md) | 바인딩 + 실행 API — Bind/Add/Execute/Broadcast, AddDynamic 제약 |
| [03_internals.md](03_internals.md) | 내부 구현 — IDelegateInstance, InlineStorage, FName+ProcessEvent, 복사·이동 |
| [04_safety.md](04_safety.md) | 안전성 — Dynamic vs Non-Dynamic 비교, 바인딩 안전성, 수명 관리 |
